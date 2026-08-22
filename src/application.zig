const std = @import("std");
const gtk = @import("gtk.zig");
const gl = @import("opengl.zig");
const greeting = @import("greeting.zig");

const window_xml = @embedFile("ui/window.ui");
const debounce_ms = 350;

pub const Application = struct {
    window: ?*gtk.GtkWindow = null,
    name_entry: ?*gtk.GtkEditable = null,
    reset_button: ?*gtk.GtkWidget = null,
    greeting_label: ?*gtk.GtkLabel = null,
    gl_area: ?*gtk.GtkGLArea = null,
    debounce_source: gtk.guint = 0,
    gl_program: gl.GLuint = 0,
    gl_vao: gl.GLuint = 0,
    start_time_us: i64 = 0,
    pointer_x: f32 = 0.5,
    pointer_y: f32 = 0.5,

    pub fn run(self: *Application) void {
        const app = gtk.gtk_application_new(
            "dev.example.zig-gtk-greeting",
            gtk.G_APPLICATION_DEFAULT_FLAGS,
        ) orelse return;
        defer gtk.g_object_unref(app);

        _ = gtk.g_signal_connect_data(
            app,
            "activate",
            @ptrCast(&activate),
            self,
            null,
            gtk.G_CONNECT_DEFAULT,
        );

        _ = gtk.g_application_run(@ptrCast(app), 0, null);
    }

    fn activate(app: *gtk.GtkApplication, user_data: gtk.gpointer) callconv(.c) void {
        const self: *Application = @ptrCast(@alignCast(user_data));

        if (self.window) |window| {
            gtk.gtk_window_present(window);
            return;
        }

        const builder = gtk.gtk_builder_new_from_string(window_xml.ptr, @intCast(window_xml.len));
        defer gtk.g_object_unref(builder);

        self.window = object(gtk.GtkWindow, builder, "main_window") orelse return;
        self.name_entry = object(gtk.GtkEditable, builder, "name_entry") orelse return;
        self.reset_button = object(gtk.GtkWidget, builder, "reset_button") orelse return;
        self.greeting_label = object(gtk.GtkLabel, builder, "greeting_label") orelse return;
        self.gl_area = object(gtk.GtkGLArea, builder, "gl_canvas") orelse return;

        gtk.gtk_window_set_application(self.window.?, app);
        gtk.gtk_gl_area_set_required_version(self.gl_area.?, 3, 2);
        _ = gtk.g_signal_connect_data(
            self.name_entry.?,
            "changed",
            @ptrCast(&nameChanged),
            self,
            null,
            gtk.G_CONNECT_DEFAULT,
        );
        _ = gtk.g_signal_connect_data(
            self.reset_button.?,
            "clicked",
            @ptrCast(&resetClicked),
            self,
            null,
            gtk.G_CONNECT_DEFAULT,
        );
        _ = gtk.g_signal_connect_data(
            self.window.?,
            "destroy",
            @ptrCast(&windowDestroyed),
            self,
            null,
            gtk.G_CONNECT_DEFAULT,
        );
        _ = gtk.g_signal_connect_data(
            self.gl_area.?,
            "realize",
            @ptrCast(&glRealize),
            self,
            null,
            gtk.G_CONNECT_DEFAULT,
        );
        _ = gtk.g_signal_connect_data(
            self.gl_area.?,
            "render",
            @ptrCast(&glRender),
            self,
            null,
            gtk.G_CONNECT_DEFAULT,
        );
        _ = gtk.g_signal_connect_data(
            self.gl_area.?,
            "unrealize",
            @ptrCast(&glUnrealize),
            self,
            null,
            gtk.G_CONNECT_DEFAULT,
        );

        const motion = gtk.gtk_event_controller_motion_new();
        _ = gtk.g_signal_connect_data(
            motion,
            "motion",
            @ptrCast(&pointerMotion),
            self,
            null,
            gtk.G_CONNECT_DEFAULT,
        );
        gtk.gtk_widget_add_controller(@ptrCast(self.gl_area.?), motion);
        _ = gtk.gtk_widget_add_tick_callback(@ptrCast(self.gl_area.?), animationTick, self, null);

        gtk.gtk_window_present(self.window.?);
    }

    fn nameChanged(_: *gtk.GtkEditable, user_data: gtk.gpointer) callconv(.c) void {
        const self: *Application = @ptrCast(@alignCast(user_data));

        if (self.name_entry) |entry| {
            if (self.reset_button) |button| {
                const has_text = std.mem.span(gtk.gtk_editable_get_text(entry)).len != 0;
                gtk.gtk_widget_set_visible(button, if (has_text) 1 else 0);
            }
        }

        if (self.debounce_source != 0) {
            _ = gtk.g_source_remove(self.debounce_source);
        }
        self.debounce_source = gtk.g_timeout_add(debounce_ms, updateGreeting, self);
    }

    fn resetClicked(_: *gtk.GtkWidget, user_data: gtk.gpointer) callconv(.c) void {
        const self: *Application = @ptrCast(@alignCast(user_data));
        const entry = self.name_entry orelse return;

        // Clearing the entry makes GTK show its placeholder text again.
        gtk.gtk_editable_set_text(entry, "");
        if (self.reset_button) |button| gtk.gtk_widget_set_visible(button, 0);
    }

    fn updateGreeting(user_data: gtk.gpointer) callconv(.c) gtk.gboolean {
        const self: *Application = @ptrCast(@alignCast(user_data));
        self.debounce_source = 0;

        const entry = self.name_entry orelse return gtk.G_SOURCE_REMOVE;
        const label = self.greeting_label orelse return gtk.G_SOURCE_REMOVE;
        const name = std.mem.span(gtk.gtk_editable_get_text(entry));
        var buffer: [512]u8 = undefined;
        const text = greeting.format(&buffer, name) catch return gtk.G_SOURCE_REMOVE;
        gtk.gtk_label_set_text(label, text.ptr);

        return gtk.G_SOURCE_REMOVE;
    }

    fn windowDestroyed(_: *gtk.GtkWindow, user_data: gtk.gpointer) callconv(.c) void {
        const self: *Application = @ptrCast(@alignCast(user_data));
        if (self.debounce_source != 0) {
            _ = gtk.g_source_remove(self.debounce_source);
            self.debounce_source = 0;
        }
        self.window = null;
        self.name_entry = null;
        self.reset_button = null;
        self.greeting_label = null;
        self.gl_area = null;
    }

    fn glRealize(area: *gtk.GtkGLArea, user_data: gtk.gpointer) callconv(.c) void {
        const self: *Application = @ptrCast(@alignCast(user_data));
        gtk.gtk_gl_area_make_current(area);

        const vertex_shader = compileShader(gl.VERTEX_SHADER, vertex_source) orelse return;
        defer gl.glDeleteShader(vertex_shader);
        const fragment_shader = compileShader(gl.FRAGMENT_SHADER, fragment_source) orelse return;
        defer gl.glDeleteShader(fragment_shader);

        const program = gl.glCreateProgram();
        gl.glAttachShader(program, vertex_shader);
        gl.glAttachShader(program, fragment_shader);
        gl.glLinkProgram(program);

        var linked: gl.GLint = gl.FALSE;
        gl.glGetProgramiv(program, gl.LINK_STATUS, &linked);
        if (linked == gl.FALSE) {
            printProgramLog(program);
            gl.glDeleteProgram(program);
            return;
        }

        self.gl_program = program;
        gl.glGenVertexArrays(1, &self.gl_vao);
        self.start_time_us = gtk.g_get_monotonic_time();
    }

    fn glRender(area: *gtk.GtkGLArea, _: *gtk.GdkGLContext, user_data: gtk.gpointer) callconv(.c) gtk.gboolean {
        const self: *Application = @ptrCast(@alignCast(user_data));
        if (self.gl_program == 0) return 0;

        var viewport: [4]gl.GLint = undefined;
        gl.glGetIntegerv(gl.VIEWPORT, &viewport);
        const elapsed_us = gtk.g_get_monotonic_time() - self.start_time_us;

        gl.glClearColor(0.025, 0.035, 0.065, 1.0);
        gl.glClear(gl.COLOR_BUFFER_BIT);
        gl.glUseProgram(self.gl_program);
        gl.glUniform1f(gl.glGetUniformLocation(self.gl_program, "u_time"), @as(f32, @floatFromInt(elapsed_us)) / 1_000_000.0);
        gl.glUniform2f(
            gl.glGetUniformLocation(self.gl_program, "u_resolution"),
            @floatFromInt(viewport[2]),
            @floatFromInt(viewport[3]),
        );
        gl.glUniform2f(gl.glGetUniformLocation(self.gl_program, "u_pointer"), self.pointer_x, self.pointer_y);
        gl.glBindVertexArray(self.gl_vao);
        gl.glDrawArrays(gl.TRIANGLES, 0, 3);
        gl.glBindVertexArray(0);
        gl.glUseProgram(0);

        _ = area;
        return 1;
    }

    fn glUnrealize(area: *gtk.GtkGLArea, user_data: gtk.gpointer) callconv(.c) void {
        const self: *Application = @ptrCast(@alignCast(user_data));
        gtk.gtk_gl_area_make_current(area);
        if (self.gl_vao != 0) gl.glDeleteVertexArrays(1, &self.gl_vao);
        if (self.gl_program != 0) gl.glDeleteProgram(self.gl_program);
        self.gl_vao = 0;
        self.gl_program = 0;
    }

    fn animationTick(_: *gtk.GtkWidget, _: *gtk.GdkFrameClock, user_data: gtk.gpointer) callconv(.c) gtk.gboolean {
        const self: *Application = @ptrCast(@alignCast(user_data));
        if (self.gl_area) |area| gtk.gtk_gl_area_queue_render(area);
        return gtk.G_SOURCE_CONTINUE;
    }

    fn pointerMotion(_: *gtk.GtkEventController, x: f64, y: f64, user_data: gtk.gpointer) callconv(.c) void {
        const self: *Application = @ptrCast(@alignCast(user_data));
        const area = self.gl_area orelse return;
        const width = gtk.gtk_widget_get_width(@ptrCast(area));
        const height = gtk.gtk_widget_get_height(@ptrCast(area));
        if (width <= 0 or height <= 0) return;

        self.pointer_x = @floatCast(x / @as(f64, @floatFromInt(width)));
        self.pointer_y = @floatCast(1.0 - y / @as(f64, @floatFromInt(height)));
        gtk.gtk_gl_area_queue_render(area);
    }
};

fn compileShader(shader_type: gl.GLenum, source: [*:0]const u8) ?gl.GLuint {
    const shader = gl.glCreateShader(shader_type);
    var sources = [_][*:0]const u8{source};
    gl.glShaderSource(shader, 1, &sources, null);
    gl.glCompileShader(shader);

    var compiled: gl.GLint = gl.FALSE;
    gl.glGetShaderiv(shader, gl.COMPILE_STATUS, &compiled);
    if (compiled == gl.FALSE) {
        printShaderLog(shader);
        gl.glDeleteShader(shader);
        return null;
    }
    return shader;
}

fn printShaderLog(shader: gl.GLuint) void {
    var length: gl.GLint = 0;
    gl.glGetShaderiv(shader, gl.INFO_LOG_LENGTH, &length);
    if (length <= 1) return;
    var buffer: [2048]u8 = undefined;
    var written: gl.GLsizei = 0;
    gl.glGetShaderInfoLog(shader, @min(length, buffer.len), &written, &buffer);
    std.debug.print("OpenGL shader error: {s}\n", .{buffer[0..@intCast(written)]});
}

fn printProgramLog(program: gl.GLuint) void {
    var length: gl.GLint = 0;
    gl.glGetProgramiv(program, gl.INFO_LOG_LENGTH, &length);
    if (length <= 1) return;
    var buffer: [2048]u8 = undefined;
    var written: gl.GLsizei = 0;
    gl.glGetProgramInfoLog(program, @min(length, buffer.len), &written, &buffer);
    std.debug.print("OpenGL program error: {s}\n", .{buffer[0..@intCast(written)]});
}

const vertex_source =
    \\#version 150
    \\out vec2 v_uv;
    \\void main() {
    \\    vec2 position;
    \\    if (gl_VertexID == 0) position = vec2(-1.0, -1.0);
    \\    else if (gl_VertexID == 1) position = vec2(3.0, -1.0);
    \\    else position = vec2(-1.0, 3.0);
    \\    v_uv = position * 0.5 + 0.5;
    \\    gl_Position = vec4(position, 0.0, 1.0);
    \\}
;

const fragment_source =
    \\#version 150
    \\in vec2 v_uv;
    \\out vec4 out_color;
    \\uniform float u_time;
    \\uniform vec2 u_resolution;
    \\uniform vec2 u_pointer;
    \\void main() {
    \\    vec2 pixel = v_uv * u_resolution;
    \\    vec2 uv = v_uv;
    \\    uv.x *= u_resolution.x / max(u_resolution.y, 1.0);
    \\    vec3 color = mix(vec3(0.025, 0.035, 0.07), vec3(0.04, 0.09, 0.13), v_uv.y);
    \\    float grid_x = 1.0 - smoothstep(0.0, 1.2, mod(pixel.x, 32.0));
    \\    float grid_y = 1.0 - smoothstep(0.0, 1.2, mod(pixel.y, 32.0));
    \\    color += vec3(0.04, 0.18, 0.19) * max(grid_x, grid_y) * 0.45;
    \\    float wave = sin(uv.x * 11.0 - u_time * 1.8) * 0.055;
    \\    float trace = exp(-95.0 * abs(v_uv.y - 0.52 - wave));
    \\    color += vec3(0.18, 0.95, 0.72) * trace;
    \\    vec2 pointer_delta = (v_uv - u_pointer) * vec2(u_resolution.x / max(u_resolution.y, 1.0), 1.0);
    \\    float glow = exp(-10.0 * length(pointer_delta));
    \\    color += vec3(0.25, 0.55, 1.0) * glow * (0.35 + 0.1 * sin(u_time * 3.0));
    \\    color *= 0.96 + 0.04 * sin(pixel.y * 3.14159);
    \\    out_color = vec4(color, 1.0);
    \\}
;

fn object(comptime T: type, builder: *gtk.GtkBuilder, id: [*:0]const u8) ?*T {
    const value = gtk.gtk_builder_get_object(builder, id) orelse return null;
    return @ptrCast(@alignCast(value));
}
