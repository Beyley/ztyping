const std = @import("std");
const bass = @import("bass");
const builtin = @import("builtin");

const c = @import("../main.zig").c;

const Screen = @import("../screen.zig");
const Gfx = @import("../gfx.zig");
const Fumen = @import("../fumen.zig");

const RenderState = Screen.RenderState;

const Phase = enum {
    ///Waiting on the player to start the game
    ready,
    ///While the game is playing
    main,
    fade_out,
    ///The results of the play
    result,
    finished,
    exit,
};

const GameplayData = struct {
    phase: Phase = .ready,
    beat_line_left: usize = 0,
    beat_line_right: usize = std.math.maxInt(usize),

    current_time: f64 = 0,

    last_mouse_x: f32 = 0,
    scrub_frame_counter: usize = 0,

    ///The current kanji lyric on display
    current_lyric_kanji: ?usize = null,

    //things Actually Relavent to the gameplay

    ///The current note the user is on
    active_note: usize = 0,
};

pub var Gameplay = Screen{
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

    var data = allocator.create(GameplayData) catch @panic("OOM");

    data.* = .{};

    self.data = data;

    //Open the dir of the fumen folder
    var dir = try std.fs.openDirAbsolute(self.state.current_map.?.fumen.fumen_folder, .{});
    defer dir.close();
    //Get the real path of the audio file
    var full_audio_path = dir.realpathAlloc(allocator, self.state.current_map.?.fumen.audio_path) catch @panic(":(");
    defer allocator.free(full_audio_path);

    //Create a sentinel-ending array for the path
    var audio_pathZ = try allocator.dupeZ(u8, full_audio_path);
    defer allocator.free(audio_pathZ);
    std.debug.print("Loading song file {s}\n", .{audio_pathZ});
    self.state.audio_tracker.music = try bass.createFileStream(
        .{ .file = .{ .path = audio_pathZ } },
        0,
        .{
            .@"union" = .{
                .stream = .prescan,
            },
        },
    );
}

pub fn deinitScreen(self: *Screen) void {
    var data = self.getData(GameplayData);

    //Stop the song
    self.state.audio_tracker.music.?.stop() catch |err| {
        std.debug.panicExtra(null, null, "Unable to stop music!!! err:{s}\n", .{@errorName(err)});
    };
    //Deinit the stream
    self.state.audio_tracker.music.?.deinit();

    //Destroy the data pointer
    self.allocator.destroy(data);
}

pub fn char(self: *Screen, typed_char: []const u8) Screen.ScreenError!void {
    _ = typed_char;
    var data = self.getData(GameplayData);
    _ = data;
}

pub fn keyDown(self: *Screen, key: c.SDL_Keysym) Screen.ScreenError!void {
    var data = self.getData(GameplayData);

    switch (key.sym) {
        c.SDLK_ESCAPE => {
            self.close_screen = true;
        },
        c.SDLK_p => {
            if (try self.state.audio_tracker.music.?.activeState() == .playing) {
                try self.state.audio_tracker.music.?.pause();
            } else {
                try self.state.audio_tracker.music.?.play(false);
            }
        },
        else => {
            if (data.phase == .ready) {
                data.phase = .main;

                try self.state.audio_tracker.music.?.play(true);
            }
        },
    }
}

const circle_x = 100;
const circle_y = 180;
const circle_r = 30;

const lyrics_y = circle_y + circle_r + 40;

const lyrics_kanji_x = 100;
const lyrics_kanji_y = lyrics_y + 35;
const lyrics_kanji_next_y = lyrics_y + 70;

const y0_bar = circle_y - 60;
const y1_bar = circle_y + 50;
const y0_beat = circle_y - 45;
const y1_beat = circle_y + 40;

const circle_speed = 250;

const x_score = 640 - 25;
const y_score = 70;

// https://github.com/toslunar/UTyping/blob/1b2eff072bda776ae4d7091f39d0c440f45d2727/UTyping.cpp#L2768
inline fn getDrawPosX(time_diff: f64) f32 {
    //return X_CIRCLE + (int)(-timeDiff * (CIRCLE_SPEED * m_challenge.speed()));
    return @floatCast(f32, circle_x + (-time_diff * (circle_speed * 1.0)));
}

const scale_function = 60;

// https://github.com/toslunar/UTyping/blob/1b2eff072bda776ae4d7091f39d0c440f45d2727/UTyping.cpp#L2773
inline fn getDrawPosY(x: f32) f32 {
    var workingX = x;

    workingX -= circle_x;
    var y: f32 = 0;
    // if(m_challenge.test(CHALLENGE_SIN)){
    // y += std.math.sin(workingX / scale_function) * scale_function;
    // }
    // if(m_challenge.test(CHALLENGE_COS)){
    // y += std.math.cos(workingX / scale_function) * scale_function;
    // }
    // if(m_challenge.test(CHALLENGE_TAN)){
    // y += std.math.tan(workingX / scale_function) * scale_function;
    // }
    return -y; // スクリーン座標は上下が逆
}

pub fn renderScreen(self: *Screen, render_state: RenderState) Screen.ScreenError!void {
    var data = self.getData(GameplayData);

    data.current_time = try self.state.audio_tracker.music.?.getSecondPosition();

    //In debug mode, allow the user to scrub through the song
    if (builtin.mode == .Debug) {
        data.scrub_frame_counter += 1;

        if (data.scrub_frame_counter > 20) {
            var mouse_x_i: c_int = 0;
            var mouse_y: c_int = 0;
            var mouse_buttons = c.SDL_GetMouseState(&mouse_x_i, &mouse_y);
            var mouse_x = @intToFloat(f32, mouse_x_i);

            var max_x = render_state.gfx.scale * 640.0;

            if (mouse_x < 0) {
                mouse_x = 0;
            }

            if (mouse_x > max_x) {
                mouse_x = max_x;
            }

            if ((mouse_buttons & c.SDL_BUTTON(3)) != 0 and mouse_x != data.last_mouse_x) {
                var byte = @floatToInt(u64, @intToFloat(f64, try self.state.audio_tracker.music.?.getLength(.byte)) * (mouse_x / max_x));

                try self.state.audio_tracker.music.?.setPosition(byte, .byte, .{});
            }

            data.last_mouse_x = mouse_x;

            data.scrub_frame_counter = 0;
        }
    }

    try render_state.fontstash.renderer.begin();
    render_state.fontstash.reset();

    try render_state.renderer.begin();

    //If we are in the ready phase, render the "Press any key to start." text
    if (data.phase == .ready) {
        render_state.fontstash.setMincho();
        render_state.fontstash.setSizePt(36);
        render_state.fontstash.setAlign(.baseline);

        render_state.fontstash.drawText(
            .{ 50, 370 - render_state.fontstash.verticalMetrics().line_height },
            "Press any key to start.",
        );
    }

    var fumen = self.state.current_map.?.fumen;

    try drawGameplayLyrics(render_state, data, fumen);

    drawKanjiLyrics(render_state, data, fumen);

    drawScoreUi(render_state, data, fumen);

    try render_state.renderer.end();
    try render_state.renderer.draw(render_state.render_pass_encoder);

    try render_state.fontstash.renderer.end();

    try render_state.fontstash.renderer.draw(render_state.render_pass_encoder);

    if (builtin.mode == .Debug) {
        var open = false;
        _ = c.igBegin("Gameplay Debugging", &open, 0);

        c.igText("Active Note: %d", data.active_note);

        c.igEnd();
    }
}

fn drawScoreUi(render_state: Screen.RenderState, data: *GameplayData, fumen: Fumen) void {
    _ = fumen;
    _ = data;
    //Draw the score
    render_state.fontstash.setMincho();
    render_state.fontstash.setSizePt(36);
    render_state.fontstash.setAlign(.right);
    render_state.fontstash.drawText(.{ x_score, y_score - render_state.fontstash.verticalMetrics().line_height }, "12345678");
}

fn drawGameplayLyrics(render_state: Screen.RenderState, data: *GameplayData, fumen: Fumen) !void {
    //Draw all the beat lines
    for (0..fumen.beat_lines.len) |i| {
        var beat_line = fumen.beat_lines[i];

        var time_diff = data.current_time - beat_line.time;
        var posX = getDrawPosX(time_diff);
        var posY = getDrawPosY(posX);

        if (posX < 0) continue;
        if (posX > 640) break;

        switch (beat_line.type) {
            .bar => {
                try render_state.renderer.reserveTexQuad("white", .{ posX, posY + y0_bar }, .{ 1, y1_bar - y0_bar }, Gfx.WhiteF);
            },
            .beat => {
                try render_state.renderer.reserveTexQuad("white", .{ posX, posY + y0_beat }, .{ 1, y1_beat - y0_beat }, .{ 0.5, 0.5, 0.5, 1 });
            },
        }
    }

    //Draw all the typing cutoffs
    for (0..fumen.lyric_cutoffs) |j| {
        var i = fumen.lyric_cutoffs.len - 1 - j;

        var lyric_cutoff = fumen.lyric_cutoffs[i];
        var time_diff = data.current_time - lyric_cutoff.time;

        var posX = getDrawPosX(time_diff);
        var posY = getDrawPosY(posX);

        if (posX < 0 - circle_r) break;
        if (posX > 640 + circle_r) continue;

        //Draw the note circle itself
        try render_state.renderer.reserveTexQuadPxSize("typing_cutoff", .{ posX - circle_r, posY + circle_y - circle_r }, .{ circle_r * 2, circle_r * 2 }, Gfx.WhiteF);
    }

    //Draw all the lyrics
    for (0..fumen.lyrics.len) |j| {
        var i = fumen.lyrics.len - 1 - j;

        var lyric = fumen.lyrics[i];
        var time_diff = data.current_time - lyric.time;

        var posX = getDrawPosX(time_diff);
        var posY = getDrawPosY(posX);

        if (posX < 0 - circle_r) break;
        if (posX > 640 + circle_r) continue;

        //Draw the note circle itself
        try render_state.renderer.reserveTexQuadPxSize(
            "note",
            .{ posX - circle_r, posY + circle_y - circle_r },
            .{ circle_r * 2, circle_r * 2 },
            Gfx.RedF,
        );

        if (builtin.mode == .Debug) {
            if (i == data.active_note) {
                try render_state.renderer.reserveTexQuadPxSize(
                    "note",
                    .{ posX - circle_r / 2, posY + circle_y - circle_r * 2 },
                    .{ circle_r, circle_r },
                    Gfx.BlueF,
                );
            }
        }

        var size: f32 = 50;

        //Set the initial font settings
        render_state.fontstash.setMincho();
        render_state.fontstash.setSizePt(size);
        render_state.fontstash.setAlign(.center);

        //If the font size is too big and it goes outside of the notes,
        var bounds = render_state.fontstash.textBounds(lyric.text);
        while (bounds.x2 > circle_r) {
            //Shrink the font size
            size -= 5;
            render_state.fontstash.setSizePt(size);

            bounds = render_state.fontstash.textBounds(lyric.text);
        }

        //Draw the text inside of the notes
        render_state.fontstash.drawText(
            .{
                posX,
                posY + circle_y + render_state.fontstash.verticalMetrics().line_height - 3,
            },
            lyric.text,
        );

        //Draw the text below the notes
        render_state.fontstash.setGothic();
        render_state.fontstash.setSizePt(28);
        render_state.fontstash.drawText(.{ posX, lyrics_y + posY }, lyric.text);
    }

    try render_state.renderer.reserveTexQuadPxSize("note", .{ circle_x - circle_r, circle_y - circle_r }, .{ circle_r * 2, circle_r * 2 }, Gfx.WhiteF);
}

fn drawKanjiLyrics(render_state: Screen.RenderState, data: *GameplayData, fumen: Fumen) void {
    const next_string = "Next: ";

    render_state.fontstash.setAlign(.left);
    render_state.fontstash.setGothic();
    render_state.fontstash.setSizePt(16);

    var bounds = render_state.fontstash.textBounds(next_string);
    var next_string_width = bounds.x2 - bounds.x1;

    render_state.fontstash.drawText(.{ lyrics_kanji_x - next_string_width, lyrics_kanji_next_y }, next_string);

    //Move the current lyric forward by 1, if applicable
    while (data.current_lyric_kanji != null and fumen.lyrics_kanji[data.current_lyric_kanji.?].time_end < data.current_time) {
        if (data.current_lyric_kanji.? != fumen.lyrics_kanji.len - 1) {
            data.current_lyric_kanji.? += 1;
        } else {
            break;
        }
    }

    //If we havent reached a lyric yet, check if we have reached it
    if (data.current_lyric_kanji == null and fumen.lyrics_kanji[0].time < data.current_time) {
        data.current_lyric_kanji = 0;
    }

    //If the current lyric has started,
    if (data.current_lyric_kanji != null and fumen.lyrics_kanji[data.current_lyric_kanji.?].time < data.current_time) {
        //Draw the lyric
        fumen.lyrics_kanji[data.current_lyric_kanji.?].draw(lyrics_kanji_x, lyrics_kanji_y, render_state);
    }

    //If we are not at the last lyric
    if (data.current_lyric_kanji != null and data.current_lyric_kanji.? < fumen.lyrics_kanji.len - 1) {
        const next_lyric_kanji = fumen.lyrics_kanji[data.current_lyric_kanji.? + 1];

        //Draw the next lyirc
        next_lyric_kanji.draw(lyrics_kanji_x, lyrics_kanji_next_y, render_state);
    }
    //If we have not reached a lyric yet
    else if (data.current_lyric_kanji == null) {
        const next_lyric_kanji = fumen.lyrics_kanji[0];

        //Draw the next lyirc
        next_lyric_kanji.draw(lyrics_kanji_x, lyrics_kanji_next_y, render_state);
    }
}
