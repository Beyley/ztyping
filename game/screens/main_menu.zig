const std = @import("std");

const core = @import("mach-core");

const SongSelect = @import("song_select.zig");

const Screen = @import("../screen.zig");
const Gfx = @import("../gfx.zig");
const Fontstash = @import("../fontstash.zig");

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
    .app = undefined,
};

pub fn initScreen(self: *Screen, allocator: std.mem.Allocator, gfx: Gfx) anyerror!void {
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

pub fn char(self: *Screen, typed_char: u21) anyerror!void {
    var data = self.getData(MainMenuData);

    //Count the amount of needed bytes for this codepoint
    const needed = try std.unicode.utf8CodepointSequenceLength(typed_char);
    //Ensure we have the amount of data needed
    try data.name.ensureUnusedCapacity(needed);
    //Increase the length of the items slice by the amount needed
    data.name.items.len += needed;
    //Encode the codepoint into the items array at the end
    std.debug.assert(try std.unicode.utf8Encode(typed_char, data.name.items[data.name.items.len - needed .. data.name.items.len]) == needed);

    //Set the name slice
    self.app.name = data.name.items;
}

pub fn keyDown(self: *Screen, key: core.Key) anyerror!void {
    var data = self.getData(MainMenuData);

    switch (key) {
        .escape => {
            if (data.name.items.len == 0) {
                self.app.is_running = false;
            } else {
                data.name.clearRetainingCapacity();
            }
        },
        .backspace => {
            if (data.name.items.len != 0) {
                //TODO: handle unicode stuff here
                _ = data.name.pop();
            }
        },
        .enter => {
            //If they did not enter a name, mark them as a guest
            if (data.name.items.len == 0) {
                try data.name.appendSlice("(guest)");
                self.app.name = data.name.items;
            }

            self.screen_push = &SongSelect.SongSelect;
        },
        else => {},
    }
}

pub fn renderScreen(self: *Screen, render_state: RenderState) anyerror!void {
    var data = self.getData(MainMenuData);

    try render_state.fontstash.renderer.begin();

    _ = try render_state.fontstash.drawText(
        .{ Screen.display_width / 2, Screen.display_height / 3 },
        "ztyping",
        .{
            .font = Fontstash.Mincho,
            .size = Fontstash.ptToPx(48),
            .color = Gfx.WhiteF,
            .alignment = .{
                .horizontal = .center,
            },
        },
    );

    _ = try render_state.fontstash.drawText(
        .{ Screen.display_width - 10, Screen.display_height - 10 },
        "(c)2023 Beyley",
        .{
            .font = Fontstash.Gothic,
            .size = Fontstash.ptToPx(16),
            .color = Gfx.WhiteF,
            .alignment = .{
                .horizontal = .right,
            },
        },
    );

    _ = try render_state.fontstash.drawText(
        .{ Screen.display_width / 2, Screen.display_height * 2 / 3 },
        "Press Enter key.",
        .{
            .font = Fontstash.Mincho,
            .size = Fontstash.ptToPx(24),
            .color = Gfx.WhiteF,
            .alignment = .{
                .horizontal = .center,
            },
        },
    );

    var state: Fontstash.Fontstash.State = .{
        .font = Fontstash.Gothic,
        .size = Fontstash.ptToPx(16),
        .color = Gfx.WhiteF,
        .alignment = .{
            .vertical = .baseline,
        },
    };

    var metrics = render_state.fontstash.verticalMetrics(state);
    _ = try render_state.fontstash.drawText(
        .{ 30, 375 + metrics.line_height },
        "名前を入力してください :",
        state,
    );

    if (data.name.items.len > 0) {
        const fs_state = .{
            .font = Fontstash.Mincho,
            .size = Fontstash.ptToPx(36),
            .color = Gfx.WhiteF,
            .alignment = .{
                .vertical = .baseline,
            },
        };

        metrics = render_state.fontstash.verticalMetrics(fs_state);
        _ = try render_state.fontstash.drawText(
            .{ 60, 400 + metrics.line_height * 2 },
            data.name.items[0..(data.name.items.len)],
            fs_state,
        );
    } else {
        state = .{
            .font = Fontstash.Mincho,
            .size = Fontstash.ptToPx(36),
            .color = .{ 0.5, 0.5, 0.5, 1.0 },
            .alignment = .{
                .vertical = .baseline,
            },
        };

        metrics = render_state.fontstash.verticalMetrics(state);
        _ = try render_state.fontstash.drawText(
            .{ 60, 400 + metrics.line_height * 2 },
            "（未設定）",
            state,
        );
    }

    try render_state.fontstash.renderer.end();

    try render_state.fontstash.renderer.draw(render_state.render_pass_encoder);
}
