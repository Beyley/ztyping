const std = @import("std");

const c = @import("../main.zig").c;

const Screen = @import("../screen.zig");
const Gfx = @import("../gfx.zig");

const MainMenuData = struct {
    open: bool = true,
};

pub var MainMenu = Screen{
    .render = renderScreen,
    .init = initScreen,
    .deinit = deinitScreen,
    .allocator = undefined,
    .data = undefined,
};

pub fn initScreen(self: *Screen, allocator: std.mem.Allocator, gfx: Gfx) bool {
    self.allocator = allocator;

    var data = allocator.create(MainMenuData) catch {
        std.debug.print("Failed to allocate MainMenuData!!???\n", .{});
        return false;
    };

    self.data = data;
    _ = gfx;

    return true;
}

pub fn deinitScreen(self: *Screen) void {
    self.allocator.destroy(self.getData(MainMenuData));
}

pub fn renderScreen(self: *Screen, gfx: Gfx, render_pass_encoder: Gfx.RenderPassEncoder, texture: Gfx.Texture) void {
    _ = render_pass_encoder;
    _ = gfx;
    _ = texture;

    var data = self.getData(MainMenuData);
    _ = data;
}
