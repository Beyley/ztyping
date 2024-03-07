const builtin = @import("builtin");
const std = @import("std");
const core = @import("mach").core;

const Screen = @import("../screen.zig");
const Gfx = @import("../gfx.zig");
const Gameplay = @import("gameplay.zig");
const Music = @import("../music.zig");
const Fontstash = @import("../fontstash.zig");
const Challenge = @import("../challenge.zig");
const App = @import("../app.zig");

const RenderState = Screen.RenderState;

const SongSelectData = struct {
    draw_info: DrawInfo,
    challenge_info: Challenge.ChallengeInfo,
    step_timer: f64,
};

pub var SongSelect = Screen{
    .render = renderScreen,
    .init = initScreen,
    .deinit = deinitScreen,
    .allocator = undefined,
    // .char = char,
    .reenter = reenter,
    .key_down = keyDown,
    .data = undefined,
    .app = undefined,
};

pub fn initScreen(self: *Screen, allocator: std.mem.Allocator, gfx: Gfx) anyerror!void {
    _ = gfx;
    self.allocator = allocator;

    const data = try allocator.create(SongSelectData);
    data.* = .{
        .draw_info = DrawInfo{
            .ranking_flag = false,
            .draw_pos = .{ 0, 0 },
            .add_height = std.mem.zeroes([DrawInfo.add_height_count]f32),
            .add_height_wait = 25,
            .music_iter = .{
                .music = self.app.map_list,
                .idx = 0,
            },
            .ranking_pos = 0,
            .searching = false,
        },
        .challenge_info = .{},
        .step_timer = 0,
    };

    self.data = data;
}

pub fn deinitScreen(self: *Screen) void {
    const data = self.getData(SongSelectData);

    self.allocator.destroy(data);
}

// pub fn char(self: *Screen, typed_char: []const u8) void {
//     _ = typed_char;
//     var data = self.getData(SongSelectData);
//     _ = data;
// }

pub fn reenter(self: *Screen) anyerror!void {
    var data = self.getData(SongSelectData);

    data.draw_info.resetPos();
}

pub fn keyDown(self: *Screen, key: core.Key) anyerror!void {
    var data = self.getData(SongSelectData);

    switch (key) {
        .escape => {
            self.close_screen = true;
        },
        //If the user presses either enter/return key,
        .enter, .kp_enter => {
            //Set the current map
            self.app.current_map = data.draw_info.music_iter.curr().*;
            //Push the gameplay scene onto the top of the stack
            self.screen_push = &Gameplay.Gameplay;
            Gameplay.challenge = data.challenge_info;
        },
        .r => {
            data.draw_info.random(self.app);
        },
        .f => {
            //TODO: search
        },
        .up => data.draw_info.prev(),
        .down => data.draw_info.next(),
        .right => data.draw_info.right(),
        .left => data.draw_info.left(),
        .h => {
            data.challenge_info.hidden = !data.challenge_info.hidden;
            //Stealth and hidden are incompatible, so if we are toggling hidden on, disable stealth
            if (data.challenge_info.hidden) {
                data.challenge_info.stealth = false;
            }
        },
        .s => {
            data.challenge_info.sudden = !data.challenge_info.sudden;
            //Stealth and sudden are incompatible, so if we are toggling sudden on, disable stealth
            if (data.challenge_info.sudden) {
                data.challenge_info.stealth = false;
            }
        },
        .c => {
            data.challenge_info.stealth = !data.challenge_info.stealth;
            //Stealth is incompatible with hidden and sudden, so if we are toggling stealth on, disable both of those
            if (data.challenge_info.stealth) {
                data.challenge_info.hidden = false;
                data.challenge_info.sudden = false;
            }
        },
        .l => data.challenge_info.lyrics_stealth = !data.challenge_info.lyrics_stealth,
        //Speed up
        .period => {
            if (data.challenge_info.speed < 2) {
                data.challenge_info.speed += 0.1;
            } else if (data.challenge_info.speed < 3) {
                data.challenge_info.speed += 0.2;
            } else if (data.challenge_info.speed < 4) {
                data.challenge_info.speed += 0.5;
            }
            //Round to nearest tenth to prevent floating point rounding errors
            data.challenge_info.speed = @round(data.challenge_info.speed * 10.0) / 10.0;
        },
        //Speed down
        .comma => {
            if (data.challenge_info.speed > 3) {
                data.challenge_info.speed -= 0.5;
            } else if (data.challenge_info.speed > 2) {
                data.challenge_info.speed -= 0.2;
            } else if (data.challenge_info.speed > 0.5) {
                data.challenge_info.speed -= 0.1;
            }
            //Round to nearest tenth to prevent floating point rounding errors
            data.challenge_info.speed = @round(data.challenge_info.speed * 10.0) / 10.0;
        },
        //Key down
        .minus => {
            if (data.challenge_info.key > -12) {
                data.challenge_info.key -= 1;
            }
        },
        //Key up
        .equal => {
            if (data.challenge_info.key < 12) {
                data.challenge_info.key += 1;
            }
        },
        .left_bracket => {
            if (data.challenge_info.audio_offset > -1000) {
                data.challenge_info.audio_offset -= 1;
            }
        },
        .right_bracket => {
            if (data.challenge_info.audio_offset < 1000) {
                data.challenge_info.audio_offset += 1;
            }
        },
        .f6 => data.challenge_info.sin = !data.challenge_info.sin,
        .f7 => data.challenge_info.cos = !data.challenge_info.cos,
        .f8 => data.challenge_info.tan = !data.challenge_info.tan,
        .zero => data.draw_info.music_iter.noSort(),
        .one => data.draw_info.music_iter.sortTitle(),
        .two => data.draw_info.music_iter.sortArtist(),
        .three => data.draw_info.music_iter.sortLevel(),
        // TODO:
        // c.SDLK_4 => data.draw_info.music_iter.sortAchievement(),
        else => {},
    }
}

const music_info_height = 60;
const ranking_draw_len = 5;
const ranking_len = 20;

const DrawInfo = struct {
    ranking_pos: isize,
    ///Whether we are displaying the rankings or not
    ranking_flag: bool,

    draw_pos: Gfx.Vector2,
    add_height: [add_height_count]f32,
    add_height_wait: f32,

    music_iter: MusicIterator,

    searching: bool,

    //21 elements, 10 on each side, one in the middle
    const add_height_count = 21;
    //Get the center element
    const add_height_middle = (add_height_count - 1) / 2;

    pub fn resetPos(self: *DrawInfo) void {
        self.ranking_pos = 0;
        self.draw_pos = .{ 0, 0 };
        for (&self.add_height) |*height| {
            height.* = 0;
        }
        self.add_height_wait = 25;
    }

    pub fn step(self: *DrawInfo) void {
        for (&self.add_height, 0..) |*height, i| {
            const h: f32 =
                if (i == add_height_middle)
            blk: {
                const h: f32 = if (self.ranking_flag)
                    h_ranking
                else if (self.ranking_pos == 0)
                    h_ranking1
                else
                    h_music_info_sub;

                //If the add height is basically 0,
                if (self.add_height[add_height_middle] < 1 and self.add_height_wait > 0) {
                    //Decrement the waiting timer
                    self.add_height_wait -= 1;
                    //Continue, preventing `height` from being added to
                    continue;
                }
                break :blk h;
            } else 0;
            height.* = h + ((height.* - h) * 0.8);
        }

        self.draw_pos[0] *= 0.7;

        const sign = std.math.sign(self.draw_pos[1]);
        var tmp = -0.05 * self.draw_pos[1];

        tmp -= sign * 1;
        tmp -= sign * 0.0010 * self.draw_pos[1] * self.draw_pos[1];

        self.draw_pos[1] += tmp;

        if (self.draw_pos[1] * tmp > 0) {
            self.draw_pos[1] = 0;
        }
    }

    pub fn next(self: *DrawInfo) void {
        self.music_iter.next();

        self.draw_pos[1] += music_info_height + (self.add_height[add_height_middle] + self.add_height[add_height_middle + 1]) / 2.0;

        for (self.add_height[0 .. self.add_height.len - 1], self.add_height[1..self.add_height.len]) |*old, new| {
            old.* = new;
        }
        //Set the last item to 0
        self.add_height[self.add_height.len - 1] = 0;

        self.add_height_wait = 25;

        self.ranking_pos = 0;
        self.ranking_flag = false;
    }

    pub fn prev(self: *DrawInfo) void {
        self.music_iter.prev();

        self.draw_pos[1] -= music_info_height + (self.add_height[add_height_middle] + self.add_height[add_height_middle - 1]) / 2.0;

        var i: usize = self.add_height.len - 1;
        while (i > 0) {
            self.add_height[i] = self.add_height[i - 1];
            i -= 1;
        }
        //Set the first item to 0
        self.add_height[0] = 0;

        self.add_height_wait = 25;

        self.ranking_pos = 0;
        self.ranking_flag = false;
    }

    pub fn left(self: *DrawInfo) void {
        if (self.ranking_pos < 0) {
            return;
        }

        self.add_height_wait /= 2;

        if (self.ranking_pos == 0 and self.ranking_flag) {
            self.ranking_flag = false;
        } else {
            self.ranking_pos -= ranking_draw_len;
            self.draw_pos[0] -= Screen.display_width;
        }
    }

    pub fn right(self: *DrawInfo) void {
        if (self.ranking_pos + ranking_draw_len > ranking_len) {
            return;
        }

        self.add_height_wait /= 2;

        if (self.ranking_pos == 0 and !self.ranking_flag) {
            self.ranking_flag = true;
        } else {
            self.ranking_pos += ranking_draw_len;
            self.draw_pos[0] += Screen.display_width;
        }
    }

    pub fn find(self: *DrawInfo, query: []const u8) void {
        _ = query;
        _ = self;

        //TODO
    }

    pub fn jump(self: *DrawInfo, idx: usize) void {
        //If the index is invalid, ignore it
        if (idx <= 0 or idx > self.music_iter.music.len) {
            return;
        }

        //Go through all the songs until we are at the right one
        while (self.music_iter.idx != idx) : (self.music_iter.next()) continue;
    }

    pub fn random(self: *DrawInfo, game_state: *App) void {
        //Get a random number from 0 - music.len
        const selection: usize = @intFromFloat(@as(f64, @floatFromInt(game_state.random.next())) / std.math.maxInt(u64) * @as(f64, @floatFromInt(self.music_iter.music.len - 1)));
        //Jump to the random selection
        self.jump(selection);
    }
};

pub const MusicIterator = struct {
    music: []Music,
    idx: usize,

    pub fn prev(self: *MusicIterator) void {
        if (self.idx == 0) {
            self.idx = self.music.len - 1;
        } else {
            self.idx -= 1;
        }
    }

    pub fn next(self: *MusicIterator) void {
        self.idx += 1;
        self.idx %= self.music.len;
    }

    pub fn curr(self: *MusicIterator) *const Music {
        return &self.music[self.idx];
    }

    fn noSortComparison(context: void, lhs: Music, rhs: Music) bool {
        _ = context;
        return lhs.sort_idx < rhs.sort_idx;
    }

    pub fn noSort(self: *MusicIterator) void {
        std.sort.block(Music, self.music, {}, noSortComparison);
    }

    fn titleComparison(context: void, lhs: Music, rhs: Music) bool {
        _ = context;
        return std.ascii.lessThanIgnoreCase(lhs.title, rhs.title);
    }

    pub fn sortTitle(self: *MusicIterator) void {
        std.sort.block(Music, self.music, {}, titleComparison);
    }

    fn artistComparison(context: void, lhs: Music, rhs: Music) bool {
        _ = context;
        return std.ascii.lessThanIgnoreCase(lhs.artist, rhs.artist);
    }

    pub fn sortArtist(self: *MusicIterator) void {
        std.sort.block(Music, self.music, {}, artistComparison);
    }

    fn levelComparison(context: void, lhs: Music, rhs: Music) bool {
        _ = context;
        return lhs.level < rhs.level;
    }

    pub fn sortLevel(self: *MusicIterator) void {
        std.sort.block(Music, self.music, {}, levelComparison);
    }

    // fn achievementComparison(context: void, lhs: Music, rhs: Music) bool {
    //     _ = context;
    //     //TODO: implement this properly
    //     return lhs.level < rhs.level;
    // }

    // pub fn sortAchievement(self: *MusicIterator) void {
    //     std.sort.block(Music, self.music, {}, levelComparison);
    // }
};

pub const h_ranking = 252;
pub const h_ranking1 = 60;

pub const h_comment = 240;
pub const h_play_data = 40;

pub const h_music_info_sub = 6 + h_comment + 4 + h_play_data + 6;

pub fn renderScreen(self: *Screen, render_state: RenderState) anyerror!void {
    var data = self.getData(SongSelectData);

    // var open = true;

    // // if (builtin.mode == .Debug) {
    // //     _ = c.igBegin("Test", &open, c.ImGuiWindowFlags_AlwaysVerticalScrollbar);

    // //     for (data.draw_info.add_height) |height| {
    // //         c.igText("height: %f", height);
    // //     }
    // //     c.igText("wait: %f", data.draw_info.add_height_wait);
    // //     c.igText("ranking pos: %d", data.draw_info.ranking_pos);

    // //     c.igEnd();
    // // }

    try render_state.renderer.begin();
    try render_state.fontstash.renderer.begin();

    // zig fmt: off
    const dy = 180 + (music_info_height - data.draw_info.add_height[DrawInfo.add_height_middle]) / 2 
                   + @floor(data.draw_info.draw_pos[1] + 0.5);
    // zig fmt: on

    {
        const rect: Gfx.RectU = .{ 10, 0, @intFromFloat((Screen.display_width - 10) * render_state.gfx.scale), @intFromFloat(360 * render_state.gfx.scale) };
        try render_state.renderer.setScissor(rect);
        try render_state.fontstash.renderer.setScissor(rect);
    }
    {
        //Draw a box from the top left of the area to the bottom right
        try render_state.renderer.reserveSolidBox(
            .{ 10, dy - music_info_height },
            .{ Screen.display_width - 20, data.draw_info.add_height[DrawInfo.add_height_middle] + music_info_height },
            .{ 16.0 / 255.0, 16.0 / 255.0, 32.0 / 255.0, 1 },
        );
        try data.draw_info.music_iter.curr().draw(
            render_state,
            dy - music_info_height,
            1,
            data.draw_info.music_iter.idx,
            data.draw_info.music_iter.music.len,
        );
        try render_state.renderer.reserveSolidBox(
            .{ 40, dy },
            .{ Screen.display_width - 80, 1 },
            .{ 64.0 / 255.0, 64.0 / 255.0, 64.0 / 255.0, 1 },
        );

        try drawMainRanking(
            render_state,
            data.draw_info.music_iter.curr().*,
            data.draw_info.ranking_pos,
            .{ data.draw_info.draw_pos[0], dy },
            data.draw_info.add_height[DrawInfo.add_height_middle],
        );
        if (data.draw_info.draw_pos[0] < 0) {
            try drawMainRanking(
                render_state,
                data.draw_info.music_iter.curr().*,
                data.draw_info.ranking_pos + ranking_draw_len,
                .{ data.draw_info.draw_pos[0] + Screen.display_width, dy },
                data.draw_info.add_height[DrawInfo.add_height_middle],
            );
        } else if (data.draw_info.draw_pos[0] > 0) {
            try drawMainRanking(
                render_state,
                data.draw_info.music_iter.curr().*,
                data.draw_info.ranking_pos - ranking_draw_len,
                .{ data.draw_info.draw_pos[0] - Screen.display_width, dy },
                data.draw_info.add_height[DrawInfo.add_height_middle],
            );
        }
    }
    {
        const rect: Gfx.RectU = .{ 10, 0, @intFromFloat((Screen.display_width - 10) * render_state.gfx.scale), @intFromFloat(360 * render_state.gfx.scale) };
        try render_state.renderer.setScissor(rect);
        try render_state.fontstash.renderer.setScissor(rect);
    }
    { //draw songs above current one
        var iter = data.draw_info.music_iter;

        var y: f32 = dy - music_info_height;
        var count: usize = 0;
        while (y >= 0) {
            const line_color = Gfx.ColorF{
                1.0 / @as(f32, @floatFromInt(count + 2)),
                1.0 / @as(f32, @floatFromInt(count + 2)),
                1.0 / @as(f32, @floatFromInt(count + 2)),
                1.0,
            };
            //Draw a solid line separating the songs
            try render_state.renderer.reserveSolidBox(.{ 10, y }, .{ Screen.display_width - 20, 1 }, line_color);
            iter.prev();
            count += 1;
            y -= music_info_height + data.draw_info.add_height[DrawInfo.add_height_middle - count];
            try iter.curr().draw(
                render_state,
                y,
                1.0 / @as(f32, @floatFromInt((count + 1))),
                iter.idx,
                iter.music.len,
            );
        }
    }
    {
        const rect: Gfx.RectU = .{ 10, 0, @intFromFloat((Screen.display_width - 10) * render_state.gfx.scale), @intFromFloat(360 * render_state.gfx.scale) };
        try render_state.renderer.setScissor(rect);
        try render_state.fontstash.renderer.setScissor(rect);
    }
    { //draw songs below current one
        var iter = data.draw_info.music_iter;

        var y: f32 = dy + data.draw_info.add_height[DrawInfo.add_height_middle];
        var count: usize = 0;
        while (y < 360) {
            const line_color = Gfx.ColorF{
                1.0 / @as(f32, @floatFromInt(count + 2)),
                1.0 / @as(f32, @floatFromInt(count + 2)),
                1.0 / @as(f32, @floatFromInt(count + 2)),
                1.0,
            };
            //Draw a solid line separating the songs
            try render_state.renderer.reserveSolidBox(.{ 10, y }, .{ Screen.display_width - 20, 1 }, line_color);
            iter.next();
            count += 1;
            try iter.curr().draw(
                render_state,
                y,
                1.0 / @as(f32, @floatFromInt(count + 1)),
                iter.idx,
                iter.music.len,
            );
            y += music_info_height + data.draw_info.add_height[DrawInfo.add_height_middle + count];
        }
    }
    try render_state.renderer.resetScissor();
    try render_state.fontstash.renderer.resetScissor();

    try render_state.renderer.reserveSolidBox(
        .{ 0, 360 },
        .{ Screen.display_width, Screen.display_height - 360 - 25 },
        .{ 0.1, 0.1, 0.1, 1 },
    );
    try render_state.renderer.reserveSolidBox(
        .{ 0, 360 },
        .{ Screen.display_width, 1 },
        .{ 0.666, 0.666, 0.666, 1 },
    );

    if (!data.draw_info.searching) {
        _ = try render_state.fontstash.drawText(
            .{ 10, 370 },
            "↑/↓: 曲選択,  F: 検索, 0～4:ソート, R: ランダム,  F5: 再読込,",
            Fontstash.Normal,
        );
        _ = try render_state.fontstash.drawText(
            .{ 10, 390 },
            "←/→: 情報/ランキング表示,  Tab: 全画面切替",
            Fontstash.Normal,
        );
        {
            var state = Fontstash.Normal;
            state.alignment.horizontal = .right;

            _ = try render_state.fontstash.drawText(
                .{ Screen.display_width - 10, 370 },
                "Enter: 決定",
                state,
            );
            _ = try render_state.fontstash.drawText(
                .{ Screen.display_width - 10, 390 },
                "!/?: Replay Save/Load",
                state,
            );
        }

        _ = try render_state.fontstash.drawText(
            .{ 10, Screen.display_height - 65 },
            "[H]idden, [S]udden, [C]ircleStealth, [L]yricsStealth,",
            Fontstash.Normal,
        );
        _ = try render_state.fontstash.drawText(
            .{ 10, Screen.display_height - 45 },
            "</>: Speed Down/Up, +/-: KeyShift,   F6/F7/F8: sin/cos/tan,",
            Fontstash.Normal,
        );

        {
            var state = Fontstash.Normal;
            state.alignment.horizontal = .right;

            _ = try render_state.fontstash.drawText(
                .{ Screen.display_width - 10, Screen.display_height - 65 },
                "Reset to [D]efault",
                state,
            );

            _ = try render_state.fontstash.drawText(
                .{ Screen.display_width - 10, Screen.display_height - 45 },
                "Esc: 終了",
                state,
            );
        }
    } else {
        //TODO: search
    }

    { //draw players name in the bottom right
        var state = Fontstash.Normal;
        state.alignment.horizontal = .right;

        if (std.mem.eql(u8, self.app.name, "(guest)")) {
            state.color = .{ 0.5, 0.5, 0.5, 1 };
        } else {
            state.color = .{ 1, 1, 1, 1 };
        }

        const bounds = try render_state.fontstash.textBounds(self.app.name, state);
        const width = bounds.x2 - bounds.x1;

        const background_color = .{ 0.0627, 0.0627, 0.1254, 1 };
        try render_state.renderer.reserveSolidBox(
            .{ Screen.display_width - 20 - width, Screen.display_height - 25 },
            .{ 20 + width, 25 },
            background_color,
        );

        _ = try render_state.fontstash.drawText(
            .{ Screen.display_width - 10, Screen.display_height - 20 },
            self.app.name,
            state,
        );
    }

    try render_state.renderer.reserveSolidBox(
        .{ 0, Screen.display_height - 25 },
        .{ Screen.display_width, 1 },
        .{ 2.0 / 3.0, 2.0 / 3.0, 2.0 / 3.0, 1 },
    );

    //TODO: draw enabled mod names
    if (data.challenge_info.stealth) {
        var state = Fontstash.Normal;
        state.color = .{ 1, 0.125, 0, 1 };
        _ = try render_state.fontstash.drawText(
            .{ 130, Screen.display_height - 20 },
            "[ CStealth ]",
            state,
        );
    } else {
        if (data.challenge_info.hidden and data.challenge_info.sudden) {
            var state = Fontstash.Normal;
            state.color = .{ 1, 0.5, 0, 1 };
            _ = try render_state.fontstash.drawText(
                .{ 130, Screen.display_height - 20 },
                "[ Hid.Sud. ]",
                state,
            );
        } else if (data.challenge_info.hidden) {
            var state = Fontstash.Normal;
            state.color = .{ 1, 1, 0, 1 };
            _ = try render_state.fontstash.drawText(
                .{ 130, Screen.display_height - 20 },
                "[ Hidden ]",
                state,
            );
        } else if (data.challenge_info.sudden) {
            var state = Fontstash.Normal;
            state.color = .{ 1, 1, 0, 1 };
            _ = try render_state.fontstash.drawText(
                .{ 130, Screen.display_height - 20 },
                "[ Sudden ]",
                state,
            );
        } else {
            var state = Fontstash.Normal;
            state.color = .{ 0.25, 0.25, 0.25, 1 };
            _ = try render_state.fontstash.drawText(
                .{ 130, Screen.display_height - 20 },
                "[ Hid.Sud. ]",
                state,
            );
        }
    }

    {
        var state = Fontstash.Normal;
        state.color = if (data.challenge_info.lyrics_stealth) .{ 1, 0.5, 0, 1 } else .{ 0.25, 0.25, 0.25, 1 };
        _ = try render_state.fontstash.drawText(
            .{ 230, Screen.display_height - 20 },
            "[ LStealth ]",
            state,
        );
    }

    {
        var state = Fontstash.Normal;
        if (data.challenge_info.speed > 3) {
            state.color = .{ 1, 0.125, 0, 1 };
        } else if (data.challenge_info.speed > 2) {
            state.color = .{ 1, 0.5, 0, 1 };
        } else if (data.challenge_info.speed > 1) {
            state.color = .{ 1, 1, 0, 1 };
        } else if (data.challenge_info.speed < 1) {
            state.color = .{ 0.5, 0.5, 1, 1 };
        } else {
            state.color = .{ 0.25, 0.25, 0.25, 1 };
        }
        state.size *= render_state.gfx.scale;
        var context: Fontstash.Fontstash.WriterContext = .{
            .state = state,
            .draw = true,
            .draw_position = Gfx.Vector2{ 10, Screen.display_height - 20 } * @as(Gfx.Vector2, @splat(render_state.gfx.scale)),
        };
        var writer = try render_state.fontstash.context.writer(&context);
        try writer.writeAll("[ Speed x");
        try std.fmt.formatFloatDecimal(data.challenge_info.speed, .{ .precision = 1 }, writer);
        try writer.writeAll(" ]");
    }

    {
        var state = Fontstash.Normal;

        const sign: bool = blk: {
            if (data.challenge_info.key > 8) {
                state.color = .{ 1, 0.125, 0, 1 };
                break :blk true;
            } else if (data.challenge_info.key > 4) {
                state.color = .{ 1, 0.5, 0, 1 };
                break :blk true;
            } else if (data.challenge_info.key > 0) {
                state.color = .{ 1, 1, 0, 1 };
                break :blk true;
            } else {
                state.color = .{ 0.5, 1, 0, 1 };
                break :blk false;
            }
        };

        state.size *= render_state.gfx.scale;
        var context: Fontstash.Fontstash.WriterContext = .{
            .state = state,
            .draw = true,
            .draw_position = Gfx.Vector2{ 330, Screen.display_height - 20 } * @as(Gfx.Vector2, @splat(render_state.gfx.scale)),
        };
        const writer = try render_state.fontstash.context.writer(&context);

        if (data.challenge_info.key == 0) {
            context.state.color = .{ 0.25, 0.25, 0.25, 1 };
            try std.fmt.format(writer, "[ Key 0 ]", .{});
        } else {
            try std.fmt.format(
                writer,
                "[ Key {s}{d:.2} ]",
                .{
                    if (sign) "+" else "",
                    data.challenge_info.key,
                },
            );
        }
    }

    {
        var state = Fontstash.Normal;

        const sct_text = blk: {
            if (data.challenge_info.sin) {
                if (data.challenge_info.cos) {
                    if (data.challenge_info.tan) {
                        state.color = .{ 1, 0.5, 0, 1 };
                        break :blk "[sct]";
                    } else {
                        state.color = .{ 1, 0.5, 0, 1 };
                        break :blk "[sc-]";
                    }
                } else {
                    if (data.challenge_info.tan) {
                        state.color = .{ 1, 0.5, 0, 1 };
                        break :blk "[s-t]";
                    } else {
                        state.color = .{ 1, 1, 0, 1 };
                        break :blk "[sin]";
                    }
                }
            } else {
                if (data.challenge_info.cos) {
                    if (data.challenge_info.tan) {
                        state.color = .{ 1, 0.5, 0, 1 };
                        break :blk "[-ct]";
                    } else {
                        state.color = .{ 1, 1, 0, 1 };
                        break :blk "[cos]";
                    }
                } else {
                    if (data.challenge_info.tan) {
                        state.color = .{ 1, 1, 0, 1 };
                        break :blk "[tan]";
                    } else {
                        state.color = .{ 0.25, 0.25, 0.25, 1 };
                        break :blk "[sct]";
                    }
                }
            }
        };

        _ = try render_state.fontstash.drawText(.{ 430, Screen.display_height - 20 }, sct_text, state);
    }

    {
        var state = Fontstash.Normal;

        state.size *= render_state.gfx.scale;
        var context: Fontstash.Fontstash.WriterContext = .{
            .state = state,
            .draw = true,
            .draw_position = Gfx.Vector2{ 470, Screen.display_height - 20 } * @as(Gfx.Vector2, @splat(render_state.gfx.scale)),
        };
        const writer = try render_state.fontstash.context.writer(&context);

        try std.fmt.format(writer, "[ Offset: {d} ]", .{data.challenge_info.audio_offset});
    }

    const step_timer_length = 1.0 / 60.0;

    data.step_timer += core.delta_time;

    if (data.step_timer >= step_timer_length) {
        data.draw_info.step();

        data.step_timer -= step_timer_length;
    }

    try render_state.fontstash.renderer.end();
    try render_state.renderer.end();

    try render_state.renderer.draw(render_state.render_pass_encoder);
    try render_state.fontstash.renderer.draw(render_state.render_pass_encoder);
}

fn drawMainRanking(render_state: Screen.RenderState, music: Music, ranking_pos: isize, pos: Gfx.Vector2, height: f32) !void {
    const yMin = @max(pos[1], 0);
    const yMax = @min(pos[1] + height, 360);

    var scissor: Gfx.RectF = .{ 10, yMin, Screen.display_width - 20, yMax - yMin };
    scissor *= @splat(render_state.gfx.scale);

    const scissor_u: Gfx.RectU = .{
        @intFromFloat(@max(0, scissor[0])),
        @intFromFloat(@max(0, scissor[1])),
        @intFromFloat(@max(0, scissor[2])),
        @intFromFloat(@max(0, scissor[3])),
    };

    try render_state.renderer.setScissor(scissor_u);
    try render_state.fontstash.renderer.setScissor(scissor_u);

    if (ranking_pos >= 0) {
        try music.ranking.draw(render_state, .{ pos[0], pos[1] + 6 }, @intCast(ranking_pos), ranking_draw_len);
    } else {
        try music.drawComment(render_state, .{ pos[0], pos[1] + 6 });
        try music.drawPlayData(render_state, .{ pos[0], pos[1] + 6 + h_comment + 4 });
    }
}
