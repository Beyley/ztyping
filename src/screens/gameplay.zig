const std = @import("std");
const zaudio = @import("zaudio");
const builtin = @import("builtin");

const c = @import("../main.zig").c;

const Screen = @import("../screen.zig");
const Gfx = @import("../gfx.zig");

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

const SongSelectData = struct {
    phase: Phase = .ready,
    beat_line_left: usize = 0,
    beat_line_right: usize = std.math.maxInt(usize),
    last_x: f32 = 0,
    scrub_frame_counter: usize = 0,
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

    var data = try allocator.create(SongSelectData);

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
    //Load the audio file
    self.state.audio_tracker.music = try self.state.audio_tracker.engine.createSoundFromFile(audio_pathZ, .{ .flags = .{ .stream = true } });
}

pub fn deinitScreen(self: *Screen) void {
    var data = self.getData(SongSelectData);

    self.state.audio_tracker.music.?.stop() catch @panic("music stop");
    self.state.audio_tracker.music.?.destroy();
    self.allocator.destroy(data);
}

pub fn char(self: *Screen, typed_char: []const u8) Screen.ScreenError!void {
    _ = typed_char;
    var data = self.getData(SongSelectData);
    _ = data;
}

pub fn keyDown(self: *Screen, key: c.SDL_Keysym) Screen.ScreenError!void {
    var data = self.getData(SongSelectData);

    switch (key.sym) {
        c.SDLK_ESCAPE => {
            self.close_screen = true;
        },
        c.SDLK_p => {
            if (self.state.audio_tracker.music.?.isPlaying()) {
                try self.state.audio_tracker.music.?.stop();
            } else {
                try self.state.audio_tracker.music.?.start();
            }
        },
        else => {
            if (data.phase == .ready) {
                data.phase = .main;

                try self.state.audio_tracker.music.?.start();
            }
        },
    }
}

const circle_x = 100;
const circle_y = 180;
const circle_r = 30;

const lyrics_y = circle_y + circle_r + 40;

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
    var data = self.getData(SongSelectData);

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

            if ((mouse_buttons & c.SDL_BUTTON(3)) != 0 and mouse_x != data.last_x) {
                var frame = @floatToInt(u64, @intToFloat(f64, try self.state.audio_tracker.music.?.getLengthInPcmFrames()) * (mouse_x / max_x));

                try self.state.audio_tracker.music.?.seekToPcmFrame(frame);
            }

            data.last_x = mouse_x;

            data.scrub_frame_counter = 0;
        }
    }

    try render_state.fontstash.renderer.begin();
    render_state.fontstash.reset();

    try render_state.renderer.begin();

    var time: f64 = try self.state.audio_tracker.music.?.getCursorInSeconds();

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

    //Draw all the beat lines
    for (0..fumen.beat_lines.len) |i| {
        var beat_line = fumen.beat_lines[i];

        var time_diff = time - beat_line.time;
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
        var time_diff = time - lyric_cutoff.time;

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
        var time_diff = time - lyric.time;

        var posX = getDrawPosX(time_diff);
        var posY = getDrawPosY(posX);

        if (posX < 0 - circle_r) break;
        if (posX > 640 + circle_r) continue;

        //Draw the note circle itself
        try render_state.renderer.reserveTexQuadPxSize("note", .{ posX - circle_r, posY + circle_y - circle_r }, .{ circle_r * 2, circle_r * 2 }, Gfx.RedF);

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
        render_state.fontstash.drawText(.{ posX, posY + circle_y + render_state.fontstash.verticalMetrics().line_height - 3 }, lyric.text);

        //Draw the text below the notes
        render_state.fontstash.setGothic();
        render_state.fontstash.setSizePt(28);
        render_state.fontstash.drawText(.{ posX, lyrics_y + posY }, lyric.text);
    }

    //Draw the score
    render_state.fontstash.setMincho();
    render_state.fontstash.setSizePt(36);
    render_state.fontstash.setAlign(.right);
    render_state.fontstash.drawText(.{ x_score, y_score - render_state.fontstash.verticalMetrics().line_height }, "12345678");

    try render_state.renderer.reserveTexQuadPxSize("note", .{ circle_x - circle_r, circle_y - circle_r }, .{ circle_r * 2, circle_r * 2 }, Gfx.WhiteF);

    try render_state.renderer.end();
    try render_state.renderer.draw(render_state.render_pass_encoder);

    try render_state.fontstash.renderer.end();

    try render_state.fontstash.renderer.draw(render_state.render_pass_encoder);
}
