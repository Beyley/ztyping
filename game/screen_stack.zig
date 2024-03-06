const std = @import("std");

const App = @import("app.zig");
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

pub fn load(self: *ScreenStack, screen: *Screen, gfx: Gfx, app: *App) !void {
    screen.app = app;
    try screen.init(screen, self.internal.allocator, gfx);

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
