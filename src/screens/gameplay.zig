const std = @import("std");
const bass = @import("bass");
const builtin = @import("builtin");

const c = @import("../main.zig").c;

const Screen = @import("../screen.zig");
const Gfx = @import("../gfx.zig");
const Fumen = @import("../fumen.zig");
const Music = @import("../music.zig");
const Convert = @import("../convert.zig");
const Fontstash = @import("../fontstash.zig");

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

    animation_timers: AnimationTimers,

    gauge_data: GaugeData,

    ///The interpolated score to draw on the screen
    draw_score: f64 = 0,

    //things Actually Relavent to the gameplay

    ///Get the actively playing music
    music: *Music,

    ///The current note the user is on
    active_note: usize = 0,

    ///The hiragana the user typed so far of the current note
    typed_hiragana: []const u8 = &.{},

    ///The romaji the user has typed so far for the current hiragana
    typed_romaji: []const u8 = &.{},

    ///Info about the score the user has achieved
    score: Score = .{},

    ///The accuracy text to display (eg. 優)
    accuracy_text: [:0]const u8 = "",
    ///The color of the accuracy text
    accuracy_text_color: Gfx.ColorF = .{ 1, 1, 1, 1 },
};

const GaugeData = struct {
    //Gauge

    gauge: isize,
    gauge_max: isize,
    gauge_last_count: isize,
    gauge_new_count: isize,
    gauge_last_lost: isize,

    excellent_count: usize = 0,
    good_count: usize = 0,
    fair_count: usize = 0,
    poor_count: usize = 0,
    clear_count: usize = 0,

    note_count: usize,

    //Stat gauge

    //The real length of the gauge
    lengths: [4]f64,
    //The width its currently being drawn at
    draw_x: [4]f64,
    //Velocity of the currently drawn length of the gauge
    draw_v: [4]f64,
    //Length on screen equivalent to length 1
    rate: f64,
    //Intensity of the light illuminating each gauge
    lights: [4]f64,
    colours: [4][2]Gfx.ColorF,

    const GaugeZone = enum {
        failed,
        red,
        yellow,
        blue,
        clear,
    };

    pub fn statIncrement(self: *GaugeData, hit_result: Fumen.Lyric.HitResult) void {
        //Increment the lengths
        self.lengths[@intFromEnum(hit_result)] += 1;
        //Set the light to 1
        self.lights[@intFromEnum(hit_result)] = 1;
    }

    pub fn updateGauge(self: *GaugeData, data: *GameplayData) void {
        const count = data.active_note;

        if (count > self.gauge_last_count) {
            var lost: isize = @intCast(count - self.clear_count);
            var t = lost - self.gauge_last_lost;
            self.gauge_last_lost = lost;
            while (t > 0) : (t -= 1) {
                switch (self.getGaugeZone()) {
                    .red => self.gauge -= 50,
                    .yellow => self.gauge -= 100,
                    .blue => self.gauge -= @intCast(100 + (self.note_count / 2)),
                    .clear => self.gauge -= @intCast(100 + self.note_count),
                    else => {},
                }
            }

            t = @as(isize, @intCast(count)) - self.gauge_last_count;
            self.gauge_last_count = @intCast(count);

            t -= self.gauge_new_count;
            if (t < 0) {
                self.gauge_new_count = -t;
            } else {
                while (t > 0) : (t -= 1) {
                    switch (self.getGaugeZone()) {
                        .red => self.gauge -= 100,
                        .yellow => self.gauge -= 150,
                        .blue => self.gauge -= 200,
                        .clear => self.gauge -= @intCast(200 + self.note_count),
                        else => {},
                    }
                }
                self.gauge_new_count = 0;
            }
        }

        if (self.gauge <= 0) {
            self.gauge = 0;

            //TODO: fail, if failing is enabled
        }
    }

    pub fn gaugeIncrement(self: *GaugeData, hit_result: Fumen.Lyric.HitResult) void {
        const gauge_zone = self.getGaugeZone();
        switch (hit_result) {
            .excellent => {
                switch (gauge_zone) {
                    .red => self.gauge += 200,
                    .yellow => self.gauge += 200,
                    .blue => self.gauge += 150,
                    .clear => self.gauge += 100,
                    else => {},
                }
            },
            .good => {
                switch (gauge_zone) {
                    .red => self.gauge += 100,
                    .yellow => self.gauge += 100,
                    .blue => self.gauge += 75,
                    .clear => self.gauge += 50,
                    else => {},
                }
            },
            .fair => {},
            .poor => {
                switch (gauge_zone) {
                    .red => self.gauge -= 50,
                    .yellow => self.gauge -= 100,
                    .blue => self.gauge -= 150,
                    .clear => self.gauge -= @intCast(150 + self.note_count),
                    else => {},
                }
            },
        }
        self.gauge_new_count += 1;
        self.gauge = @min(self.gauge, self.gauge_max);
        self.clear_count += 1;

        if (self.gauge <= 0) {
            self.gauge = 0;

            //TODO: fail, if failing is enabled
        }
    }

    fn getGaugeZone(self: *GaugeData) GaugeZone {
        if (self.gauge == 0) {
            return .failed;
        } else if (self.gauge <= self.note_count * gauge_red_zone) {
            return .red;
        } else if (self.gauge <= self.note_count * gauge_yellow_zone) {
            return .yellow;
        } else if (self.gauge <= self.note_count * gauge_clear_zone) {
            return .blue;
        } else {
            return .clear;
        }
    }

    pub fn init(note_count: usize) GaugeData {
        return .{
            //Gauge
            .gauge = @intCast(note_count * 25),
            .gauge_max = @intCast(note_count * gauge_count),
            .gauge_last_count = 0,
            .gauge_new_count = 0,
            .gauge_last_lost = 0,

            .note_count = note_count,

            //Stat gauge
            .lengths = [4]f64{ 0, 0, 0, 0 },
            .draw_x = [4]f64{ 0, 0, 0, 0 },
            .draw_v = [4]f64{ 0, 0, 0, 0 },
            .lights = [4]f64{ 0, 0, 0, 0 },
            .rate = 20,
            .colours = [4][2]Gfx.ColorF{
                [2]Gfx.ColorF{ excellent_color, excellent_color_2 },
                [2]Gfx.ColorF{ good_color, good_color_2 },
                [2]Gfx.ColorF{ fair_color, fair_color_2 },
                [2]Gfx.ColorF{ poor_color, poor_color_2 },
            },
        };
    }
};

const AnimationTimers = struct {
    accuracy_text: std.time.Timer,
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

    var data = try allocator.create(GameplayData);
    errdefer allocator.destroy(data);

    data.* = .{
        .music = &self.state.current_map.?,
        .animation_timers = .{
            .accuracy_text = try std.time.Timer.start(),
        },
        .gauge_data = GaugeData.init(self.state.current_map.?.fumen.lyrics.len),
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
    var full_audio_path = try dir.realpathAlloc(allocator, data.music.fumen.audio_path);
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
pub const excellent_color: Gfx.ColorF = .{ 1, 1, 0, 1 };
///The color to display for a good hit
pub const good_color: Gfx.ColorF = .{ 0, 1, 0, 1 };
///The color to display for a fair hit
pub const fair_color: Gfx.ColorF = .{ 0, 0.5, 1, 1 };
///The color to display for a poor hit
pub const poor_color: Gfx.ColorF = .{ 0.5, 0.5, 0.5, 1 };

pub const excellent_color_2: Gfx.ColorF = .{ 1, 1, 0.5, 1 };
pub const good_color_2: Gfx.ColorF = .{ 0.5, 1, 0.5, 1 };
pub const fair_color_2: Gfx.ColorF = .{ 0.5, 0.75, 1, 1 };
pub const poor_color_2: Gfx.ColorF = .{ 0.75, 0.75, 0.75, 1 };

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

    //Defer updateGauge to happen at the end of scope
    defer data.gauge_data.updateGauge(data);

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
}

fn handleTypedRomaji(data: *GameplayData, typed: []const u8) !void {
    data.score.typing_score += typing_score * try std.unicode.utf8CountCodepoints(typed);
}

fn handleNoteFirstChar(data: *GameplayData, note: *Fumen.Lyric) void {
    //Get the extra score from having a combo, capped to the `combo_score_max` value
    var score_combo = @min(combo_score * data.score.combo, combo_score_max);

    //Add the accuracy the user has reached to the accuracy score, ignore bonus score with a `poor` hit
    data.score.accuracy_score += (if (note.pending_hit_result.? == .poor) 0 else score_combo) + hitResultToAccuracyScore(note.pending_hit_result.?);

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

    data.accuracy_text = switch (note.pending_hit_result.?) {
        .excellent => excellent_str,
        .good => good_str,
        .fair => fair_str,
        .poor => poor_str,
    };

    data.accuracy_text_color = switch (note.pending_hit_result.?) {
        .excellent => excellent_color,
        .good => good_color,
        .fair => fair_color,
        .poor => poor_color,
    };

    switch (note.pending_hit_result.?) {
        .excellent => data.gauge_data.excellent_count += 1,
        .good => data.gauge_data.good_count += 1,
        .fair => data.gauge_data.fair_count += 1,
        .poor => data.gauge_data.poor_count += 1,
    }

    data.gauge_data.gaugeIncrement(note.pending_hit_result.?);
    data.gauge_data.statIncrement(note.pending_hit_result.?);

    //Reset the animation timer for accuracy_text
    data.animation_timers.accuracy_text.reset();
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
    return @floatCast(circle_x + (-time_diff * (circle_speed * 1.0)));
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
            var mouse_x: f32 = @floatFromInt(mouse_x_i);

            var max_x = render_state.gfx.scale * 640.0;

            if (mouse_x < 0) {
                mouse_x = 0;
            }

            if (mouse_x > max_x) {
                mouse_x = max_x;
            }

            if ((mouse_buttons & c.SDL_BUTTON(3)) != 0 and mouse_x != data.last_mouse_x) {
                var byte: u64 = @intFromFloat(@as(f64, @floatFromInt(try self.state.audio_tracker.music.?.getLength(.byte))) * (mouse_x / max_x));

                try self.state.audio_tracker.music.?.setPosition(byte, .byte, .{});
            }

            data.last_mouse_x = mouse_x;

            data.scrub_frame_counter = 0;
        }
    }

    checkForMissedNotes(data);

    try render_state.fontstash.renderer.begin();

    try render_state.renderer.begin();

    //If we are in the ready phase, render the "Press any key to start." text
    if (data.phase == .ready) {
        const state = .{
            .font = Fontstash.Mincho,
            .size = Fontstash.ptToPx(36),
            .color = Gfx.WhiteF,
            .alignment = .{
                .vertical = .baseline,
            },
        };

        _ = try render_state.fontstash.drawText(
            .{ 50, 370 - render_state.fontstash.verticalMetrics(state).line_height },
            "Press any key to start.",
            state,
        );
    }

    try drawGameplayLyrics(render_state, data);

    try drawKanjiLyrics(render_state, data);

    try drawGauge(render_state, data, false);

    try drawStatGauge(render_state, data);

    try drawScoreUi(render_state, data);

    try drawElapsedTime(render_state, data);

    try drawCurrentLyricText(render_state, data);

    const info_x = 160;
    const info_y = 10;

    const state: Fontstash.Fontstash.State = .{
        .font = Fontstash.Gothic,
        .size = Fontstash.ptToPx(16),
        .alignment = .{
            .vertical = .top,
            .horizontal = .right,
        },
    };

    var buf: [16]u8 = undefined;
    const written = std.fmt.formatIntBuf(&buf, data.score.max_combo, 10, .lower, .{});

    const spacing = 3;

    const size2 = try render_state.fontstash.textBounds(buf[0..written], state);
    const size3 = try render_state.fontstash.textBounds("コンボ", state);

    _ = try render_state.fontstash.drawText(.{ info_x + size2.x1 + size3.x1 - spacing * 2, info_y }, "最大", state);
    _ = try render_state.fontstash.drawText(.{ info_x + size3.x1 - spacing, info_y }, buf[0..written], state);
    _ = try render_state.fontstash.drawText(.{ info_x, info_y }, "コンボ", state);

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

        c.igSeparator();

        c.igText("Gauge Data");

        inline for (@typeInfo(GaugeData).Struct.fields) |field| {
            handleDebugType(data.gauge_data, field.name, field.type, {});
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

const big_lyric_x = circle_x - circle_r;
const big_lyirc_y = 350;

fn drawCurrentLyricText(render_state: RenderState, data: *GameplayData) !void {
    //Only draw the current lyric text during the main phase
    if (data.phase != .main) {
        return;
    }

    const current_note = data.music.fumen.lyrics[data.active_note];

    //If we are not within the typing window of the note, dont display its text
    if (current_note.time - poor_window > data.current_time) {
        return;
    }

    const state: Fontstash.Fontstash.State = .{
        .font = Fontstash.Mincho,
        .size = Fontstash.ptToPx(36),
        .alignment = .{
            .vertical = .top,
        },
    };

    //TODO: smoothly move the characters after they are typed, this is something UTyping does with CEffectStr
    //      so we should probably create a similar datatype to replicate that behaviour
    _ = try render_state.fontstash.drawText(.{ big_lyric_x, big_lyirc_y }, current_note.text[data.typed_hiragana.len..], state);

    //TODO: see above TODO
    _ = try render_state.fontstash.drawText(.{ big_lyric_x, big_lyirc_y + 40 }, data.typed_romaji, state);
}

const time_x = gauge_x;
const time_y = 445;
const time_width = gauge_width;
const time_height = 4;

const time_color: Gfx.ColorF = .{ 0.25, 0.75, 1, 1 };
const time_color_2: Gfx.ColorF = .{ 0.75, 0.75, 0.75, 1 };

fn drawElapsedTime(render_state: RenderState, data: *GameplayData) !void {
    const time = std.math.clamp(data.current_time / data.music.fumen.time_length, 0, 1);

    const pos: f32 = @floatCast(gauge_width * time);

    try render_state.renderer.reserveSolidBox(.{ time_x, time_y }, .{ pos, time_height }, time_color);
    try render_state.renderer.reserveSolidBox(.{ time_x + pos - 3, time_y }, .{ 6, time_height }, time_color_2);
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

    data.gauge_data.updateGauge(data);
}

fn checkForMissedNotes(data: *GameplayData) void {
    if (data.phase != .main) {
        return;
    }

    //The current note the user is playing
    var current_note = data.music.fumen.lyrics[data.active_note];
    //The next note the user *could* hit
    var next_note: ?Fumen.Lyric = if (data.active_note < data.music.fumen.lyrics.len - 1) data.music.fumen.lyrics[data.active_note + 1] else null;

    //If the user should miss the current note
    if (missCheck(data, current_note, next_note)) {
        return missNote(data);
    }
}

///Whether the user is in a state to miss the current note
fn missCheck(data: *GameplayData, current_note: Fumen.Lyric, next_note: ?Fumen.Lyric) bool {
    for (data.music.fumen.lyric_cutoffs) |cutoff| {
        //If the current note is after or equal to this cutoff,
        if (current_note.time >= cutoff.time) {
            //Skip it
            continue;
        }

        //If the current time is past this cutoff, and the note has no hit result, then miss
        if (data.current_time > cutoff.time) {
            return true;
        }
        //Else, we are not past the cutoff
        else {
            break;
        }
    }

    if (next_note) |next| {
        //If the user is past the next note, then return that they should miss it
        if (next.time < data.current_time) {
            return true;
        }
    }

    return false;
}

const gauge_x = 90;
const gauge_y = Screen.display_height - 25;
const gauge_width = gauge_segment_width * gauge_count;
const gauge_height = 10;
const gauge_segment_width = 5;
const gauge_width_padding = 4;
const gauge_height_padding = 2;

const gauge_count = 100;
const gauge_red_zone = 15;
const gauge_yellow_zone = 45;
const gauge_clear_zone = 75;

fn drawGauge(render_state: Screen.RenderState, data: *GameplayData, is_result: bool) !void {
    const y: f32 = if (is_result) 355 else gauge_y;

    const count = @divTrunc(data.gauge_data.gauge + @as(isize, @intCast(data.music.fumen.lyrics.len)) - 1, @as(isize, @intCast(data.music.fumen.lyrics.len)));

    //Render the background
    try render_state.renderer.reserveSolidBox(
        .{ gauge_x - gauge_width_padding, y - gauge_height_padding },
        .{ gauge_width + gauge_width_padding * 2, gauge_height + gauge_height_padding * 2 },
        .{ 0.0627, 0.0627, 0.0627, 0.5 },
    );

    for (0..gauge_count) |i| {
        const x: f32 = @floatFromInt(gauge_x + gauge_segment_width * i);

        const color = getGaugeColor(i, count);

        if (i < count) {
            var overflowing_color: Gfx.ColorF = color;
            overflowing_color[3] = color[3] * (3 / 16);

            try render_state.renderer.reserveSolidBox(
                .{ x + 1, y - 1 },
                .{ gauge_segment_width - 2, gauge_height + 1 },
                overflowing_color,
            );
        }

        try render_state.renderer.reserveSolidBox(
            .{ x + 1, y },
            .{ gauge_segment_width - 2, gauge_height },
            color,
        );
    }
}

fn getGaugeColor(pos: usize, count: isize) Gfx.ColorF {
    const alpha: f32 = if (pos >= count) 0.25 else 1;

    if (pos < gauge_red_zone) {
        return .{ 1, 0.125, 0, alpha };
    } else if (pos < gauge_yellow_zone) {
        return .{ 0.878, 1, 0, alpha };
    } else if (pos < gauge_clear_zone) {
        return .{ 0, 0.25, 1, alpha };
    } else {
        return .{ 1, 1, 1, alpha };
    }
}

const stat_gauge_x = Screen.display_width - 10;
const stat_gauge_y = 10;
const stat_gauge_width = 400;
const stat_gauge_height = 40;

fn drawStatGauge(render_state: Screen.RenderState, data: *GameplayData) !void {
    var y: f32 = stat_gauge_y;
    var single_bar_height: f32 = stat_gauge_height / 4;

    for (&data.gauge_data.draw_x, &data.gauge_data.draw_v, &data.gauge_data.lengths) |*x, *velocity, length| {
        //Add a little bit of velocity, depending on the amount we need to change
        velocity.* += 0.12 * (length - x.*) * render_state.game_state.delta_time * 60;
        x.* += velocity.*;
        //Slow the velocity down
        velocity.* *= 0.7 * render_state.game_state.delta_time * 60;
    }

    var rate: f32 = 20;
    while (true) {
        var flag = true;

        for (data.gauge_data.lengths) |length| {
            if (length * rate > stat_gauge_width) {
                flag = false;
                break;
            }
        }

        if (flag) {
            break;
        }

        //Slow the rate down a bit, until it does not exceed the width of the gauge
        rate *= 0.75;
    }
    data.gauge_data.rate += (rate - data.gauge_data.rate) * 0.2;

    //Render a solid box around the stat gauge
    try render_state.renderer.reserveSolidBox(.{ stat_gauge_x - stat_gauge_width, y }, .{ stat_gauge_width, stat_gauge_height }, .{ 0.25, 0.25, 0.25, 0.5 });

    for (data.gauge_data.draw_x, data.gauge_data.colours, 0..) |x, colour, i| {
        try drawBar(render_state, @floatCast(x * data.gauge_data.rate), y + @as(f32, @floatFromInt(i)) * single_bar_height, single_bar_height, colour[0]);
    }

    for (&data.gauge_data.lights, &data.gauge_data.colours, 0..) |*light, colour, i| {
        try drawLight(render_state, @floatCast(light.*), y + @as(f32, @floatFromInt(i)) * single_bar_height, single_bar_height, colour[1]);

        //Lower the amount of light by 0.85
        light.* *= 1 - ((1 - 0.95) * (render_state.game_state.delta_time * 250));
    }
}

fn drawBar(render_state: Screen.RenderState, val: f32, y: f32, h: f32, color: Gfx.ColorF) !void {
    var display_color: Gfx.ColorF = color;
    //Set opacity to 7/8
    display_color[3] = 0.875;

    var rounded_val = @floor(val);

    var val_fractional = val - rounded_val;

    try render_state.renderer.reserveSolidBox(.{ stat_gauge_x - rounded_val, y }, .{ rounded_val, h }, display_color);
    //Multiply opacity by the fractional part of the number
    display_color[3] *= val_fractional;
    try render_state.renderer.reserveSolidBox(.{ stat_gauge_x - rounded_val - 1, y }, .{ 1, h }, display_color);
}

fn drawLight(render_state: Screen.RenderState, light: f32, y: f32, h: f32, color: Gfx.ColorF) !void {
    var display_color: Gfx.ColorF = color;
    display_color[3] = 0.75 * light;

    //Set the display light to 4x the set light
    var display_light = light * 4;

    //Cap the display light to 1
    display_light = @min(1, display_light);

    //The amount to change the height of the light as it fades out
    var delta_height = @round(h * 0.5 * (1 - display_light) * (1 - display_light)) * 4;
    try render_state.renderer.reserveSolidBox(.{ stat_gauge_x - stat_gauge_width, y + delta_height / 2 }, .{ stat_gauge_width, h - delta_height }, display_color);
}

const accuracy_x = circle_x - circle_r;
const accuracy_y = 90;

fn drawScoreUi(render_state: Screen.RenderState, data: *GameplayData) !void {
    const combined_score: f64 = @floatFromInt(data.score.accuracy_score + data.score.typing_score);
    data.draw_score += (render_state.game_state.delta_time * 25 * (combined_score - data.draw_score));

    //Draw the score
    var buf: [8]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 0 };
    var used = std.fmt.formatIntBuf(
        &buf,
        @as(u64, @intFromFloat(@ceil(data.draw_score))),
        10,
        .upper,
        .{},
    );

    _ = try render_state.fontstash.drawText(
        .{ x_score, y_score },
        buf[0..used],
        .{
            .font = Fontstash.Mincho,
            .size = Fontstash.ptToPx(36),
            .color = Gfx.WhiteF,
            .alignment = .{
                .horizontal = .right,
                .vertical = .top,
            },
        },
    );

    var state = .{
        .font = Fontstash.Mincho,
        .size = Fontstash.ptToPx(36),
        .color = data.accuracy_text_color,
        .alignment = .{
            .horizontal = .left,
            .vertical = .top,
        },
    };

    //Get the accuracy timer in seconds, note we divide in 2 stagets to help remove floating point inaccuracies
    var accuracy_text_timer = @as(f32, @floatFromInt(data.animation_timers.accuracy_text.read() / std.time.ns_per_ms)) / std.time.ms_per_s;

    var accuracy_text_offset: f32 = 0;
    if (accuracy_text_timer < 0.05) {
        accuracy_text_offset = (0.05 - accuracy_text_timer) / 0.05 * 10;
    }
    accuracy_text_offset -= 6;

    if (accuracy_text_timer > 0.6) {
        //Set the color to 0 if we are after the point it is fully faded out, to skip all that math
        state.color[3] = 0;
    } else if (accuracy_text_timer > 0.5) {
        //Get the time since we started fading out
        const time_since_start_fade = (accuracy_text_timer - 0.5);
        //Fade out linearly from time 0.5 to 0.6
        state.color[3] = @max(0, 1.0 - time_since_start_fade * 10);
    }

    var metrics = render_state.fontstash.verticalMetrics(state);
    _ = try render_state.fontstash.drawText(
        .{ accuracy_x, accuracy_y + metrics.line_height + accuracy_text_offset },
        data.accuracy_text,
        state,
    );

    if (data.score.combo >= 10) {
        var digits = std.fmt.count("{d}", .{data.score.combo});

        _ = std.fmt.formatIntBuf(
            &buf,
            data.score.combo,
            10,
            .upper,
            .{ .width = 8, .fill = '0' },
        );

        _ = try render_state.fontstash.drawText(
            .{ accuracy_x + 35, accuracy_y + metrics.line_height + accuracy_text_offset },
            buf[buf.len - digits ..],
            .{
                .font = Fontstash.Mincho,
                .size = Fontstash.ptToPx(36),
                .color = state.color,
                .alignment = .{
                    .horizontal = .left,
                    .vertical = .top,
                },
            },
        );
    }
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
                try render_state.renderer.reserveTexQuadPxSize("white", .{ posX, posY + y0_bar }, .{ 1, y1_bar - y0_bar }, Gfx.WhiteF);
            },
            .beat => {
                try render_state.renderer.reserveTexQuadPxSize("white", .{ posX, posY + y0_beat }, .{ 1, y1_beat - y0_beat }, .{ 0.5, 0.5, 0.5, 1 });
            },
        }
    }

    //Draw all the typing cutoffs
    for (0..data.music.fumen.lyric_cutoffs.len) |j| {
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
            .excellent => excellent_color,
            .good => good_color,
            .fair => fair_color,
            .poor => poor_color,
        } else Gfx.RedF;

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

        var state = .{
            .font = Fontstash.Mincho,
            .size = Fontstash.ptToPx(50),
            .color = Gfx.WhiteF,
            .alignment = .{
                .horizontal = .center,
            },
        };

        //If the font size is too big and it goes outside of the notes,
        var bounds = try render_state.fontstash.textBounds(lyric.text, state);
        while (bounds.x2 > circle_r) {
            //Shrink the font size
            size -= 5;
            state.size = size;

            bounds = try render_state.fontstash.textBounds(lyric.text, state);
        }

        //Make sure the text size is at least 5
        size = @max(size, 5);

        //Draw the text inside of the notes
        _ = try render_state.fontstash.drawText(
            .{
                posX,
                posY + circle_y + render_state.fontstash.verticalMetrics(state).line_height - 3,
            },
            lyric.text,
            state,
        );

        //Draw the text below the notes
        _ = try render_state.fontstash.drawText(
            .{ posX, lyrics_y + posY },
            lyric.text,
            .{
                .font = Fontstash.Gothic,
                .size = Fontstash.ptToPx(28),
                .color = Gfx.WhiteF,
                .alignment = .{
                    .horizontal = .center,
                },
            },
        );

        if (lyric.hit_result == null) {
            //Draw the possible romaji below the notes
            //Create a variable to store how many we have drawn
            var rendered_romaji: usize = 0;
            //Iterate over all conversions
            for (render_state.game_state.convert.conversions) |conversion| {
                //Get the text that has yet to be typed
                const to_type = if (i == data.active_note) lyric.text[data.typed_hiragana.len..] else lyric.text;

                if (std.mem.startsWith(u8, to_type, conversion.hiragana)) {
                    rendered_romaji += 1;

                    _ = try render_state.fontstash.drawText(
                        .{ posX, lyrics_y + posY + 32 * @as(f32, @floatFromInt(rendered_romaji)) },
                        conversion.romaji,
                        .{
                            .font = Fontstash.Gothic,
                            .size = Fontstash.ptToPx(26),
                            .color = .{ 0.5, 0.5, 0.5, 1 },
                            .alignment = .{
                                .horizontal = .center,
                            },
                        },
                    );
                }
            }
        }
    }

    try render_state.renderer.reserveTexQuadPxSize("note", .{ circle_x - circle_r, circle_y - circle_r }, .{ circle_r * 2, circle_r * 2 }, Gfx.WhiteF);
}

fn drawKanjiLyrics(render_state: Screen.RenderState, data: *GameplayData) !void {
    //If there are no kanji lyrics, return out
    if (data.music.fumen.lyrics_kanji.len == 0) {
        return;
    }

    const next_string = "Next: ";

    _ = try render_state.fontstash.drawText(
        .{ lyrics_kanji_x, lyrics_kanji_next_y },
        next_string,
        .{
            .font = Fontstash.Gothic,
            .size = Fontstash.ptToPx(16),
            .color = Gfx.WhiteF,
            .alignment = .{
                .horizontal = .right,
            },
        },
    );

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
        try data.music.fumen.lyrics_kanji[data.current_lyric_kanji.?].draw(lyrics_kanji_x, lyrics_kanji_y, render_state);
    }

    //If we are not at the last lyric
    if (data.current_lyric_kanji != null and data.current_lyric_kanji.? < data.music.fumen.lyrics_kanji.len - 1) {
        const next_lyric_kanji = data.music.fumen.lyrics_kanji[data.current_lyric_kanji.? + 1];

        //Draw the next lyirc
        try next_lyric_kanji.draw(lyrics_kanji_x, lyrics_kanji_next_y, render_state);
    }
    //If we have not reached a lyric yet
    else if (data.current_lyric_kanji == null) {
        const next_lyric_kanji = data.music.fumen.lyrics_kanji[0];

        //Draw the next lyirc
        try next_lyric_kanji.draw(lyrics_kanji_x, lyrics_kanji_next_y, render_state);
    }
}
