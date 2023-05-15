const std = @import("std");

const GameState = @import("game_state.zig");
const Gfx = @import("gfx.zig");
const Screen = @import("screen.zig");

const ScreenStack = @This();

internal: std.ArrayList(*Screen),

pub fn init(allocator: std.mem.Allocator) ScreenStack {
    return .{ .internal = std.ArrayList(*Screen).init(allocator) };
}

pub fn deinit(self: ScreenStack) void {
    self.internal.deinit();
}

pub fn load(self: *ScreenStack, screen: *Screen, gfx: Gfx, state: *GameState) !void {
    screen.state = state;
    if (!screen.init(screen, self.internal.allocator, gfx)) {
        return error.FailedToInitScreen;
    }

    try self.internal.append(screen);
}

pub fn pop(self: *ScreenStack) *Screen {
    var screen = self.internal.pop();
    screen.deinit(screen);

    return screen;
}

pub fn top(self: *const ScreenStack) *Screen {
    return self.internal.getLast();
}

pub fn count(self: *const ScreenStack) usize {
    return self.internal.items.len;
}
