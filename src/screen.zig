const std = @import("std");
const bass = @import("bass");

const c = @import("main.zig").c;

const Renderer = @import("renderer.zig");
const Gfx = @import("gfx.zig");
const Fontstash = @import("fontstash.zig");
const GameState = @import("game_state.zig");

const Self = @This();

pub const MainMenu = @import("screens/main_menu.zig");

pub const display_width = 640;
pub const display_height = 480;

pub const RenderState = struct {
    gfx: *Gfx,
    renderer: *Renderer,
    fontstash: *Fontstash,
    render_pass_encoder: *Gfx.RenderPassEncoder,
};

close_screen: bool = false,
screen_push: ?*Self = null,
state: *GameState,
render: *const fn (*Self, RenderState) anyerror!void,
char: ?*const fn (*Self, []const u8) anyerror!void = null,
key_down: ?*const fn (*Self, c.SDL_Keysym) anyerror!void = null,
init: *const fn (*Self, std.mem.Allocator, Gfx) anyerror!void,
deinit: *const fn (*Self) void,
data: *anyopaque,
allocator: std.mem.Allocator,

pub fn getData(self: *Self, comptime T: type) *T {
    return @ptrCast(*T, @alignCast(@alignOf(T), self.data));
}
