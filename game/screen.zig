const std = @import("std");
const bass = @import("bass");
const core = @import("mach-core");

const App = @import("app.zig");
const Renderer = @import("renderer.zig");
const Gfx = @import("gfx.zig");
const Fontstash = @import("fontstash.zig");

const Self = @This();

pub const MainMenu = @import("screens/main_menu.zig");

pub const display_width = 640;
pub const display_height = 480;

pub const RenderState = struct {
    gfx: *Gfx,
    renderer: *Renderer,
    fontstash: *Fontstash,
    render_pass_encoder: *Gfx.RenderPassEncoder,
    app: *App,
};

close_screen: bool = false,
screen_push: ?*Self = null,
app: *App,
render: *const fn (*Self, RenderState) anyerror!void,
char: ?*const fn (*Self, u21) anyerror!void = null,
key_down: ?*const fn (*Self, core.Key) anyerror!void = null,
init: *const fn (*Self, std.mem.Allocator, Gfx) anyerror!void,
///Called when the screen is re-entered (eg. the screen higher on the stack closes)
reenter: ?*const fn (*Self) anyerror!void = null,
deinit: *const fn (*Self) void,
data: *anyopaque,
allocator: std.mem.Allocator,

pub fn getData(self: *Self, comptime T: type) *T {
    return @ptrCast(@alignCast(self.data));
}
