const gtk = @import("gtk.zig");

const window_xml = @embedFile("ui/window.ui");

pub const Application = struct {
    pub const Screen = enum {
        home,
        lines,
    };

    window: ?*gtk.GtkWindow = null,
    screen_stack: ?*gtk.GtkStack = null,
    initial_screen: Screen = .home,

    pub fn run(self: *Application) void {
        const app = gtk.gtk_application_new(
            "io.github.nkxxll.cia",
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
        self.screen_stack = object(gtk.GtkStack, builder, "screen_stack") orelse return;
        const show_lines_button = object(gtk.GtkButton, builder, "show_lines_button") orelse return;
        const show_home_button = object(gtk.GtkButton, builder, "show_home_button") orelse return;

        gtk.gtk_window_set_application(self.window.?, app);
        gtk.gtk_stack_set_visible_child_name(self.screen_stack.?, switch (self.initial_screen) {
            .home => "home",
            .lines => "lines",
        });

        _ = gtk.g_signal_connect_data(
            show_lines_button,
            "clicked",
            @ptrCast(&showLines),
            self,
            null,
            gtk.G_CONNECT_DEFAULT,
        );
        _ = gtk.g_signal_connect_data(
            show_home_button,
            "clicked",
            @ptrCast(&showHome),
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

        gtk.gtk_window_present(self.window.?);
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

    fn windowDestroyed(_: *gtk.GtkWindow, user_data: gtk.gpointer) callconv(.c) void {
        const self: *Application = @ptrCast(@alignCast(user_data));
        self.window = null;
        self.screen_stack = null;
    }
};

fn object(comptime T: type, builder: *gtk.GtkBuilder, id: [*:0]const u8) ?*T {
    const value = gtk.gtk_builder_get_object(builder, id) orelse return null;
    return @ptrCast(@alignCast(value));
}
