const std = @import("std");

const c = @import("../main.zig").c;

const SongSelect = @import("song_select.zig");

const Screen = @import("../screen.zig");
const Gfx = @import("../gfx.zig");

const RenderState = Screen.RenderState;

const MainMenuData = struct {
    name: std.ArrayList(u8),
};

pub var MainMenu = Screen{
    .render = renderScreen,
    .init = initScreen,
    .deinit = deinitScreen,
    .allocator = undefined,
    .char = char,
    .key_down = keyDown,
    .data = undefined,
    .state = undefined,
};

pub fn initScreen(self: *Screen, allocator: std.mem.Allocator, gfx: Gfx) Screen.ScreenError!void {
    _ = gfx;
    self.allocator = allocator;

    var data = try allocator.create(MainMenuData);

    self.data = data;

    data.name = std.ArrayList(u8).init(allocator);
}

pub fn deinitScreen(self: *Screen) void {
    var data = self.getData(MainMenuData);

    data.name.deinit();

    self.allocator.destroy(data);
}

pub fn char(self: *Screen, typed_char: []const u8) Screen.ScreenError!void {
    var data = self.getData(MainMenuData);

    try data.name.appendSlice(typed_char);
}

pub fn keyDown(self: *Screen, key: c.SDL_Keysym) Screen.ScreenError!void {
    var data = self.getData(MainMenuData);

    switch (key.sym) {
        c.SDLK_ESCAPE => {
            if (data.name.items.len == 0) {
                self.state.is_running = false;
            } else {
                data.name.clearRetainingCapacity();
            }
        },
        c.SDLK_BACKSPACE => {
            if (data.name.items.len != 0) {
                //TODO: handle unicode stuff here
                _ = data.name.pop();
            }
        },
        c.SDLK_RETURN => {
            self.screen_push = &SongSelect.SongSelect;
        },
        else => {},
    }
}

pub fn renderScreen(self: *Screen, render_state: RenderState) Screen.ScreenError!void {
    var data = self.getData(MainMenuData);

    try render_state.fontstash.renderer.begin();
    render_state.fontstash.reset();

    render_state.fontstash.setMincho();
    render_state.fontstash.setSizePt(48);
    render_state.fontstash.setColor(.{ 255, 255, 255, 255 });
    render_state.fontstash.setAlign(.center);

    render_state.fontstash.drawText(.{ Screen.display_width / 2, Screen.display_height / 3 }, "ztyping");

    render_state.fontstash.setGothic();
    render_state.fontstash.setSizePt(16);
    render_state.fontstash.setColor(.{ 255, 255, 255, 255 });
    render_state.fontstash.setAlign(.right);

    render_state.fontstash.drawText(.{ Screen.display_width - 10, Screen.display_height - 10 }, "(c)2023 Beyley");

    render_state.fontstash.setMincho();
    render_state.fontstash.setSizePt(24);
    render_state.fontstash.setColor(.{ 255, 255, 255, 255 });
    render_state.fontstash.setAlign(.center);

    render_state.fontstash.drawText(.{ Screen.display_width / 2, Screen.display_height * 2 / 3 }, "Press Enter key.");

    render_state.fontstash.setGothic();
    render_state.fontstash.setSizePt(16);
    render_state.fontstash.setColor(.{ 255, 255, 255, 255 });
    render_state.fontstash.setAlign(.baseline);

    var metrics = render_state.fontstash.verticalMetrics();
    render_state.fontstash.drawText(.{ 30, 375 + metrics.line_height }, "名前を入力してください :");

    if (data.name.items.len > 0) {
        render_state.fontstash.setMincho();
        render_state.fontstash.setSizePt(36);
        render_state.fontstash.setColor(.{ 255, 255, 255, 255 });
        render_state.fontstash.setAlign(.baseline);

        metrics = render_state.fontstash.verticalMetrics();
        try data.name.append(0);
        render_state.fontstash.drawText(.{ 60, 400 + metrics.line_height * 2 }, data.name.items[0..(data.name.items.len - 1) :0]);
        _ = data.name.pop();
    } else {
        render_state.fontstash.setMincho();
        render_state.fontstash.setSizePt(36);
        render_state.fontstash.setColor(.{ 128, 128, 128, 255 });
        render_state.fontstash.setAlign(.baseline);

        metrics = render_state.fontstash.verticalMetrics();
        render_state.fontstash.drawText(.{ 60, 400 + metrics.line_height * 2 }, "（未設定）");
    }

    try render_state.fontstash.renderer.end();

    try render_state.fontstash.renderer.draw(render_state.render_pass_encoder);
}
