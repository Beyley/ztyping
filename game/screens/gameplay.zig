const std = @import("std");
const bass = @import("bass");
const builtin = @import("builtin");
const fumen_compiler = @import("fumen_compiler");
const core = @import("mach").core;

const Screen = @import("../screen.zig");
const Gfx = @import("../gfx.zig");
const Fumen = @import("../fumen.zig");
const Music = @import("../music.zig");
const Convert = @import("../convert.zig");
const Fontstash = @import("../fontstash.zig");
const Challenge = @import("../challenge.zig");

const RenderState = Screen.RenderState;

const Phase = enum {
    ///Waiting on the player to start the game
    ready,
    ///While the game is playing
    main,
    ///Fading out, transition state between main and result
    fade_out,
    ///Start displaying the results, and ask for the users name
    result,
    ///The play is completely finished, results should still be drawn at this point
    finished,
    ///We are exiting the gameplay loop, and should return to the song selection screen
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

    excellent_count: usize = 0,
    good_count: usize = 0,
    fair_count: usize = 0,
    poor_count: usize = 0,
};

const GameplayData = struct {
    /// The current phase of the game, this determines how to handle keypresses, what to display, and so on
    phase: Phase = .ready,
    beat_line_left: usize = 0,
    beat_line_right: usize = std.math.maxInt(usize),

    /// The current audio time
    current_time: f64 = 0,

    /// The last tracked position of the mouse cursor
    last_mouse_x: f64 = 0,
    scrub_frame_counter: usize = 0,

    /// The current kanji lyric on display
    current_lyric_kanji: ?usize = null,

    animation_timers: AnimationTimers,

    gauge_data: GaugeData,

    ///The interpolated score to draw on the screen
    draw_score: f64 = 0,

    //things Actually Relavent to the gameplay

    ///Get the actively playing music
    music: *Music,

    ///The current speed of the music
    // speed: f32 = 1,
    // starting_freq: f32,

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
    /// The audio offset we should use for timing
    audio_offset: f64,
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
            const icount: isize = @intCast(count);
            const iclear_count: isize = @intCast(self.clear_count);

            const lost: isize = icount - iclear_count;
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
    const fade_out_time = 1.2;

    accuracy_text: std.time.Timer,
    fade_out: std.time.Timer,
};

pub var Gameplay = Screen{
    .render = renderScreen,
    .init = initScreen,
    .deinit = deinitScreen,
    .allocator = undefined,
    .char = char,
    .key_down = keyDown,
    .data = undefined,
    .app = undefined,
};

pub var challenge: Challenge.ChallengeInfo = undefined;

pub fn initScreen(self: *Screen, allocator: std.mem.Allocator, gfx: Gfx) anyerror!void {
    _ = gfx;
    self.allocator = allocator;

    const data = try allocator.create(GameplayData);
    errdefer allocator.destroy(data);

    data.* = .{
        .music = &self.app.current_map.?,
        .animation_timers = .{
            .accuracy_text = try std.time.Timer.start(),
            .fade_out = try std.time.Timer.start(),
        },
        .gauge_data = GaugeData.init(self.app.current_map.?.fumen.lyrics.len),
        .audio_offset = @as(f64, @floatFromInt(challenge.audio_offset)) / 1000.0,
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
    const full_audio_path = try dir.realpathAlloc(allocator, data.music.fumen.audio_path);
    defer allocator.free(full_audio_path);

    //Create a sentinel-ending array for the path
    const audio_pathZ = try allocator.dupeZ(u8, full_audio_path);
    defer allocator.free(audio_pathZ);
    std.debug.print("Loading song file {s}\n", .{audio_pathZ});
    self.app.audio_tracker.music = try bass.createFileStream(
        .{ .file = .{ .path = audio_pathZ } },
        0,
        .{
            .@"union" = .{
                .stream = .prescan,
            },
        },
    );

    const starting_freq = try self.app.audio_tracker.music.?.getAttribute(bass.ChannelAttribute.frequency);

    try self.app.audio_tracker.music.?.setAttribute(bass.ChannelAttribute.frequency, starting_freq * @as(f32, @floatCast(challenge.speed)));
}

pub fn deinitScreen(self: *Screen) void {
    const data = self.getData(GameplayData);

    //Stop the song
    self.app.audio_tracker.music.?.stop() catch |err| {
        std.debug.panicExtra(null, null, "Unable to stop music!!! err:{s}\n", .{@errorName(err)});
    };
    //Deinit the stream
    self.app.audio_tracker.music.?.deinit();

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

pub fn char(self: *Screen, typed_codepoint: u21) anyerror!void {
    var typed_char_buf: [std.math.maxInt(u3)]u8 = undefined;
    const typed_char: []const u8 = typed_char_buf[0..try std.unicode.utf8Encode(typed_codepoint, &typed_char_buf)];

    var data = self.getData(GameplayData);

    //If we're not in the main phase, ignore the input
    if (data.phase != .main) {
        return;
    }

    //Defer updateGauge to happen at the end of scope
    defer data.gauge_data.updateGauge(data);

    // std.debug.print("user wrote {s}\n", .{typed_char});

    const current_time = try self.app.audio_tracker.music.?.getSecondPosition() - data.audio_offset;

    var current_note: *Fumen.Lyric = &data.music.fumen.lyrics[data.active_note];
    var next_note: ?*Fumen.Lyric = if (data.active_note + 1 == data.music.fumen.lyrics.len) null else &data.music.fumen.lyrics[data.active_note + 1];

    var hiragana_to_type = current_note.text[data.typed_hiragana.len..];
    const hiragana_to_type_next: ?[]const u8 = if (next_note != null) next_note.?.text else &.{};

    const Match = struct {
        //The matched conversion
        conversion: Convert.Conversion,
        //The romaji to type
        romaji_to_type: []const u8,
    };

    //The found match for the current note
    var matched: ?Match = null;
    //The found match for the next hiragana (only for the current note, check matched_next for the next note)
    const next_hiragana_matched: ?Match = null;
    //The found match for the next note
    var matched_next: ?Match = null;

    _ = next_hiragana_matched;

    //Iterate over all conversions,
    for (self.app.convert.conversions) |conversion| {
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
                const romaji_to_type = conversion.romaji[data.typed_romaji.len..];

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
        for (self.app.convert.conversions) |conversion| {
            //TODO: WHAT THE FUCK WAS THIS SUPPOSED TO BE WHY DID I JUST STOP HERE
            _ = conversion;
        }
    }

    var current_note_finished: bool = false;
    var current_hiragana_finished: bool = false;
    var end_cut_hit: bool = false;
    if (matched) |matched_for_current_note| {
        if (current_note.pending_hit_result == null) {
            //Get the offset the user hit the note at, used to determine the hit result of the note
            const delta = current_time - current_note.time;

            //Get the hit result, using the absolute value
            var hit_result = deltaToHitResult(@abs(delta));

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

        for (self.app.convert.conversions) |conversion| {
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
        const delta = current_time - next_note.?.time;

        //Get the hit result, using the absolute value
        const hit_result = deltaToHitResult(@abs(delta));

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
    const score_combo = @min(combo_score * data.score.combo, combo_score_max);

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

    switch (note.pending_hit_result.?) {
        .excellent => data.score.excellent_count += 1,
        .good => data.score.good_count += 1,
        .fair => data.score.fair_count += 1,
        .poor => data.score.poor_count += 1,
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
        data.animation_timers.fade_out.reset();
        data.phase = .fade_out;
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

pub fn keyDown(self: *Screen, key: core.Key) anyerror!void {
    var data = self.getData(GameplayData);

    if (key == .escape) {
        self.close_screen = true;
        return;
    }

    if (data.phase == .ready) {
        data.phase = .main;

        try self.app.audio_tracker.music.?.play(true);

        return;
    }

    switch (key) {
        .backslash => {
            if (try self.app.audio_tracker.music.?.activeState() == .playing) {
                try self.app.audio_tracker.music.?.pause();
            } else {
                try self.app.audio_tracker.music.?.play(false);
            }
        },
        .enter => {
            //Dont do any of this when we arent in the main phase
            if (data.phase != .main) return;

            //Deinit the current fumen information
            data.music.fumen.deinit();

            //Get the filename of the source file
            const source_filename = try std.fmt.allocPrint(data.music.allocator, "{s}_src.txt", .{std.fs.path.stem(data.music.fumen_file_name)});
            defer data.music.allocator.free(source_filename);

            //Open the output dir
            var out_dir = try std.fs.openDirAbsolute(data.music.folder_path, .{});
            defer out_dir.close();

            //Open the source file
            var source_file = try out_dir.openFile(source_filename, .{ .mode = .read_write });
            defer source_file.close();

            //Run the compiler
            try fumen_compiler.compile(data.music.allocator, source_file, data.music.folder_path);

            //Open the new fumen file
            var fumen_file = try out_dir.openFile(data.music.fumen_file_name, .{});
            defer fumen_file.close();

            //Read the new fumen information from the file
            data.music.fumen.* = try Fumen.readFromFile(self.app.conv, data.music.allocator, fumen_file, out_dir);

            //Reset parts of the game state to let the user replay the map basically
            data.phase = Phase.main;
            data.active_note = 0;
            data.score = .{};
            //Reset draw score to 0, if we dont do this, then sometimes it will "bounce back" to negative values, and that will crash the game
            data.draw_score = 0;
            data.gauge_data = GaugeData.init(data.music.fumen.lyrics.len);
            data.current_lyric_kanji = null;
        },
        else => {},
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
    if (challenge.sin) {
        y += std.math.sin(workingX / scale_function) * scale_function;
    }
    if (challenge.cos) {
        y += std.math.cos(workingX / scale_function) * scale_function;
    }
    if (challenge.tan) {
        y += std.math.tan(workingX / scale_function) * scale_function;
    }
    return -y; // スクリーン座標は上下が逆
}

pub fn renderScreen(self: *Screen, render_state: RenderState) anyerror!void {
    var data = self.getData(GameplayData);

    data.current_time = try self.app.audio_tracker.music.?.getSecondPosition() - data.audio_offset;

    //In debug mode, allow the user to scrub through the song
    if (builtin.mode == .Debug) {
        data.scrub_frame_counter += 1;

        if (data.scrub_frame_counter > 20) {
            const right_depressed = core.mousePressed(.right);
            var mouse_x: f64 = core.mousePosition().x;

            const max_x = render_state.gfx.scale * 640.0;

            if (mouse_x < 0) {
                mouse_x = 0;
            }

            if (mouse_x > max_x) {
                mouse_x = max_x;
            }

            if (right_depressed and mouse_x != data.last_mouse_x) {
                const byte: u64 = @intFromFloat(@as(f64, @floatFromInt(try self.app.audio_tracker.music.?.getLength(.byte))) * (mouse_x / max_x));

                try self.app.audio_tracker.music.?.setPosition(byte, .byte, .{});
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

    //If we are in the fade out or result phases
    if (data.phase == .fade_out or data.phase == .result) {
        //If we are fully faded out, switch to the result phase
        if (data.animation_timers.fade_out.read() > @as(comptime_int, AnimationTimers.fade_out_time * std.time.ns_per_s)) {
            data.phase = .result;
        }

        //Begin a new render batch
        try render_state.renderer.begin();
        try render_state.fontstash.renderer.begin();

        const timer = @as(f32, @floatFromInt(data.animation_timers.fade_out.read())) / std.time.ns_per_s;

        //Calculate the opacity of the background, to slowly fade out the rest of the scene
        const fade_out_percentage: f32 = @min(timer / AnimationTimers.fade_out_time, 1);

        // Render the fade out background
        try render_state.renderer.reserveSolidBox(.{ 0, 0 }, .{ 640, 480 }, .{ 0, 0, 0, fade_out_percentage });

        const ranking_time = timer - AnimationTimers.fade_out_time;

        const count_all = data.score.excellent_count + data.score.good_count + data.score.fair_count + data.score.fair_count;

        if (ranking_time > 0) {
            _ = try render_state.fontstash.drawText(.{ 30, 10 }, "判定 :", Fontstash.Big);
        }

        if (ranking_time >= 0.6) {
            var color_state = Fontstash.Normal;
            color_state.color = excellent_color;
            try render_state.fontstash.formatText(
                .{ 320, 15 },
                "　優 : {d: >4} / {d}",
                .{
                    data.score.excellent_count,
                    count_all,
                },
                color_state,
            );
        }

        if (ranking_time >= 0.7) {
            var color_state = Fontstash.Normal;
            color_state.color = good_color;
            try render_state.fontstash.formatText(
                .{ 320, 40 },
                "　優 : {d: >4} / {d}",
                .{
                    data.score.good_count,
                    count_all,
                },
                color_state,
            );
        }

        if (ranking_time >= 0.8) {
            var color_state = Fontstash.Normal;
            color_state.color = fair_color;
            try render_state.fontstash.formatText(
                .{ 320, 65 },
                "　優 : {d: >4} / {d}",
                .{
                    data.score.fair_count,
                    count_all,
                },
                color_state,
            );
        }

        if (ranking_time >= 0.9) {
            var color_state = Fontstash.Normal;
            color_state.color = poor_color;
            try render_state.fontstash.formatText(
                .{ 320, 90 },
                "　優 : {d: >4} / {d}",
                .{
                    data.score.poor_count,
                    count_all,
                },
                color_state,
            );
        }

        //End the new render batch
        try render_state.renderer.end();
        try render_state.fontstash.renderer.end();

        //Draw it, with text on top
        try render_state.renderer.draw(render_state.render_pass_encoder);
        try render_state.fontstash.renderer.draw(render_state.render_pass_encoder);
    }

    // if (builtin.mode == .Debug) {
    //     var open = false;
    //     _ = c.igBegin("Gameplay Debugger", &open, 0);

    //     c.igText("Gameplay State");

    //     inline for (@typeInfo(GameplayData).Struct.fields) |field| {
    //         handleDebugType(data, field.name, field.type, {});
    //     }

    //     c.igSeparator();

    //     c.igText("Score");

    //     inline for (@typeInfo(Score).Struct.fields) |field| {
    //         handleDebugType(data.score, field.name, field.type, {});
    //     }

    //     c.igSeparator();

    //     c.igText("Gauge Data");

    //     inline for (@typeInfo(GaugeData).Struct.fields) |field| {
    //         handleDebugType(data.gauge_data, field.name, field.type, {});
    //     }

    //     c.igEnd();
    // }
}

// fn handleDebugType(data: anytype, comptime name: []const u8, comptime T: type, contents: anytype) void {
//     const actual_contents = if (@TypeOf(contents) == void) @field(data, name) else contents;

//     switch (@typeInfo(T)) {
//         .Int => {
//             c.igText(name ++ ": %d", actual_contents);
//         },
//         .Float => {
//             c.igText(name ++ ": %f", actual_contents);
//         },
//         .Enum => {
//             c.igText(name ++ ": %s", @tagName(actual_contents).ptr);
//         },
//         .Pointer => |ptr| {
//             //We dont handle printing non-slices, so just break out
//             if (ptr.size != .Slice) return;

//             switch (ptr.child) {
//                 u8 => {
//                     //We can just use normal %s for sentinel terminated arrays
//                     if (ptr.sentinel != null) {
//                         c.igText(name ++ ": \"%s\"", actual_contents.ptr);
//                     }
//                     //Else we have to use the `%.*s` magic
//                     else {
//                         c.igText(name ++ ": \"%.*s\"", actual_contents.len, actual_contents.ptr);
//                     }
//                 },
//                 else => {},
//             }
//         },
//         .Optional => |optional| {
//             const content = @field(data, name);

//             if (content == null) {
//                 c.igText(name ++ ": null");
//             } else {
//                 handleDebugType(data, name, optional.child, content.?);
//             }
//         },
//         else => {},
//     }
// }

const big_lyric_x = circle_x - circle_r;
const big_lyirc_y = 350;

fn drawCurrentLyricText(render_state: RenderState, data: *GameplayData) !void {
    //Only draw the current lyric text during the main phase
    if (data.phase != .main) {
        return;
    }

    //Dont draw current lyric text when the stealth or lyrics stealth is enabled
    if (challenge.stealth or challenge.lyrics_stealth) return;

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
        //Reset the fade out animation timer
        data.animation_timers.fade_out.reset();
        //Start fading out the gameplay
        data.phase = .fade_out;
        std.debug.print("note missed, game finished\n", .{});
    }

    data.gauge_data.updateGauge(data);
}

fn checkForMissedNotes(data: *GameplayData) void {
    if (data.phase != .main) {
        return;
    }

    //The current note the user is playing
    const current_note = data.music.fumen.lyrics[data.active_note];
    //The next note the user *could* hit
    const next_note: ?Fumen.Lyric = if (data.active_note < data.music.fumen.lyrics.len - 1) data.music.fumen.lyrics[data.active_note + 1] else null;

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
    const y: f32 = stat_gauge_y;
    const single_bar_height: f32 = stat_gauge_height / 4;

    for (&data.gauge_data.draw_x, &data.gauge_data.draw_v, &data.gauge_data.lengths) |*x, *velocity, length| {
        //Add a little bit of velocity, depending on the amount we need to change
        velocity.* += 0.12 * (length - x.*) * core.delta_time * 60;
        x.* += velocity.*;
        //Slow the velocity down
        velocity.* *= 0.7 * core.delta_time * 60;
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
        light.* *= 1 - ((1 - 0.95) * (core.delta_time * 250));
    }
}

fn drawBar(render_state: Screen.RenderState, val: f32, y: f32, h: f32, color: Gfx.ColorF) !void {
    var display_color: Gfx.ColorF = color;
    //Set opacity to 7/8
    display_color[3] = 0.875;

    const rounded_val = @floor(val);

    const val_fractional = val - rounded_val;

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
    const delta_height = @round(h * 0.5 * (1 - display_light) * (1 - display_light)) * 4;
    try render_state.renderer.reserveSolidBox(.{ stat_gauge_x - stat_gauge_width, y + delta_height / 2 }, .{ stat_gauge_width, h - delta_height }, display_color);
}

const accuracy_x = circle_x - circle_r;
const accuracy_y = 90;

fn drawScoreUi(render_state: Screen.RenderState, data: *GameplayData) !void {
    const combined_score: f64 = @floatFromInt(data.score.accuracy_score + data.score.typing_score);
    data.draw_score += (core.delta_time * 25 * (combined_score - data.draw_score));

    //Draw the score
    var buf: [8]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 0 };
    const used = std.fmt.formatIntBuf(
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

    //Get the accuracy timer in seconds, note we divide in 2 stages to help remove floating point inaccuracies
    const accuracy_text_timer = @as(f32, @floatFromInt(data.animation_timers.accuracy_text.read() / std.time.ns_per_ms)) / std.time.ms_per_s;

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

    const metrics = render_state.fontstash.verticalMetrics(state);
    _ = try render_state.fontstash.drawText(
        .{ accuracy_x, accuracy_y + metrics.line_height + accuracy_text_offset },
        data.accuracy_text,
        state,
    );

    if (data.score.combo >= 10) {
        const digits = std.fmt.count("{d}", .{data.score.combo});

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
        const beat_line = data.music.fumen.beat_lines[i];

        const time_diff = data.current_time - beat_line.time;
        const posX = getDrawPosX(time_diff);
        const posY = getDrawPosY(posX);

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
        const i = data.music.fumen.lyric_cutoffs.len - 1 - j;

        const lyric_cutoff = data.music.fumen.lyric_cutoffs[i];
        const time_diff = data.current_time - lyric_cutoff.time;

        const posX = getDrawPosX(time_diff);
        const posY = getDrawPosY(posX);

        if (posX < 0 - circle_r) break;
        if (posX > 640 + circle_r) continue;

        //Draw the note circle itself
        try render_state.renderer.reserveTexQuadPxSize(
            "typing_cutoff",
            .{ posX - circle_r, posY + circle_y - circle_r },
            .{ circle_r * 2, circle_r * 2 },
            Gfx.WhiteF,
        );
    }

    //We dont draw lyrics when the stealth mod is enabled
    if (!challenge.stealth) {
        const hidden_x = circle_x + circle_r + 60;
        const sudden_x = hidden_x + 30;

        const x_min: f32 = if (challenge.hidden) hidden_x else 0;
        const x_max: f32 = if (challenge.sudden) sudden_x else Screen.display_width;

        const rect: Gfx.RectU = .{
            @intFromFloat(x_min * render_state.gfx.scale),
            0,
            @intFromFloat((x_max - x_min) * render_state.gfx.scale),
            @intFromFloat(Screen.display_height * render_state.gfx.scale),
        };
        try render_state.renderer.setScissor(rect);
        try render_state.fontstash.renderer.setScissor(rect);

        defer render_state.renderer.resetScissor() catch unreachable;
        defer render_state.fontstash.renderer.resetScissor() catch unreachable;

        //Draw all the lyrics
        for (0..data.music.fumen.lyrics.len) |j| {
            const i = data.music.fumen.lyrics.len - 1 - j;

            var lyric = data.music.fumen.lyrics[i];
            const time_diff = data.current_time - lyric.time;

            const posX = getDrawPosX(time_diff);
            const posY = getDrawPosY(posX);

            //If the note is fully off the left side of the screen, break out, dont try to render any more notes
            if (posX < 0 - circle_r) break;
            //If the note is fully off the right side of the screen, skip it
            if (posX > 640 + circle_r) continue;

            //Get the color of the note
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

            if (!challenge.lyrics_stealth) {
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

                if (lyric.hit_result == null and render_state.app.config.display_romaji) {
                    //Draw the possible romaji below the notes
                    //Create a variable to store how many we have drawn
                    var rendered_romaji: usize = 0;
                    //Iterate over all conversions
                    for (render_state.app.convert.conversions) |conversion| {
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
        }
    }

    try render_state.renderer.reserveTexQuadPxSize("note", .{ circle_x - circle_r, circle_y - circle_r }, .{ circle_r * 2, circle_r * 2 }, Gfx.WhiteF);
}

fn drawKanjiLyrics(render_state: Screen.RenderState, data: *GameplayData) !void {
    //Dont draw kanji lyrics when lyrics stealth challenge is enabled
    if (challenge.lyrics_stealth) return;

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
