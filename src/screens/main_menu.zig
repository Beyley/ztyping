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

pub fn initScreen(self: *Screen, allocator: std.mem.Allocator, gfx: Gfx) bool {
    _ = gfx;
    self.allocator = allocator;

    var data = allocator.create(MainMenuData) catch {
        std.debug.print("Failed to allocate MainMenuData!!???\n", .{});
        return false;
    };

    self.data = data;

    data.name = std.ArrayList(u8).init(allocator);

    return true;
}

pub fn deinitScreen(self: *Screen) void {
    var data = self.getData(MainMenuData);

    data.name.deinit();

    self.allocator.destroy(data);
}

pub fn char(self: *Screen, typed_char: []const u8) void {
    var data = self.getData(MainMenuData);

    data.name.appendSlice(typed_char) catch @panic("OOM");
}

pub fn keyDown(self: *Screen, key: c.SDL_Keysym) void {
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

pub fn renderScreen(self: *Screen, render_state: RenderState) void {
    var data = self.getData(MainMenuData);

    render_state.fontstash.renderer.begin() catch {
        @panic("Cant begin font renderer");
    };
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
        data.name.append(0) catch {
            @panic("OOM");
        };
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

    render_state.fontstash.renderer.end() catch {
        @panic("Cant end font renderer");
    };

    render_state.fontstash.renderer.draw(render_state.render_pass_encoder) catch {
        @panic("Cant draw....");
    };
}
