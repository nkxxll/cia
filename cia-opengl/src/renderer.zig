const std = @import("std");
const gl = @import("opengl.zig");
const treemap = @import("layout");

const vertex_shader_source: [*:0]const u8 =
    \\#version 150 core
    \\const vec2 positions[6] = vec2[6](
    \\    vec2(0.0, 0.0), vec2(1.0, 0.0), vec2(1.0, 1.0),
    \\    vec2(0.0, 0.0), vec2(1.0, 1.0), vec2(0.0, 1.0)
    \\);
    \\uniform vec4 rect;
    \\uniform vec2 viewport;
    \\void main() {
    \\    vec2 pixel = rect.xy + positions[gl_VertexID] * rect.zw;
    \\    vec2 ndc = vec2(pixel.x / viewport.x * 2.0 - 1.0,
    \\                    1.0 - pixel.y / viewport.y * 2.0);
    \\    gl_Position = vec4(ndc, 0.0, 1.0);
    \\}
;

const fragment_shader_source: [*:0]const u8 =
    \\#version 150 core
    \\uniform vec4 color;
    \\out vec4 out_color;
    \\void main() {
    \\    out_color = color;
    \\}
;

const colors = [_][3]f32{
    .{ 0.216, 0.494, 0.722 },
    .{ 0.302, 0.686, 0.290 },
    .{ 1.000, 0.498, 0.000 },
    .{ 0.596, 0.306, 0.639 },
    .{ 0.894, 0.102, 0.110 },
    .{ 0.651, 0.337, 0.157 },
    .{ 0.969, 0.506, 0.749 },
};

pub const Renderer = struct {
    program: gl.GLuint = 0,
    vao: gl.GLuint = 0,
    rect_location: gl.GLint = -1,
    viewport_location: gl.GLint = -1,
    color_location: gl.GLint = -1,

    pub fn init(self: *Renderer) !void {
        const vertex_shader = try compileShader(gl.VERTEX_SHADER, vertex_shader_source);
        defer gl.glDeleteShader(vertex_shader);
        const fragment_shader = try compileShader(gl.FRAGMENT_SHADER, fragment_shader_source);
        defer gl.glDeleteShader(fragment_shader);

        self.program = gl.glCreateProgram();
        errdefer {
            gl.glDeleteProgram(self.program);
            self.program = 0;
        }
        gl.glAttachShader(self.program, vertex_shader);
        gl.glAttachShader(self.program, fragment_shader);
        gl.glLinkProgram(self.program);

        var linked: gl.GLint = 0;
        gl.glGetProgramiv(self.program, gl.LINK_STATUS, &linked);
        if (linked == gl.FALSE) {
            printProgramLog(self.program);
            return error.ProgramLinkFailed;
        }

        self.rect_location = gl.glGetUniformLocation(self.program, "rect");
        self.viewport_location = gl.glGetUniformLocation(self.program, "viewport");
        self.color_location = gl.glGetUniformLocation(self.program, "color");
        gl.glGenVertexArrays(1, &self.vao);
    }

    pub fn deinit(self: *Renderer) void {
        if (self.vao != 0) gl.glDeleteVertexArrays(1, &self.vao);
        if (self.program != 0) gl.glDeleteProgram(self.program);
        self.* = .{};
    }

    pub fn begin(self: *const Renderer, width: f32, height: f32) void {
        gl.glClearColor(0.047, 0.063, 0.090, 1.0);
        gl.glClear(gl.COLOR_BUFFER_BIT);
        gl.glUseProgram(self.program);
        gl.glUniform2f(self.viewport_location, width, height);
        gl.glBindVertexArray(self.vao);
    }

    pub fn drawTreemap(self: *const Renderer, tiles: []const treemap.Tile, hovered: ?usize) void {
        for (tiles) |tile| {
            const visible = inset(tile.rect, 2.0);
            if (visible.width <= 0 or visible.height <= 0) continue;

            const base = colors[tile.entry_index % colors.len];
            if (hovered == tile.entry_index) {
                self.drawRect(visible, .{ 0.96, 0.98, 1.0, 1.0 });
                self.drawRect(inset(visible, 2.0), .{
                    @min(1.0, base[0] * 1.18),
                    @min(1.0, base[1] * 1.18),
                    @min(1.0, base[2] * 1.18),
                    1.0,
                });
            } else {
                self.drawRect(visible, .{ base[0], base[1], base[2], 1.0 });
            }
        }
    }

    pub fn drawSpinner(self: *const Renderer, width: f32, height: f32, monotonic_us: i64) void {
        const count: usize = 12;
        const angle_step: f32 = 2.0 * std.math.pi / 12.0;
        const phase: usize = @intCast(@mod(@divTrunc(monotonic_us, 80_000), count));
        const center_x = width * 0.5;
        const center_y = height * 0.5;

        for (0..count) |index| {
            const angle = @as(f32, @floatFromInt(index)) * angle_step;
            const age = (index + count - phase) % count;
            const brightness = 1.0 - @as(f32, @floatFromInt(age)) / @as(f32, count) * 0.75;
            self.drawRect(.{
                .x = center_x + @cos(angle) * 30.0 - 4.0,
                .y = center_y + @sin(angle) * 30.0 - 4.0,
                .width = 8.0,
                .height = 8.0,
            }, .{ 0.35 * brightness, 0.75 * brightness, brightness, 1.0 });
        }
    }

    fn drawRect(self: *const Renderer, rect: treemap.Rect, color: [4]f32) void {
        if (rect.width <= 0 or rect.height <= 0) return;
        gl.glUniform4f(
            self.rect_location,
            @floatCast(rect.x),
            @floatCast(rect.y),
            @floatCast(rect.width),
            @floatCast(rect.height),
        );
        gl.glUniform4f(self.color_location, color[0], color[1], color[2], color[3]);
        gl.glDrawArrays(gl.TRIANGLES, 0, 6);
    }
};

fn inset(rect: treemap.Rect, amount: f64) treemap.Rect {
    return .{
        .x = rect.x + amount,
        .y = rect.y + amount,
        .width = @max(0, rect.width - amount * 2),
        .height = @max(0, rect.height - amount * 2),
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
    std.log.err("OpenGL shader error: {s}", .{log[0..@intCast(length)]});
}

fn printProgramLog(program: gl.GLuint) void {
    var log: [1024]gl.GLchar = undefined;
    var length: gl.GLsizei = 0;
    gl.glGetProgramInfoLog(program, log.len, &length, &log);
    std.log.err("OpenGL program error: {s}", .{log[0..@intCast(length)]});
}
