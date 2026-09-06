const std = @import("std");
const gl = @import("opengl.zig");
const gtk = @import("gtk.zig");

const vertex_shader_source: [*:0]const u8 =
    \\#version 150 core
    \\in vec2 position;
    \\in vec3 color;
    \\out vec3 vertex_color;
    \\uniform vec2 pan;
    \\uniform float zoom;
    \\void main() {
    \\    gl_Position = vec4(position * zoom + pan, 0.0, 1.0);
    \\    vertex_color = color;
    \\}
;

const fragment_shader_source: [*:0]const u8 =
    \\#version 150 core
    \\in vec3 vertex_color;
    \\out vec4 out_color;
    \\void main() {
    \\    out_color = vec4(vertex_color, 1.0);
    \\}
;

const Vertex = extern struct {
    position: [2]f32,
    color: [3]f32,
};

const Renderer = struct {
    program: gl.GLuint = 0,
    vao: gl.GLuint = 0,
    vbo: gl.GLuint = 0,
    pan_location: gl.GLint = -1,
    zoom_location: gl.GLint = -1,

    fn init(self: *Renderer) !void {
        const vertex_shader = try compileShader(gl.VERTEX_SHADER, vertex_shader_source);
        defer gl.glDeleteShader(vertex_shader);
        const fragment_shader = try compileShader(gl.FRAGMENT_SHADER, fragment_shader_source);
        defer gl.glDeleteShader(fragment_shader);

        self.program = gl.glCreateProgram();
        gl.glAttachShader(self.program, vertex_shader);
        gl.glAttachShader(self.program, fragment_shader);
        gl.glLinkProgram(self.program);

        var linked: gl.GLint = 0;
        gl.glGetProgramiv(self.program, gl.LINK_STATUS, &linked);
        if (linked == gl.FALSE) {
            printProgramLog(self.program);
            return error.ProgramLinkFailed;
        }

        self.pan_location = gl.glGetUniformLocation(self.program, "pan");
        self.zoom_location = gl.glGetUniformLocation(self.program, "zoom");

        gl.glGenVertexArrays(1, &self.vao);
        gl.glBindVertexArray(self.vao);
        gl.glGenBuffers(1, &self.vbo);
        gl.glBindBuffer(gl.ARRAY_BUFFER, self.vbo);
        gl.glBufferData(gl.ARRAY_BUFFER, @sizeOf(Vertex) * 15, null, gl.DYNAMIC_DRAW);

        gl.glEnableVertexAttribArray(0);
        gl.glVertexAttribPointer(0, 2, gl.FLOAT, 0, @sizeOf(Vertex), null);
        gl.glEnableVertexAttribArray(1);
        gl.glVertexAttribPointer(1, 3, gl.FLOAT, 0, @sizeOf(Vertex), @ptrFromInt(@offsetOf(Vertex, "color")));
    }

    fn draw(self: *Renderer, state: *const State) void {
        const vertices = makeVertices(state);
        gl.glClearColor(state.clear_color[0], state.clear_color[1], state.clear_color[2], 1.0);
        gl.glClear(gl.COLOR_BUFFER_BIT);

        gl.glUseProgram(self.program);
        gl.glUniform2f(self.pan_location, state.pan[0], state.pan[1]);
        gl.glUniform1f(self.zoom_location, state.zoom);
        gl.glBindVertexArray(self.vao);
        gl.glBindBuffer(gl.ARRAY_BUFFER, self.vbo);
        gl.glBufferSubData(gl.ARRAY_BUFFER, 0, @sizeOf(@TypeOf(vertices)), &vertices);
        gl.glDrawArrays(gl.TRIANGLES, 0, vertices.len);
    }

    fn deinit(self: *Renderer) void {
        if (self.vbo != 0) gl.glDeleteBuffers(1, &self.vbo);
        if (self.vao != 0) gl.glDeleteVertexArrays(1, &self.vao);
        if (self.program != 0) gl.glDeleteProgram(self.program);
        self.* = .{};
    }
};

const State = struct {
    app: *gtk.GtkApplication,
    area: ?*gtk.GtkGLArea = null,
    renderer: Renderer = .{},
    renderer_ready: bool = false,
    width: f32 = 1,
    height: f32 = 1,
    pan: [2]f32 = .{ 0, 0 },
    zoom: f32 = 1,
    cursor: [2]f32 = .{ 0, 0 },
    last_pointer: [2]f64 = .{ 0, 0 },
    dragging: bool = false,
    alternate_colors: bool = false,
    clear_color: [3]f32 = .{ 0.035, 0.045, 0.07 },

    fn queueRender(self: *State) void {
        if (self.area) |area| gtk.gtk_gl_area_queue_render(area);
    }

    fn resetView(self: *State) void {
        self.pan = .{ 0, 0 };
        self.zoom = 1;
        self.clear_color = .{ 0.035, 0.045, 0.07 };
    }
};

pub fn main() !void {
    const app = gtk.gtk_application_new("dev.zig.opengl-tutorial", gtk.G_APPLICATION_DEFAULT_FLAGS) orelse
        return error.ApplicationCreationFailed;
    defer gtk.g_object_unref(app);

    var state = State{ .app = app };
    connect(app, "activate", activate, &state);
    _ = gtk.g_application_run(app, 0, null);
}

fn activate(app: *gtk.GtkApplication, user_data: gtk.gpointer) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(user_data.?));
    const window: *gtk.GtkWindow = @ptrCast(gtk.gtk_application_window_new(app));
    gtk.gtk_window_set_title(window, "Zig + OpenGL input playground");
    gtk.gtk_window_set_default_size(window, 900, 600);

    const area_widget = gtk.gtk_gl_area_new();
    const area: *gtk.GtkGLArea = @ptrCast(area_widget);
    state.area = area;
    gtk.gtk_gl_area_set_required_version(area, 3, 2);
    gtk.gtk_widget_set_focusable(area_widget, 1);

    connect(area, "render", render, state);
    connect(area, "resize", resize, state);
    connect(area, "unrealize", unrealize, state);

    const motion = gtk.gtk_event_controller_motion_new();
    connect(motion, "motion", mouseMotion, state);
    gtk.gtk_widget_add_controller(area_widget, motion);

    const click = gtk.gtk_gesture_click_new();
    gtk.gtk_gesture_single_set_button(@ptrCast(click), 0);
    connect(click, "pressed", mousePressed, state);
    connect(click, "released", mouseReleased, state);
    gtk.gtk_widget_add_controller(area_widget, @ptrCast(click));

    const scroll = gtk.gtk_event_controller_scroll_new(gtk.GTK_EVENT_CONTROLLER_SCROLL_VERTICAL);
    connect(scroll, "scroll", mouseScroll, state);
    gtk.gtk_widget_add_controller(area_widget, scroll);

    const keys = gtk.gtk_event_controller_key_new();
    connect(keys, "key-pressed", keyPressed, state);
    gtk.gtk_widget_add_controller(area_widget, keys);

    gtk.gtk_window_set_child(window, area_widget);
    gtk.gtk_window_present(window);
    _ = gtk.gtk_widget_grab_focus(area_widget);
}

fn render(_: *gtk.GtkGLArea, _: *gtk.GdkGLContext, user_data: gtk.gpointer) callconv(.c) gtk.gboolean {
    const state: *State = @ptrCast(@alignCast(user_data.?));
    if (!state.renderer_ready) {
        state.renderer.init() catch |err| {
            std.debug.print("OpenGL setup failed: {s}\n", .{@errorName(err)});
            return 0;
        };
        state.renderer_ready = true;
    }
    state.renderer.draw(state);
    return 1;
}

fn resize(area: *gtk.GtkGLArea, width: c_int, height: c_int, user_data: gtk.gpointer) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(user_data.?));
    const scale = gtk.gtk_widget_get_scale_factor(@ptrCast(area));
    state.width = @floatFromInt(@max(width, 1));
    state.height = @floatFromInt(@max(height, 1));
    gl.glViewport(0, 0, width * scale, height * scale);
}

fn unrealize(area: *gtk.GtkGLArea, user_data: gtk.gpointer) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(user_data.?));
    if (!state.renderer_ready) return;
    gtk.gtk_gl_area_make_current(area);
    state.renderer.deinit();
    state.renderer_ready = false;
}

fn mouseMotion(_: *gtk.GtkEventController, x: f64, y: f64, user_data: gtk.gpointer) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(user_data.?));
    if (state.dragging) {
        state.pan[0] += @floatCast(2.0 * (x - state.last_pointer[0]) / state.width);
        state.pan[1] -= @floatCast(2.0 * (y - state.last_pointer[1]) / state.height);
    }
    state.last_pointer = .{ x, y };

    const screen_x: f32 = @floatCast(2.0 * x / state.width - 1.0);
    const screen_y: f32 = @floatCast(1.0 - 2.0 * y / state.height);
    state.cursor = .{
        (screen_x - state.pan[0]) / state.zoom,
        (screen_y - state.pan[1]) / state.zoom,
    };
    state.queueRender();
}

fn mousePressed(_: *gtk.GtkGestureClick, _: c_int, x: f64, y: f64, user_data: gtk.gpointer) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(user_data.?));
    state.dragging = true;
    state.alternate_colors = !state.alternate_colors;
    state.last_pointer = .{ x, y };
    state.queueRender();
}

fn mouseReleased(_: *gtk.GtkGestureClick, _: c_int, _: f64, _: f64, user_data: gtk.gpointer) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(user_data.?));
    state.dragging = false;
}

fn mouseScroll(_: *gtk.GtkEventController, _: f64, dy: f64, user_data: gtk.gpointer) callconv(.c) gtk.gboolean {
    const state: *State = @ptrCast(@alignCast(user_data.?));
    const factor: f32 = if (dy < 0) 1.1 else 1.0 / 1.1;
    state.zoom = std.math.clamp(state.zoom * factor, 0.25, 4.0);
    state.queueRender();
    return 1;
}

fn keyPressed(_: *gtk.GtkEventController, key: c_uint, _: c_uint, _: c_uint, user_data: gtk.gpointer) callconv(.c) gtk.gboolean {
    const state: *State = @ptrCast(@alignCast(user_data.?));
    const step: f32 = 0.08;
    switch (key) {
        gtk.GDK_KEY_Escape => gtk.g_application_quit(state.app),
        gtk.GDK_KEY_Left, gtk.GDK_KEY_a => state.pan[0] -= step,
        gtk.GDK_KEY_Right, gtk.GDK_KEY_d => state.pan[0] += step,
        gtk.GDK_KEY_Up, gtk.GDK_KEY_w => state.pan[1] += step,
        gtk.GDK_KEY_Down, gtk.GDK_KEY_s => state.pan[1] -= step,
        gtk.GDK_KEY_r => state.resetView(),
        gtk.GDK_KEY_space => state.clear_color = if (state.clear_color[0] < 0.1)
            .{ 0.18, 0.04, 0.07 }
        else
            .{ 0.035, 0.045, 0.07 },
        else => return 0,
    }
    state.queueRender();
    return 1;
}

fn makeVertices(state: *const State) [15]Vertex {
    const triangle_colors: [3][3]f32 = if (state.alternate_colors)
        .{ .{ 1.0, 0.35, 0.2 }, .{ 0.9, 0.2, 0.75 }, .{ 0.25, 0.8, 1.0 } }
    else
        .{ .{ 0.95, 0.25, 0.3 }, .{ 0.2, 0.85, 0.5 }, .{ 0.25, 0.5, 1.0 } };
    const cx = state.cursor[0];
    const cy = state.cursor[1];
    const marker_size = 0.025 / state.zoom;

    return .{
        .{ .position = .{ -0.72, -0.35 }, .color = triangle_colors[0] },
        .{ .position = .{ -0.15, -0.35 }, .color = triangle_colors[1] },
        .{ .position = .{ -0.43, 0.55 }, .color = triangle_colors[2] },

        .{ .position = .{ 0.12, -0.35 }, .color = .{ 0.95, 0.7, 0.15 } },
        .{ .position = .{ 0.7, -0.35 }, .color = .{ 0.95, 0.7, 0.15 } },
        .{ .position = .{ 0.7, 0.35 }, .color = .{ 0.3, 0.75, 0.95 } },
        .{ .position = .{ 0.12, -0.35 }, .color = .{ 0.95, 0.7, 0.15 } },
        .{ .position = .{ 0.7, 0.35 }, .color = .{ 0.3, 0.75, 0.95 } },
        .{ .position = .{ 0.12, 0.35 }, .color = .{ 0.65, 0.35, 0.95 } },

        .{ .position = .{ cx, cy + marker_size }, .color = .{ 1, 1, 1 } },
        .{ .position = .{ cx - marker_size, cy }, .color = .{ 1, 1, 1 } },
        .{ .position = .{ cx, cy - marker_size }, .color = .{ 1, 1, 1 } },
        .{ .position = .{ cx, cy + marker_size }, .color = .{ 1, 1, 1 } },
        .{ .position = .{ cx, cy - marker_size }, .color = .{ 1, 1, 1 } },
        .{ .position = .{ cx + marker_size, cy }, .color = .{ 1, 1, 1 } },
    };
}

fn compileShader(kind: gl.GLenum, source: [*:0]const u8) !gl.GLuint {
    const shader = gl.glCreateShader(kind);
    gl.glShaderSource(shader, 1, &source, null);
    gl.glCompileShader(shader);

    var compiled: gl.GLint = 0;
    gl.glGetShaderiv(shader, gl.COMPILE_STATUS, &compiled);
    if (compiled == gl.FALSE) {
        printShaderLog(shader);
        gl.glDeleteShader(shader);
        return error.ShaderCompilationFailed;
    }
    return shader;
}

fn printShaderLog(shader: gl.GLuint) void {
    var log: [1024]gl.GLchar = undefined;
    var length: gl.GLsizei = 0;
    gl.glGetShaderInfoLog(shader, log.len, &length, &log);
    std.debug.print("Shader error: {s}\n", .{log[0..@intCast(length)]});
}

fn printProgramLog(program: gl.GLuint) void {
    var log: [1024]gl.GLchar = undefined;
    var length: gl.GLsizei = 0;
    gl.glGetProgramInfoLog(program, log.len, &length, &log);
    std.debug.print("Program error: {s}\n", .{log[0..@intCast(length)]});
}

fn connect(instance: *anyopaque, signal: [*:0]const u8, callback: anytype, data: gtk.gpointer) void {
    _ = gtk.g_signal_connect_data(instance, signal, @ptrCast(&callback), data, null, gtk.G_CONNECT_DEFAULT);
}
