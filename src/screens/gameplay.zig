const std = @import("std");
const bass = @import("bass");
const builtin = @import("builtin");

const c = @import("../main.zig").c;

const Screen = @import("../screen.zig");
const Gfx = @import("../gfx.zig");
const Fumen = @import("../fumen.zig");
const Music = @import("../music.zig");
const Convert = @import("../convert.zig");

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

const Score = struct {
    ///The score gotten from accuracy
    accuracy_score: u64 = 0,
    ///The score gotten from typing
    typing_score: u64 = 0,
    ///The current combo the user has
    combo: u64 = 0,
    ///The highest combo the user has reached
    max_combo: u64 = 0,
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

    ///Get the actively playing music
    music: *Music,

    ///The current note the user is on
    active_note: usize = 0,

    ///The hiragana the user typed so far of the current note
    typed_hiragana: []const u8 = &.{},

    ///The romaji the user has typed so far for the current hiragana
    typed_romaji: []const u8 = &.{},

    score: Score = .{},
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

pub fn initScreen(self: *Screen, allocator: std.mem.Allocator, gfx: Gfx) anyerror!void {
    _ = gfx;
    self.allocator = allocator;

    var data = allocator.create(GameplayData) catch @panic("OOM");

    data.* = .{
        .music = &self.state.current_map.?,
    };

    //Reset the hit status for all the lyrics before the game starts
    for (data.music.fumen.lyrics) |*lyric| {
        lyric.resetHitStatus();
    }

    self.data = data;

    //Open the dir of the fumen folder
    var dir = try std.fs.openDirAbsolute(data.music.fumen.fumen_folder, .{});
    defer dir.close();
    //Get the real path of the audio file
    var full_audio_path = dir.realpathAlloc(allocator, data.music.fumen.audio_path) catch @panic(":(");
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

///The window to get an Excellent, in seconds in both directions
pub const excellent_window = 0.02;
///The window to get a Good, in seconds in both directions
pub const good_window = 0.05;
///The window to get a Fair, in seconds in both directions
pub const fair_window = 0.10;
///The window to get a Poor, in seconds in both directions
pub const poor_window = 0.20;

///The string to display for an excellent hit
pub const excellent_str = "優";
///The string to display for a good hit
pub const good_str = "良";
///The string to display for a fair hit
pub const fair_str = "可";
///The string to display for a poor hit
pub const poor_str = "不可";

///The color to display for an excellent hit
pub const excellent_color: Gfx.ColorF = .{ 1, 1, 0, 0 };
///The color to display for a good hit
pub const good_color: Gfx.ColorF = .{ 0, 1, 0, 0 };
///The color to display for a fair hit
pub const fair_color: Gfx.ColorF = .{ 0, 0.5, 1, 0 };
///The color to display for a poor hit
pub const poor_color: Gfx.ColorF = .{ 0.5, 0.5, 0.5, 0 };

///The score for an excellent hit
pub const excellent_score = 1500;
///The score for a good hit
pub const good_score = 1000;
///The score for a fair hit
pub const fair_score = 500;
///The score for a poor hit
pub const poor_score = 0;

pub const combo_score = 10;
pub const combo_score_max = 1000;

pub const typing_score = 500;

pub fn char(self: *Screen, typed_char: []const u8) anyerror!void {
    var data = self.getData(GameplayData);

    //If we're not in the main phase, ignore the input
    if (data.phase != .main) {
        return;
    }

    // std.debug.print("user wrote {s}\n", .{typed_char});

    var current_time = try self.state.audio_tracker.music.?.getSecondPosition();

    var current_note: *Fumen.Lyric = &data.music.fumen.lyrics[data.active_note];
    var next_note: ?*Fumen.Lyric = if (data.active_note + 1 == data.music.fumen.lyrics.len) null else &data.music.fumen.lyrics[data.active_note + 1];

    var hiragana_to_type = current_note.text[data.typed_hiragana.len..];
    var hiragana_to_type_next: ?[:0]const u8 = if (next_note != null) next_note.?.text else &.{};

    const Match = struct {
        //The matched conversion
        conversion: Convert.Conversion,
        //The romaji to type
        romaji_to_type: []const u8,
    };

    //The found match for the current note
    var matched: ?Match = null;
    //The found match for the next hiragana (only for the current note, check matched_next for the next note)
    var next_hiragana_matched: ?Match = null;
    //The found match for the next note
    var matched_next: ?Match = null;

    _ = next_hiragana_matched;

    //Iterate over all conversions,
    for (self.state.convert.conversions) |conversion| {
        const hiragana_matches = std.mem.startsWith(u8, hiragana_to_type, conversion.hiragana);
        const hiragana_matches_next: ?bool = if (hiragana_to_type_next != null) std.mem.startsWith(u8, hiragana_to_type_next.?, conversion.hiragana) else null;

        //If we have found a match for the current and next note,
        if (matched != null and matched_next != null) {
            //Break out
            break;
        }

        //If the text we need to type starts with the conversion we are testing, and we havent found a match already
        if (hiragana_matches and matched == null) {
            //If the conversion starts with the romaji we have already typed,
            if (std.mem.startsWith(u8, conversion.romaji, data.typed_romaji)) {
                //Get the romaji we have left to type
                var romaji_to_type = conversion.romaji[data.typed_romaji.len..];

                //If the romaji we need to type starts with the characters the user has just typed
                if (std.mem.startsWith(u8, romaji_to_type, typed_char)) {
                    matched = .{
                        .conversion = conversion,
                        .romaji_to_type = romaji_to_type,
                    };
                }
            }
        }

        //If the text we need to type for the next note starts with the conversion we are testing, and we havent found a valid match for the next note
        if (hiragana_matches_next != null and hiragana_matches_next.? and matched_next == null) {
            //And if the conversion's romaji starts with the characters the user has just typed
            if (std.mem.startsWith(u8, conversion.romaji, typed_char)) {
                matched_next = .{
                    .conversion = conversion,
                    .romaji_to_type = conversion.romaji,
                };
            }
        }
    }

    //If we have matched the current note
    if (matched) |matched_for_current_note| {
        _ = matched_for_current_note;

        //Iterate over all conversions,
        for (self.state.convert.conversions) |conversion| {
            _ = conversion;
        }
    }

    var current_note_finished: bool = false;
    var current_hiragana_finished: bool = false;
    var end_cut_hit: bool = false;
    if (matched) |matched_for_current_note| {
        if (current_note.pending_hit_result == null) {
            //Get the offset the user hit the note at, used to determine the hit result of the note
            var delta = current_time - current_note.time;

            //Get the hit result, using the absolute value
            var hit_result = deltaToHitResult(@fabs(delta));

            //If the user is past the note, and they are too far away, mark it as poor
            //This allows them to hit notes at any point *after*
            if (hit_result == null and delta > 0) {
                hit_result = .poor;
            }

            //If it is a valid hit,
            if (hit_result) |valid_hit_result| {
                //Set the pending hit result to the valid hit result
                current_note.pending_hit_result = valid_hit_result;

                handleNoteFirstChar(data, current_note);
            }
        }

        //If there is a hit result set for the note, then we can add the characters they typed
        if (current_note.pending_hit_result != null) {
            //Add the typed romaji
            data.typed_romaji = matched_for_current_note.conversion.romaji[0 .. data.typed_romaji.len + typed_char.len];

            try handleTypedRomaji(data, typed_char);

            // std.debug.print("adding romaji, now {s}/{s}\n", .{ data.typed_romaji, matched_for_current_note.conversion.romaji });

            if (data.typed_romaji.len == matched_for_current_note.conversion.romaji.len) {
                //If the user has typed all the romaji for the current note, then we need to append the hiragana
                data.typed_hiragana = current_note.text[0 .. data.typed_hiragana.len + matched_for_current_note.conversion.hiragana.len];

                // std.debug.print("finished hiragana {s}/{s}\n", .{ data.typed_hiragana, current_note.text });

                //Clear the typed romaji
                data.typed_romaji = &.{};

                //Mark that we finished the current hiragana
                current_hiragana_finished = true;

                //If the user has typed all the hiragana for the current note, then we need to move to the next note
                if (data.typed_hiragana.len == current_note.text.len) {
                    // std.debug.print("finished note {s}\n", .{current_note.text});

                    //Hit the current note
                    hitNote(data);

                    //Clear the typed hiragana
                    data.typed_hiragana = &.{};

                    //Mark that we finished the current note
                    current_note_finished = true;
                }
            }

            //If the current match has an end cut
            if (matched_for_current_note.conversion.end_cut) |end_cut| {
                //And the user has typed that end cut
                if (std.mem.eql(u8, typed_char, end_cut)) {
                    end_cut_hit = true;
                }
            }

            //If we have hit the end cut, then we want to continue out, so if we have not,
            if (!end_cut_hit) {
                //Return out, so we dont trigger the "next" match
                return;
            }
        }
    }

    //If we hit the end cut, and we have finished the current hiragana, and we have not finished the current note
    if (end_cut_hit and current_hiragana_finished and !current_note_finished) {
        hiragana_to_type = current_note.text[data.typed_hiragana.len..];

        for (self.state.convert.conversions) |conversion| {
            if (std.mem.startsWith(u8, hiragana_to_type, conversion.hiragana)) {
                //Add the typed characters to the typed romaji
                data.typed_romaji = conversion.romaji[0..typed_char.len];

                try handleTypedRomaji(data, typed_char);

                // std.debug.print("adding romaji for next note on end cut, now {s}/{s}\n", .{ data.typed_romaji, conversion.romaji });

                //If the typed romaji is the same as the romaji for the conversion
                if (std.mem.eql(u8, data.typed_romaji, conversion.romaji)) {
                    //Clear the typed romaji
                    data.typed_romaji = &.{};

                    //Add the typed hiragana
                    data.typed_hiragana = current_note.text[0 .. data.typed_hiragana.len + conversion.hiragana.len];

                    // std.debug.print("adding hiragana for next note on end cut, now {s}/{s}\n", .{ data.typed_hiragana, current_note.text });

                    //If the user has typed all the hiragana for the current note, then we need to move to the next note
                    if (data.typed_hiragana.len == current_note.text.len) {
                        // std.debug.print("finished note {s}\n", .{current_note.text});

                        //Hit the current note
                        hitNote(data);

                        //Clear the typed hiragana
                        data.typed_hiragana = &.{};

                        //Mark that we finished the current note
                        current_note_finished = true;
                    }
                }

                //Return out so the matched_next logic doesnt get triggered
                return;
            }
        }
    }

    if (matched_next) |matched_for_next_note| {
        //Get the offset the user hit the note at, used to determine the hit result of the note
        var delta = current_time - next_note.?.time;

        //Get the hit result, using the absolute value
        var hit_result = deltaToHitResult(@fabs(delta));

        // std.debug.print("next \"{s}\"/{d}/{any}\n", .{ matched_for_next_note.conversion.romaji, delta, hit_result });

        //If it is a valid hit,
        if (hit_result) |valid_hit_result| {
            //If the end cut is not hit, then we need to mark the previous note as hit, not doing this will cause the next note to be marked as missed, because the current note has been completed
            if (!end_cut_hit) {
                //Miss the current note
                missNote(data);
            }

            //Set the pending hit result to the valid hit result
            next_note.?.pending_hit_result = valid_hit_result;

            handleNoteFirstChar(data, next_note.?);

            //Set the typed romaji to the characters they typed
            data.typed_romaji = matched_for_next_note.conversion.romaji[0..typed_char.len];

            // std.debug.print("adding next romaji, now {s}/{s}\n", .{ data.typed_romaji, matched_for_next_note.conversion.romaji });

            if (data.typed_romaji.len == matched_for_next_note.conversion.romaji.len) {
                //If the user has typed all the romaji for the current note, then we need to append the hiragana
                data.typed_hiragana = next_note.?.text[0 .. data.typed_hiragana.len + matched_for_next_note.conversion.hiragana.len];

                //Clear the typed romaji
                data.typed_romaji = &.{};

                // std.debug.print("finished next hiragana {s}/{s}\n", .{ data.typed_hiragana, next_note.?.text });

                //If the user has typed all the hiragana for the current note, then we need to move to the next note
                if (data.typed_hiragana.len == next_note.?.text.len) {
                    // std.debug.print("finished next note {s}\n", .{next_note.?.text});

                    //Hit the current note
                    hitNote(data);

                    //Clear the typed hiragana
                    data.typed_hiragana = &.{};
                }
            }
        }
    }

    // if (matched) |matched_match| {
    //     std.debug.print("found match {s}\n", .{matched_match.conversion.romaji});
    // }

    // if (matched_next) |matched_match| {
    //     std.debug.print("found match_next {s}\n", .{matched_match.conversion.romaji});
    // }
}

fn handleTypedRomaji(data: *GameplayData, typed: []const u8) !void {
    data.score.typing_score += typing_score * try std.unicode.utf8CountCodepoints(typed);
}

fn handleNoteFirstChar(data: *GameplayData, note: *Fumen.Lyric) void {
    //Get the extra score from having a combo, capped to the `combo_score_max` value
    var score_combo = @min(combo_score * data.score.combo, combo_score_max);

    //Add the accuracy the user has reached to the accuracy score, ignore bonus score with a `poor` hit
    data.score.accuracy_score += (if (note.pending_hit_result.? == .poor) 0 else score_combo) + hitResultToAccuracyScore(note.pending_hit_result.?);

    //TODO: set combo/accuracy strings

    //Increment the combo
    data.score.combo += 1;

    //Reset the combo if its a poor hit
    if (note.pending_hit_result.? == .poor) {
        data.score.combo = 0;
    }

    //If the user has reached a higher max combo
    if (data.score.combo > data.score.max_combo) {
        data.score.max_combo = data.score.combo;
    }
}

fn hitNote(data: *GameplayData) void {
    //Get the current note
    const current_note = &data.music.fumen.lyrics[data.active_note];

    //Assert that the note has a pending hit result
    std.debug.assert(current_note.pending_hit_result != null);

    //Set the hit result to the pending hit result
    current_note.hit_result = current_note.pending_hit_result.?;

    //Mark that we are on the next note
    data.active_note += 1;

    if (data.active_note == data.music.fumen.lyrics.len) {
        data.phase = .finished;
        std.debug.print("note hit, game finished\n", .{});
    }
}

///Returns the expected hit result for the delta
fn deltaToHitResult(delta: f64) ?Fumen.Lyric.HitResult {
    if (delta < excellent_window) {
        return .excellent;
    } else if (delta < good_window) {
        return .good;
    } else if (delta < fair_window) {
        return .fair;
    } else if (delta < poor_window) {
        return .poor;
    }

    return null;
}

fn hitResultToAccuracyScore(hit_result: Fumen.Lyric.HitResult) u64 {
    return switch (hit_result) {
        .excellent => excellent_score,
        .good => good_score,
        .fair => fair_score,
        .poor => poor_score,
    };
}

pub fn keyDown(self: *Screen, key: c.SDL_Keysym) anyerror!void {
    var data = self.getData(GameplayData);

    switch (key.sym) {
        c.SDLK_ESCAPE => {
            self.close_screen = true;
        },
        c.SDLK_BACKSLASH => {
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

pub fn renderScreen(self: *Screen, render_state: RenderState) anyerror!void {
    var data = self.getData(GameplayData);

    data.current_time = try self.state.audio_tracker.music.?.getSecondPosition();

    //In debug mode, allow the user to scrub through the song
    if (builtin.mode == .Debug) {
        data.scrub_frame_counter += 1;

        if (data.scrub_frame_counter > 20) {
            var mouse_x_i: c_int = 0;
            var mouse_y: c_int = 0;
            var mouse_buttons = c.SDL_GetMouseState(&mouse_x_i, &mouse_y);
            var mouse_x = @floatFromInt(f32, mouse_x_i);

            var max_x = render_state.gfx.scale * 640.0;

            if (mouse_x < 0) {
                mouse_x = 0;
            }

            if (mouse_x > max_x) {
                mouse_x = max_x;
            }

            if ((mouse_buttons & c.SDL_BUTTON(3)) != 0 and mouse_x != data.last_mouse_x) {
                var byte = @intFromFloat(u64, @floatFromInt(f64, try self.state.audio_tracker.music.?.getLength(.byte)) * (mouse_x / max_x));

                try self.state.audio_tracker.music.?.setPosition(byte, .byte, .{});
            }

            data.last_mouse_x = mouse_x;

            data.scrub_frame_counter = 0;
        }
    }

    checkForMissedNotes(data);

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

    try drawGameplayLyrics(render_state, data);

    drawKanjiLyrics(render_state, data);

    drawScoreUi(render_state, data);

    try render_state.renderer.end();
    try render_state.renderer.draw(render_state.render_pass_encoder);

    try render_state.fontstash.renderer.end();

    try render_state.fontstash.renderer.draw(render_state.render_pass_encoder);

    if (builtin.mode == .Debug) {
        var open = false;
        _ = c.igBegin("Gameplay Debugger", &open, 0);

        c.igText("Gameplay State");

        inline for (@typeInfo(GameplayData).Struct.fields) |field| {
            handleDebugType(data, field.name, field.type, {});
        }

        c.igSeparator();

        c.igText("Score");

        inline for (@typeInfo(Score).Struct.fields) |field| {
            handleDebugType(data.score, field.name, field.type, {});
        }

        c.igEnd();
    }
}

fn handleDebugType(data: anytype, comptime name: []const u8, comptime T: type, contents: anytype) void {
    const actual_contents = if (@TypeOf(contents) == void) @field(data, name) else contents;

    switch (@typeInfo(T)) {
        .Int => {
            c.igText(name ++ ": %d", actual_contents);
        },
        .Float => {
            c.igText(name ++ ": %f", actual_contents);
        },
        .Enum => {
            c.igText(name ++ ": %s", @tagName(actual_contents).ptr);
        },
        .Pointer => |ptr| {
            //We dont handle printing non-slices, so just break out
            if (ptr.size != .Slice) return;

            switch (ptr.child) {
                u8 => {
                    //We can just use normal %s for sentinel terminated arrays
                    if (ptr.sentinel != null) {
                        c.igText(name ++ ": \"%s\"", actual_contents.ptr);
                    }
                    //Else we have to use the `%.*s` magic
                    else {
                        c.igText(name ++ ": \"%.*s\"", actual_contents.len, actual_contents.ptr);
                    }
                },
                else => {},
            }
        },
        .Optional => |optional| {
            const content = @field(data, name);

            if (content == null) {
                c.igText(name ++ ": null");
            } else {
                handleDebugType(data, name, optional.child, content.?);
            }
        },
        else => {},
    }
}

///Causes the game to process a full miss on the current note
fn missNote(data: *GameplayData) void {
    //Set the pending hit result to null, and mark the hit as "poor" since they missed
    data.music.fumen.lyrics[data.active_note].pending_hit_result = null;
    data.music.fumen.lyrics[data.active_note].hit_result = .poor;

    //Clear out the typed flags, to prepare for the next note
    data.typed_hiragana = &.{};
    data.typed_romaji = &.{};

    //Mark that we are on the next note now
    data.active_note += 1;

    //Reset the combo
    data.score.combo = 0;

    //If we are on the last note, mark the game as finished
    if (data.music.fumen.lyrics.len == data.active_note) {
        data.phase = .finished;
        std.debug.print("note missed, game finished\n", .{});
    }
}

fn checkForMissedNotes(data: *GameplayData) void {
    if (data.phase != .main) {
        return;
    }

    //The current note the user is playing
    var current_note = data.music.fumen.lyrics[data.active_note];
    //The next note the user *could* hit
    var next_note: ?Fumen.Lyric = if (data.active_note < data.music.fumen.lyrics.len - 1) data.music.fumen.lyrics[data.active_note + 1] else null;
    _ = current_note;

    //If the user should miss the current note
    if (missCheck(data, next_note)) {
        return missNote(data);
    }
}

///Whether the user is in a state to miss the current note
fn missCheck(data: *GameplayData, next_note: ?Fumen.Lyric) bool {
    //TODO: take into account typing cutoffs

    if (next_note) |next| {
        //If the user is past the next note, then return that they should miss it
        if (next.time < data.current_time) {
            return true;
        }
    }

    return false;
}

fn drawScoreUi(render_state: Screen.RenderState, data: *GameplayData) void {
    //Draw the score
    render_state.fontstash.setMincho();
    render_state.fontstash.setSizePt(36);
    render_state.fontstash.setAlign(.right);
    render_state.fontstash.setColor(.{ 255, 255, 255, 255 });

    var buf: [8:0]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 0 };
    _ = std.fmt.formatIntBuf(
        &buf,
        data.score.accuracy_score + data.score.typing_score,
        10,
        .upper,
        .{ .width = 8, .fill = '0' },
    );
    render_state.fontstash.drawText(.{ x_score, y_score - render_state.fontstash.verticalMetrics().line_height }, &buf);
}

fn drawGameplayLyrics(render_state: Screen.RenderState, data: *GameplayData) !void {
    //Draw all the beat lines
    for (0..data.music.fumen.beat_lines.len) |i| {
        var beat_line = data.music.fumen.beat_lines[i];

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
    for (0..data.music.fumen.lyric_cutoffs) |j| {
        var i = data.music.fumen.lyric_cutoffs.len - 1 - j;

        var lyric_cutoff = data.music.fumen.lyric_cutoffs[i];
        var time_diff = data.current_time - lyric_cutoff.time;

        var posX = getDrawPosX(time_diff);
        var posY = getDrawPosY(posX);

        if (posX < 0 - circle_r) break;
        if (posX > 640 + circle_r) continue;

        //Draw the note circle itself
        try render_state.renderer.reserveTexQuadPxSize("typing_cutoff", .{ posX - circle_r, posY + circle_y - circle_r }, .{ circle_r * 2, circle_r * 2 }, Gfx.WhiteF);
    }

    //Draw all the lyrics
    for (0..data.music.fumen.lyrics.len) |j| {
        var i = data.music.fumen.lyrics.len - 1 - j;

        var lyric = data.music.fumen.lyrics[i];
        var time_diff = data.current_time - lyric.time;

        var posX = getDrawPosX(time_diff);
        var posY = getDrawPosY(posX);

        if (posX < 0 - circle_r) break;
        if (posX > 640 + circle_r) continue;

        const note_color = if (lyric.hit_result != null) switch (lyric.hit_result.?) {
            .poor => Gfx.ColorF{ 0.3, 0.3, 0.3, 0.3 },
            else => Gfx.BlueF,
        } else Gfx.RedF;
        // const note_color = if (lyric.hit_result != null and lyric.hit_result.? == .poor) Gfx.ColorF{ 0.3, 0.3, 0.3, 0.3 } else Gfx.RedF;

        //Draw the note circle itself
        try render_state.renderer.reserveTexQuadPxSize(
            "note",
            .{ posX - circle_r, posY + circle_y - circle_r },
            .{ circle_r * 2, circle_r * 2 },
            note_color,
        );

        //If we are in debug mode,
        if (builtin.mode == .Debug) {
            //And this is the active note,
            if (i == data.active_note) {
                //Render a small marker, to mark the note the game thinks the user is playing
                try render_state.renderer.reserveTexQuadPxSize(
                    "note",
                    .{ posX - circle_r / 2, posY + circle_y - circle_r * 2 },
                    .{ circle_r, circle_r },
                    Gfx.BlueF,
                );
            }

            //And this is the note after the active note, along with the user being after the current note *in time*
            if (i == data.active_note + 1 and data.music.fumen.lyrics[data.active_note].time < data.current_time) {
                //Render a small marker, to mark the note the user *could* switch to hitting
                try render_state.renderer.reserveTexQuadPxSize(
                    "note",
                    .{ posX - circle_r / 2, posY + circle_y - circle_r * 2 },
                    .{ circle_r, circle_r },
                    Gfx.GreenF,
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

fn drawKanjiLyrics(render_state: Screen.RenderState, data: *GameplayData) void {
    //If there are no kanji lyrics, return out
    if (data.music.fumen.lyrics_kanji.len == 0) {
        return;
    }

    const next_string = "Next: ";

    render_state.fontstash.setAlign(.right);
    render_state.fontstash.setGothic();
    render_state.fontstash.setSizePt(16);

    render_state.fontstash.drawText(.{ lyrics_kanji_x, lyrics_kanji_next_y }, next_string);

    render_state.fontstash.setAlign(.left);

    //Move the current lyric forward by 1, if applicable
    while (data.current_lyric_kanji != null and data.music.fumen.lyrics_kanji[data.current_lyric_kanji.?].time_end < data.current_time) {
        if (data.current_lyric_kanji.? != data.music.fumen.lyrics_kanji.len - 1) {
            data.current_lyric_kanji.? += 1;
        } else {
            break;
        }
    }

    //If we havent reached a lyric yet, check if we have reached it
    if (data.current_lyric_kanji == null and data.music.fumen.lyrics_kanji[0].time < data.current_time) {
        data.current_lyric_kanji = 0;
    }

    //If the current lyric has started,
    if (data.current_lyric_kanji != null and data.music.fumen.lyrics_kanji[data.current_lyric_kanji.?].time < data.current_time) {
        //Draw the lyric
        data.music.fumen.lyrics_kanji[data.current_lyric_kanji.?].draw(lyrics_kanji_x, lyrics_kanji_y, render_state);
    }

    //If we are not at the last lyric
    if (data.current_lyric_kanji != null and data.current_lyric_kanji.? < data.music.fumen.lyrics_kanji.len - 1) {
        const next_lyric_kanji = data.music.fumen.lyrics_kanji[data.current_lyric_kanji.? + 1];

        //Draw the next lyirc
        next_lyric_kanji.draw(lyrics_kanji_x, lyrics_kanji_next_y, render_state);
    }
    //If we have not reached a lyric yet
    else if (data.current_lyric_kanji == null) {
        const next_lyric_kanji = data.music.fumen.lyrics_kanji[0];

        //Draw the next lyirc
        next_lyric_kanji.draw(lyrics_kanji_x, lyrics_kanji_next_y, render_state);
    }
}
