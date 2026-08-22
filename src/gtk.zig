pub const GtkApplication = opaque {};
pub const GtkBuilder = opaque {};
pub const GtkEditable = opaque {};
pub const GtkEventController = opaque {};
pub const GtkGLArea = opaque {};
pub const GtkLabel = opaque {};
pub const GtkWidget = opaque {};
pub const GtkWindow = opaque {};
pub const GdkFrameClock = opaque {};
pub const GdkGLContext = opaque {};
pub const GObject = opaque {};

pub const gboolean = c_int;
pub const guint = c_uint;
pub const gpointer = ?*anyopaque;
pub const GCallback = *const fn () callconv(.c) void;
pub const GSourceFunc = *const fn (gpointer) callconv(.c) gboolean;
pub const GtkTickCallback = *const fn (*GtkWidget, *GdkFrameClock, gpointer) callconv(.c) gboolean;

pub const G_APPLICATION_DEFAULT_FLAGS: c_uint = 0;
pub const G_CONNECT_DEFAULT: c_uint = 0;
pub const G_SOURCE_REMOVE: gboolean = 0;
pub const G_SOURCE_CONTINUE: gboolean = 1;

pub extern fn gtk_application_new(application_id: [*:0]const u8, flags: c_uint) ?*GtkApplication;
pub extern fn gtk_builder_new_from_string(string: [*]const u8, length: isize) *GtkBuilder;
pub extern fn gtk_builder_get_object(builder: *GtkBuilder, name: [*:0]const u8) ?*GObject;
pub extern fn gtk_editable_get_text(editable: *GtkEditable) [*:0]const u8;
pub extern fn gtk_editable_set_text(editable: *GtkEditable, text: [*:0]const u8) void;
pub extern fn gtk_event_controller_motion_new() *GtkEventController;
pub extern fn gtk_gl_area_make_current(area: *GtkGLArea) void;
pub extern fn gtk_gl_area_queue_render(area: *GtkGLArea) void;
pub extern fn gtk_gl_area_set_required_version(area: *GtkGLArea, major: c_int, minor: c_int) void;
pub extern fn gtk_label_set_text(label: *GtkLabel, text: [*:0]const u8) void;
pub extern fn gtk_widget_add_controller(widget: *GtkWidget, controller: *GtkEventController) void;
pub extern fn gtk_widget_add_tick_callback(widget: *GtkWidget, callback: GtkTickCallback, user_data: gpointer, notify: ?*const fn (gpointer) callconv(.c) void) guint;
pub extern fn gtk_widget_get_height(widget: *GtkWidget) c_int;
pub extern fn gtk_widget_get_width(widget: *GtkWidget) c_int;
pub extern fn gtk_widget_set_visible(widget: *GtkWidget, visible: gboolean) void;
pub extern fn gtk_window_present(window: *GtkWindow) void;
pub extern fn gtk_window_set_application(window: *GtkWindow, application: *GtkApplication) void;

pub extern fn g_application_run(application: *anyopaque, argc: c_int, argv: ?[*][*:0]u8) c_int;
pub extern fn g_object_unref(object: *anyopaque) void;
pub extern fn g_signal_connect_data(
    instance: *anyopaque,
    detailed_signal: [*:0]const u8,
    callback: GCallback,
    data: gpointer,
    destroy_data: ?*const fn (gpointer, *anyopaque) callconv(.c) void,
    connect_flags: c_uint,
) c_ulong;
pub extern fn g_source_remove(tag: guint) gboolean;
pub extern fn g_timeout_add(interval: guint, function: GSourceFunc, data: gpointer) guint;
pub extern fn g_get_monotonic_time() i64;
