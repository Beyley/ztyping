const std = @import("std");
const zaudio = @import("zaudio");

const c = @import("main.zig").c;

pub const ScreenError = zaudio.Error || std.mem.Allocator.Error || std.fs.File.OpenError || std.fs.Dir.OpenError || Gfx.Error || std.time.Timer.Error;

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
render: *const fn (*Self, RenderState) ScreenError!void,
char: ?*const fn (*Self, []const u8) ScreenError!void = null,
key_down: ?*const fn (*Self, c.SDL_Keysym) ScreenError!void = null,
init: *const fn (*Self, std.mem.Allocator, Gfx) ScreenError!void,
deinit: *const fn (*Self) void,
data: *anyopaque,
allocator: std.mem.Allocator,

pub fn getData(self: *Self, comptime T: type) *T {
    return @ptrCast(*T, @alignCast(@alignOf(T), self.data));
}
