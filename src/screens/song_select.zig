const std = @import("std");

const c = @import("../main.zig").c;

const Screen = @import("../screen.zig");
const Gfx = @import("../gfx.zig");
const Gameplay = @import("gameplay.zig");

const RenderState = Screen.RenderState;

const SongSelectData = struct {
    // name: std.ArrayList(u8),
    a: u8,
};

pub var SongSelect = Screen{
    .render = renderScreen,
    .init = initScreen,
    .deinit = deinitScreen,
    .allocator = undefined,
    // .char = char,
    .key_down = keyDown,
    .data = undefined,
    .state = undefined,
};

pub fn initScreen(self: *Screen, allocator: std.mem.Allocator, gfx: Gfx) bool {
    _ = gfx;
    self.allocator = allocator;

    var data = allocator.create(SongSelectData) catch {
        std.debug.print("Failed to allocate SongSelectData!!???\n", .{});
        return false;
    };

    self.data = data;

    return true;
}

pub fn deinitScreen(self: *Screen) void {
    var data = self.getData(SongSelectData);

    self.allocator.destroy(data);
}

// pub fn char(self: *Screen, typed_char: []const u8) void {
//     _ = typed_char;
//     var data = self.getData(SongSelectData);
//     _ = data;
// }

pub fn keyDown(self: *Screen, key: c.SDL_Keysym) void {
    var data = self.getData(SongSelectData);
    _ = data;

    switch (key.sym) {
        c.SDLK_ESCAPE => {
            self.close_screen = true;
        },
        else => {},
    }
}

pub fn renderScreen(self: *Screen, render_state: RenderState) Screen.ScreenError!void {
    var data = self.getData(SongSelectData);
    _ = data;

    var open = true;
    _ = c.igBegin("Maps", &open, c.ImGuiWindowFlags_AlwaysVerticalScrollbar);

    for (self.state.map_list) |map| {
        var titleZ = self.allocator.dupeZ(u8, map.title) catch @panic("OOM");
        defer self.allocator.free(titleZ);
        if (c.igButton(titleZ, .{ .x = 0, .y = 0 })) {
            self.state.current_map = map;
            self.screen_push = &Gameplay.Gameplay;
        }
    }

    c.igEnd();

    render_state.fontstash.renderer.begin() catch @panic("Cant begin font renderer");
    render_state.fontstash.reset();

    render_state.fontstash.renderer.end() catch @panic("Cant end font renderer");

    render_state.fontstash.renderer.draw(render_state.render_pass_encoder) catch @panic("Cant draw....");
}
