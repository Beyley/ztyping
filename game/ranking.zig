const std = @import("std");

const Challenge = @import("challenge.zig").ChallengeInfo;

const Self = @This();

const Gfx = @import("gfx.zig");
const Screen = @import("screen.zig");
const Fontstash = @import("fontstash.zig");

const RenderState = Screen.RenderState;

/// The maximum length for a UTyping score name
const name_len = 16;

/// The maximum number of rankings stored
const ranking_len = 20;

/// Whether or not the scores have changed, and they should be re-written to the file
changed: bool = false,
scores: [ranking_len]Score,
achievement: RankingLevel,
play_count: i32,
play_time: i32,

pub const UTypingDate = packed struct(i32) {
    day: u8,
    month: u8,
    year: u16,
};

/// Gets the current date, in the UTyping date format
pub fn getUTypingDate() UTypingDate {
    //Get the current timestamp
    var epoch_seconds = std.time.epoch.EpochSeconds{
        .secs = @intCast(std.time.timestamp()),
    };
    //Get the year and day
    var year_day = epoch_seconds.getEpochDay().calculateYearDay();
    //Get the year and month
    const month_and_day = year_day.calculateMonthDay();

    return .{
        .day = month_and_day.day_index,
        .month = @intFromEnum(month_and_day.month),
        .year = year_day.year,
    };
}

pub fn draw(
    self: Self,
    render_state: RenderState,
    pos: Gfx.Vector2,
    rank_begin: usize,
    rank_len: usize,
    comptime font: []const u8,
) !void {
    _ = render_state;
    for (rank_begin..(rank_begin + rank_len)) |i| {
        //Break out if we are drawing more than the max amount of storable ranks
        if (i >= ranking_len) {
            break;
        }

        try self.scores[i].draw(pos + Gfx.Vector2{ 0, 48 * i }, i + 1, font);
    }
}

pub fn readRanking(file: std.fs.File) !Self {
    var ranking = Self{
        .achievement = .no_data,
        .play_count = 0,
        .play_time = 0,
        .changed = false,
        //set scores to undefined, as it is init later
        .scores = .{comptime Score.init()} ** ranking_len,
    };
    //Set all of the scores to the default state
    @memset(&ranking.scores, Score.init());

    var buffered_reader = std.io.bufferedReader(file.reader());
    var reader = buffered_reader.reader();

    var version: i32 = reader.readInt(i32, .little) catch |err| {
        if (err == std.fs.File.Reader.NoEofError.EndOfStream) {
            return ranking;
        }

        return err;
    };

    const ranking_file_version = 5;

    //If the first byte of the version is greater than 32, than assume version is 0
    if ((version & 0xff) > ' ') {
        version = 0;
        //Seek back to the start
        try file.seekTo(0);

        //Reset the buffered reader
        buffered_reader = std.io.bufferedReader(file.reader());
        reader = buffered_reader.reader();
    }

    //If we found an invalid ranking version, throw an error
    if (version > ranking_file_version or version < 0) {
        std.debug.print("found unknown ranking version {d}\n", .{version});
        return error.UnknownRankingVersion;
    }

    //In version 4, achivement was added to the score data34
    if (version >= 4) {
        ranking.achievement = try reader.readEnum(RankingLevel, .little);
    }

    //In version 3, play count and play time was added
    if (version >= 3) {
        ranking.play_count = try reader.readInt(i32, .little);
        ranking.play_time = try reader.readInt(i32, .little);
    }

    //In version 5, we now only store the exact number of scores, rather than all ranking_len scores.
    const ranking_size: usize = if (version >= 5) @intCast(try reader.readInt(i32, .little)) else ranking_len;

    //Iterate through all the rankings and read the scores
    for (0..ranking_size) |i| {
        ranking.scores[i] = try Score.read(reader, version);
    }

    //In version 4, achivement was added to the score data
    if (version < 4) {
        for (&ranking.scores) |score| {
            const level = score.getLevel();
            //If this score is better than the currently stored achivement
            if (@intFromEnum(level) > @intFromEnum(ranking.achievement)) {
                //Store that achivement
                ranking.achievement = level;
            }
        }
    }

    try file.seekTo(0);

    return ranking;
}

pub const RankingLevel = enum(i32) {
    no_data = 0,
    failed = 0x0100,
    red_zone = 0x0200,
    yellow_zone = 0x0240,
    blue_zone = 0x0280,
    clear = 0x0300,
    full_combo = 0x0500,
    full_good = 0x0600,
    perfect = 0x0700,
};

fn formatOrdinal(writer: anytype, num: anytype) !void {
    try std.fmt.format(writer, "{d}", .{num});
    if ((num / 10) % 10 == 1) {
        try writer.writeAll("th");
    } else switch (num % 10) {
        1 => try writer.writeAll("th"),
        2 => try writer.writeAll("nd"),
        3 => try writer.writeAll("rd"),
        else => try writer.writeAll("th"),
    }
}

pub const Score = struct {
    name: [name_len]u8,
    score: i32,
    score_accuracy: i32,
    score_typing: i32,
    ///The counts of the judgements, in order of: Excellent, Good, Fair, Poor, Pass
    count: [5]i32,
    count_all: i32,
    combo_max: i32,
    challenge: Challenge,
    date: UTypingDate,

    pub fn init() Score {
        var score = Score{
            .name = undefined,
            .score = 0,
            .score_accuracy = 0,
            .score_typing = 0,
            .count = .{ 0, 0, 0, 0, 0 },
            .count_all = 0,
            .combo_max = 0,
            .date = .{
                .day = 0,
                .month = 0,
                .year = 0,
            },
            .challenge = .{},
        };

        //Zero-init the score to all zeroes
        @memset(&score.name, 0);
        //Set the first char to `_`
        score.name[0] = '_';

        return score;
    }

    pub fn draw(
        self: Score,
        render_state: RenderState,
        pos: Gfx.Vector2,
        n: usize,
        comptime font: []const u8,
    ) !void {
        _ = font;
        _ = n;
        _ = pos;
        _ = render_state;
        _ = self;
    }

    pub fn getLevel(self: Score) RankingLevel {
        if (self.combo_max != -1) return .no_data;
        if (self.count[2] != 0) return .full_combo;
        if (self.count[1] != 0) return .full_good;
        return .perfect;
    }

    pub fn read(reader: anytype, version: i32) !Score {
        var score = init();

        //In version 1, the score name length was bumped from 8 to 16
        if (version >= 1) {
            //Read the full name_len bytes for the name
            _ = try reader.readNoEof(&score.name);
        } else {
            //Read only 8 bytes, as names were only 8 bytes in size in version 1
            _ = try reader.readNoEof(score.name[0..8]);
            score.name[8] = 0;
        }
        //Read the combined score
        score.score = try reader.readInt(i32, .little);
        //Read the accuracy score
        score.score_accuracy = try reader.readInt(i32, .little);
        //Read the typing score
        score.score_typing = try reader.readInt(i32, .little);
        //Iterate over all the count parameters
        for (&score.count) |*count| {
            //Set them to the read value
            count.* = try reader.readInt(i32, .little);
        }
        //Read the total count
        score.count_all = try reader.readInt(i32, .little);
        //Read the max combo
        score.combo_max = try reader.readInt(i32, .little);

        const challenge_num = 7;
        //In version 1, challenges were added
        if (version >= 1) {
            //Iterate over all known challenges
            for (0..challenge_num) |i| {
                //If the challenge is enabled
                if (try reader.readByte() != 0)
                    //Enable the associated challenge
                    switch (i) {
                        0 => score.challenge.hidden = true,
                        1 => score.challenge.sudden = true,
                        2 => score.challenge.stealth = true,
                        3 => score.challenge.lyrics_stealth = true,
                        4 => score.challenge.sin = true,
                        5 => score.challenge.cos = true,
                        6 => score.challenge.tan = true,
                        else => @panic("Unhandled challenge int"),
                    };
            }
            //Ignore all the rest of the bytes up to 16 (left for future use I assume)
            for (challenge_num..16) |_| {
                _ = try reader.readByte();
            }
            //Read the speed
            score.challenge.speed = @as(f64, @floatFromInt(try reader.readInt(i32, .little))) / 10.0;
            //Read the key
            score.challenge.key = try reader.readInt(i32, .little);
        }

        //In version 2, dates were added to the scores
        if (version >= 2) {
            //Read the date
            score.date = @bitCast(try reader.readInt(i32, .little));
        }

        return score;
    }
};
