const std = @import("std");

const Gfx = @import("gfx.zig");

const Self = @This();

pub const MainMenu = @import("screens/main_menu.zig");

render: *const fn (*Self, Gfx, Gfx.RenderPassEncoder, Gfx.Texture) void,
init: *const fn (*Self, std.mem.Allocator, Gfx) bool,
deinit: *const fn (*Self) void,
data: *anyopaque,
allocator: std.mem.Allocator,

pub fn getData(self: *Self, comptime T: type) *T {
    return @ptrCast(*T, @alignCast(@alignOf(T), self.data));
}
