const std = @import("std");
const gtk = @import("gtk.zig");
const gl = @import("opengl.zig");
const LinesModel = @import("lines_model.zig").LinesModel;
const Renderer = @import("renderer.zig").Renderer;
const scanner = @import("scanner.zig");
const treemap = @import("treemap.zig");

const window_xml = @embedFile("ui/window.ui");

const ScanJob = struct {
    const State = enum { idle, loading, ready, failed };

    mutex: std.Io.Mutex = .init,
    state: State = .idle,
    result: ?LinesModel = null,
    failure: ?anyerror = null,
};

pub const Application = struct {
    pub const Screen = enum {
        home,
        lines,
    };

    allocator: std.mem.Allocator,
    io: std.Io,
    window: ?*gtk.GtkWindow = null,
    screen_stack: ?*gtk.GtkStack = null,
    lines_gl_area: ?*gtk.GtkGLArea = null,
    lines_status_label: ?*gtk.GtkLabel = null,
    rescan_button: ?*gtk.GtkButton = null,
    initial_screen: Screen = .home,

    scan_job: ScanJob = .{},
    scan_thread: ?std.Thread = null,
    poll_source: gtk.guint = 0,
    spinner_tick: gtk.guint = 0,
    scanning: bool = false,
    cancel_scan: std.atomic.Value(bool) = .init(false),

    lines_model: ?LinesModel = null,
    tiles: []treemap.Tile = &.{},
    layout_width: c_int = 0,
    layout_height: c_int = 0,
    hovered_entry: ?usize = null,
    tooltip_buffer: [1024]u8 = undefined,

    renderer: Renderer = .{},
    renderer_ready: bool = false,
    renderer_failed: bool = false,

    pub fn run(self: *Application) void {
        const app = gtk.gtk_application_new(
            "io.github.nkxxll.cia",
            gtk.G_APPLICATION_DEFAULT_FLAGS,
        ) orelse return;
        defer gtk.g_object_unref(app);

        connect(app, "activate", activate, self);
        _ = gtk.g_application_run(@ptrCast(app), 0, null);
        self.deinit();
    }

    fn deinit(self: *Application) void {
        if (self.poll_source != 0) {
            _ = gtk.g_source_remove(self.poll_source);
            self.poll_source = 0;
        }
        self.cancel_scan.store(true, .release);
        self.joinWorker();

        self.scan_job.mutex.lockUncancelable(self.io);
        const pending_result = self.scan_job.result;
        self.scan_job.result = null;
        self.scan_job.mutex.unlock(self.io);
        if (pending_result) |result_value| {
            var result = result_value;
            result.deinit();
        }

        self.clearTiles();
        if (self.lines_model) |model_value| {
            var model = model_value;
            model.deinit();
            self.lines_model = null;
        }
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
        self.screen_stack = object(gtk.GtkStack, builder, "screen_stack") orelse return;
        self.lines_gl_area = object(gtk.GtkGLArea, builder, "lines_gl_area") orelse return;
        self.lines_status_label = object(gtk.GtkLabel, builder, "lines_status_label") orelse return;
        self.rescan_button = object(gtk.GtkButton, builder, "rescan_button") orelse return;
        const show_lines_button = object(gtk.GtkButton, builder, "show_lines_button") orelse return;
        const show_home_button = object(gtk.GtkButton, builder, "show_home_button") orelse return;

        gtk.gtk_window_set_application(self.window.?, app);
        gtk.gtk_stack_set_visible_child_name(self.screen_stack.?, switch (self.initial_screen) {
            .home => "home",
            .lines => "lines",
        });
        gtk.gtk_gl_area_set_required_version(self.lines_gl_area.?, 3, 2);
        gtk.gtk_gl_area_set_allowed_apis(self.lines_gl_area.?, gtk.GDK_GL_API_GL);

        connect(show_lines_button, "clicked", showLines, self);
        connect(show_home_button, "clicked", showHome, self);
        connect(self.rescan_button.?, "clicked", rescan, self);
        connect(self.lines_gl_area.?, "render", render, self);
        connect(self.lines_gl_area.?, "resize", resize, self);
        connect(self.lines_gl_area.?, "unrealize", unrealize, self);
        connect(self.window.?, "destroy", windowDestroyed, self);

        const motion = gtk.gtk_event_controller_motion_new();
        connect(motion, "motion", mouseMotion, self);
        connect(motion, "leave", mouseLeave, self);
        gtk.gtk_widget_add_controller(@ptrCast(self.lines_gl_area.?), motion);

        gtk.gtk_window_present(self.window.?);
        self.startScan();
    }

    fn startScan(self: *Application) void {
        if (self.scan_thread != null) return;
        self.cancel_scan.store(false, .release);

        self.scan_job.mutex.lockUncancelable(self.io);
        self.scan_job.state = .loading;
        self.scan_job.failure = null;
        self.scan_job.mutex.unlock(self.io);

        self.scanning = true;
        self.setStatus("Scanning Zig files...");
        if (self.rescan_button) |button| gtk.gtk_widget_set_sensitive(@ptrCast(button), 0);
        self.clearHover();
        self.startSpinner();

        self.scan_thread = std.Thread.spawn(.{}, scanWorker, .{self}) catch |err| {
            self.scanning = false;
            self.stopSpinner();
            self.scan_job.mutex.lockUncancelable(self.io);
            self.scan_job.state = .idle;
            self.scan_job.mutex.unlock(self.io);
            if (self.rescan_button) |button| gtk.gtk_widget_set_sensitive(@ptrCast(button), 1);
            self.setStatusFmt("Could not start scan: {s}", .{@errorName(err)});
            return;
        };
        self.poll_source = gtk.g_timeout_add(75, pollScan, self);
        self.queueRender();
    }

    fn scanWorker(self: *Application) void {
        const result = scanCurrentDirectory(self) catch |err| {
            self.scan_job.mutex.lockUncancelable(self.io);
            self.scan_job.failure = err;
            self.scan_job.state = .failed;
            self.scan_job.mutex.unlock(self.io);
            return;
        };

        self.scan_job.mutex.lockUncancelable(self.io);
        self.scan_job.result = result;
        self.scan_job.state = .ready;
        self.scan_job.mutex.unlock(self.io);
    }

    fn scanCurrentDirectory(self: *Application) !LinesModel {
        const root = try std.Io.Dir.cwd().openDir(self.io, ".", .{
            .iterate = true,
            .follow_symlinks = false,
        });
        defer root.close(self.io);
        return scanner.scanCancelable(self.allocator, self.io, root, &self.cancel_scan);
    }

    fn pollScan(user_data: gtk.gpointer) callconv(.c) gtk.gboolean {
        const self: *Application = @ptrCast(@alignCast(user_data));

        self.scan_job.mutex.lockUncancelable(self.io);
        const state = self.scan_job.state;
        if (state == .loading) {
            self.scan_job.mutex.unlock(self.io);
            return gtk.G_SOURCE_CONTINUE;
        }
        const result = self.scan_job.result;
        const failure = self.scan_job.failure;
        self.scan_job.result = null;
        self.scan_job.failure = null;
        self.scan_job.state = .idle;
        self.scan_job.mutex.unlock(self.io);

        self.poll_source = 0;
        self.joinWorker();
        self.scanning = false;
        self.stopSpinner();
        if (self.rescan_button) |button| gtk.gtk_widget_set_sensitive(@ptrCast(button), 1);

        if (state == .ready) {
            self.installModel(result.?);
        } else {
            self.setStatusFmt("Scan failed: {s}", .{@errorName(failure.?)});
            self.queueRender();
        }
        return gtk.G_SOURCE_REMOVE;
    }

    fn installModel(self: *Application, new_model: LinesModel) void {
        self.clearHover();
        self.clearTiles();
        if (self.lines_model) |model_value| {
            var model = model_value;
            model.deinit();
        }
        self.lines_model = new_model;
        self.layout_width = 0;
        self.layout_height = 0;

        if (new_model.warning_count == 0) {
            self.setStatusFmt("{d} Zig files, {d} lines", .{ new_model.files.items.len, new_model.total_lines });
        } else {
            self.setStatusFmt("{d} Zig files, {d} lines ({d} skipped)", .{
                new_model.files.items.len,
                new_model.total_lines,
                new_model.warning_count,
            });
        }
        self.queueRender();
    }

    fn rebuildLayout(self: *Application, width: c_int, height: c_int) !void {
        if (self.layout_width == width and self.layout_height == height) return;
        const model = self.lines_model orelse return;
        const weights = try self.allocator.alloc(usize, model.files.items.len);
        defer self.allocator.free(weights);
        for (model.files.items, weights) |file, *weight| weight.* = @max(file.lines, 1);
        const new_tiles = try treemap.layout(self.allocator, weights, .{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(width),
            .height = @floatFromInt(height),
        });
        self.clearTiles();
        self.tiles = new_tiles;
        self.layout_width = width;
        self.layout_height = height;
    }

    fn clearTiles(self: *Application) void {
        if (self.tiles.len != 0) self.allocator.free(self.tiles);
        self.tiles = &.{};
    }

    fn joinWorker(self: *Application) void {
        if (self.scan_thread) |thread| {
            thread.join();
            self.scan_thread = null;
        }
    }

    fn startSpinner(self: *Application) void {
        if (self.spinner_tick != 0) return;
        if (self.lines_gl_area) |area| {
            self.spinner_tick = gtk.gtk_widget_add_tick_callback(@ptrCast(area), spinnerTick, self, null);
        }
    }

    fn stopSpinner(self: *Application) void {
        if (self.spinner_tick == 0) return;
        if (self.lines_gl_area) |area| gtk.gtk_widget_remove_tick_callback(@ptrCast(area), self.spinner_tick);
        self.spinner_tick = 0;
    }

    fn spinnerTick(_: *gtk.GtkWidget, _: *gtk.GdkFrameClock, user_data: gtk.gpointer) callconv(.c) gtk.gboolean {
        const self: *Application = @ptrCast(@alignCast(user_data));
        if (!self.scanning) {
            self.spinner_tick = 0;
            return gtk.G_SOURCE_REMOVE;
        }
        self.queueRender();
        return gtk.G_SOURCE_CONTINUE;
    }

    fn render(area: *gtk.GtkGLArea, _: *gtk.GdkGLContext, user_data: gtk.gpointer) callconv(.c) gtk.gboolean {
        const self: *Application = @ptrCast(@alignCast(user_data));
        if (self.renderer_failed) return 0;
        if (!self.renderer_ready) {
            self.renderer.init() catch |err| {
                self.renderer_failed = true;
                self.setStatusFmt("OpenGL setup failed: {s}", .{@errorName(err)});
                return 0;
            };
            self.renderer_ready = true;
        }

        const width = @max(gtk.gtk_widget_get_width(@ptrCast(area)), 1);
        const height = @max(gtk.gtk_widget_get_height(@ptrCast(area)), 1);
        const scale = gtk.gtk_widget_get_scale_factor(@ptrCast(area));
        gl.glViewport(0, 0, width * scale, height * scale);
        self.renderer.begin(@floatFromInt(width), @floatFromInt(height));

        if (self.scanning) {
            self.renderer.drawSpinner(@floatFromInt(width), @floatFromInt(height), gtk.g_get_monotonic_time());
        } else {
            self.rebuildLayout(width, height) catch |err| {
                self.setStatusFmt("Could not build treemap: {s}", .{@errorName(err)});
                return 1;
            };
            self.renderer.drawTreemap(self.tiles, self.hovered_entry);
        }
        return 1;
    }

    fn resize(_: *gtk.GtkGLArea, _: c_int, _: c_int, user_data: gtk.gpointer) callconv(.c) void {
        const self: *Application = @ptrCast(@alignCast(user_data));
        self.layout_width = 0;
        self.layout_height = 0;
        self.queueRender();
    }

    fn unrealize(area: *gtk.GtkGLArea, user_data: gtk.gpointer) callconv(.c) void {
        const self: *Application = @ptrCast(@alignCast(user_data));
        if (!self.renderer_ready) return;
        gtk.gtk_gl_area_make_current(area);
        self.renderer.deinit();
        self.renderer_ready = false;
    }

    fn mouseMotion(_: *gtk.GtkEventController, x: f64, y: f64, user_data: gtk.gpointer) callconv(.c) void {
        const self: *Application = @ptrCast(@alignCast(user_data));
        if (self.scanning) {
            self.clearHover();
            return;
        }
        var hovered: ?usize = null;
        for (self.tiles) |tile| {
            const rect = tile.rect;
            if (x >= rect.x + 2 and x <= rect.x + rect.width - 2 and
                y >= rect.y + 2 and y <= rect.y + rect.height - 2)
            {
                hovered = tile.entry_index;
                break;
            }
        }
        if (hovered == self.hovered_entry) return;

        self.hovered_entry = hovered;
        if (self.lines_gl_area) |area| {
            if (hovered) |entry_index| {
                const file = self.lines_model.?.files.items[entry_index];
                const text = std.fmt.bufPrintZ(&self.tooltip_buffer, "{s}\n{d} LOC", .{ std.fs.path.basename(file.path), file.lines }) catch {
                    gtk.gtk_widget_set_tooltip_text(@ptrCast(area), "Path is too long to display");
                    self.queueRender();
                    return;
                };
                gtk.gtk_widget_set_tooltip_text(@ptrCast(area), text.ptr);
            } else {
                gtk.gtk_widget_set_tooltip_text(@ptrCast(area), null);
            }
        }
        self.queueRender();
    }

    fn mouseLeave(_: *gtk.GtkEventController, user_data: gtk.gpointer) callconv(.c) void {
        const self: *Application = @ptrCast(@alignCast(user_data));
        self.clearHover();
    }

    fn clearHover(self: *Application) void {
        if (self.hovered_entry == null) return;
        self.hovered_entry = null;
        if (self.lines_gl_area) |area| gtk.gtk_widget_set_tooltip_text(@ptrCast(area), null);
        self.queueRender();
    }

    fn queueRender(self: *Application) void {
        if (self.lines_gl_area) |area| gtk.gtk_gl_area_queue_render(area);
    }

    fn setStatus(self: *Application, text: [*:0]const u8) void {
        if (self.lines_status_label) |label| gtk.gtk_label_set_text(label, text);
    }

    fn setStatusFmt(self: *Application, comptime format: []const u8, args: anytype) void {
        var buffer: [256]u8 = undefined;
        const text = std.fmt.bufPrintZ(&buffer, format, args) catch return self.setStatus("Status message is too long");
        self.setStatus(text.ptr);
    }

    fn showLines(_: *gtk.GtkButton, user_data: gtk.gpointer) callconv(.c) void {
        const self: *Application = @ptrCast(@alignCast(user_data));
        const stack = self.screen_stack orelse return;
        gtk.gtk_stack_set_visible_child_name(stack, "lines");
    }

    fn showHome(_: *gtk.GtkButton, user_data: gtk.gpointer) callconv(.c) void {
        const self: *Application = @ptrCast(@alignCast(user_data));
        const stack = self.screen_stack orelse return;
        gtk.gtk_stack_set_visible_child_name(stack, "home");
    }

    fn rescan(_: *gtk.GtkButton, user_data: gtk.gpointer) callconv(.c) void {
        const self: *Application = @ptrCast(@alignCast(user_data));
        self.startScan();
    }

    fn windowDestroyed(_: *gtk.GtkWindow, user_data: gtk.gpointer) callconv(.c) void {
        const self: *Application = @ptrCast(@alignCast(user_data));
        self.window = null;
        self.screen_stack = null;
        self.lines_gl_area = null;
        self.lines_status_label = null;
        self.rescan_button = null;
        self.spinner_tick = 0;
    }
};

fn object(comptime T: type, builder: *gtk.GtkBuilder, id: [*:0]const u8) ?*T {
    const value = gtk.gtk_builder_get_object(builder, id) orelse return null;
    return @ptrCast(@alignCast(value));
}

fn connect(instance: *anyopaque, signal: [*:0]const u8, callback: anytype, data: gtk.gpointer) void {
    _ = gtk.g_signal_connect_data(instance, signal, @ptrCast(&callback), data, null, gtk.G_CONNECT_DEFAULT);
}
