const std = @import("std");

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

pub fn initScreen(self: *Screen, allocator: std.mem.Allocator, gfx: Gfx) bool {
    _ = gfx;
    self.allocator = allocator;

    var data = allocator.create(SongSelectData) catch @panic("OOM");

    data.* = .{};

    self.data = data;

    //Open the dir of the fumen folder
    var dir = std.fs.openDirAbsolute(self.state.current_map.?.fumen.fumen_folder, .{}) catch @panic("Unable to open fumen folder");
    defer dir.close();
    //Get the real path of the audio file
    var full_audio_path = dir.realpathAlloc(allocator, self.state.current_map.?.fumen.audio_path) catch @panic("OOM");
    defer allocator.free(full_audio_path);

    //Create a sentinel-ending array for the path
    var audio_pathZ = allocator.dupeZ(u8, full_audio_path) catch @panic("OOM");
    defer allocator.free(audio_pathZ);
    //Load the audio file
    self.state.audio_tracker.music = self.state.audio_tracker.engine.createSoundFromFile(audio_pathZ, .{ .flags = .{ .stream = true } }) catch @panic("cant load song...");

    return true;
}

pub fn deinitScreen(self: *Screen) void {
    var data = self.getData(SongSelectData);

    self.state.audio_tracker.music.?.stop() catch @panic("music stop");
    self.state.audio_tracker.music.?.destroy();
    self.allocator.destroy(data);
}

pub fn char(self: *Screen, typed_char: []const u8) void {
    _ = typed_char;
    var data = self.getData(SongSelectData);
    _ = data;
}

pub fn keyDown(self: *Screen, key: c.SDL_Keysym) void {
    var data = self.getData(SongSelectData);

    switch (key.sym) {
        c.SDLK_ESCAPE => {
            self.close_screen = true;
        },
        else => {
            if (data.phase == .ready) {
                data.phase = .main;

                self.state.audio_tracker.music.?.start() catch @panic("Unable to play song");
            }
        },
    }
}

var circle_x = 100;
var circle_speed = 250;

// https://github.com/toslunar/UTyping/blob/1b2eff072bda776ae4d7091f39d0c440f45d2727/UTyping.cpp#L2768
fn getDrawPosX(time_diff: f64) f32 {
    //return X_CIRCLE + (int)(-timeDiff * (CIRCLE_SPEED * m_challenge.speed()));
    return @floatCast(f32, circle_x + (-time_diff * (circle_speed * 1.0)));
}

// https://github.com/toslunar/UTyping/blob/1b2eff072bda776ae4d7091f39d0c440f45d2727/UTyping.cpp#L2773
fn getDrawPosY(x: f32) f32 {
    x -= circle_x;
    var y: f32 = 0;
    // if(m_challenge.test(CHALLENGE_SIN)){
    // 	y += sin(x / SCALE_FUNCTION) * SCALE_FUNCTION;
    // }
    // if(m_challenge.test(CHALLENGE_COS)){
    // 	y += cos(x / SCALE_FUNCTION) * SCALE_FUNCTION;
    // }
    // if(m_challenge.test(CHALLENGE_TAN)){
    // 	y += tan(x / SCALE_FUNCTION) * SCALE_FUNCTION;
    // }
    return -y; // スクリーン座標は上下が逆
}

pub fn renderScreen(self: *Screen, render_state: RenderState) void {
    var data = self.getData(SongSelectData);

    render_state.fontstash.renderer.begin() catch @panic("Cant begin font renderer");
    render_state.fontstash.reset();

    var time: f64 = 0;
    _ = time;

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

    for (0..fumen.beat_lines.len) |i| {
        _ = i;
    }

    render_state.fontstash.renderer.end() catch @panic("Cant end font renderer");

    render_state.fontstash.renderer.draw(render_state.render_pass_encoder) catch @panic("Cant draw....");
}
