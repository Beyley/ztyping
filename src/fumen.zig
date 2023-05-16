const std = @import("std");
const IConv = @import("iconv.zig");

const Lyric = struct {
    text: []const u8,
    time: f64,
};
const LyricKanji = struct {
    text: []const u8,
    time: f64,
    time_end: f64,
};
const BeatLine = struct {
    pub const Type = enum {
        bar,
        beat,
    };

    time: f64,
    type: Type,
};

audio_path: []const u8,
lyrics: []const Lyric,
lyrics_kanji: []const LyricKanji,
beat_lines: []const BeatLine,
fumen_folder: []const u8,

allocator: std.mem.Allocator,

const Self = @This();

pub fn deinit(self: Self) void {
    for (self.lyrics) |lyric| {
        self.allocator.free(lyric.text);
    }

    for (self.lyrics_kanji) |lyric_kanji| {
        self.allocator.free(lyric_kanji.text);
    }

    self.allocator.free(self.audio_path);
    self.allocator.free(self.lyrics);
    self.allocator.free(self.lyrics_kanji);
    self.allocator.free(self.beat_lines);
    self.allocator.free(self.fumen_folder);
}

pub fn readFromFile(allocator: std.mem.Allocator, file: *std.fs.File, dir: std.fs.Dir) !Self {
    var self: Self = .{
        .allocator = allocator,
        .audio_path = &.{},
        .lyrics = &.{},
        .lyrics_kanji = &.{},
        .beat_lines = &.{},
        .fumen_folder = &.{},
    };

    var iconv = IConv.ziconv_open("Shift_JIS", "UTF-8");
    defer IConv.ziconv_close(iconv);

    var lyrics = std.ArrayList(Lyric).init(allocator);
    errdefer lyrics.deinit();

    var lyrics_kanji = std.ArrayList(LyricKanji).init(allocator);
    errdefer lyrics_kanji.deinit();

    var beat_lines = std.ArrayList(BeatLine).init(allocator);
    errdefer beat_lines.deinit();

    while (true) {
        var orig_line: []u8 = try file.reader().readUntilDelimiterOrEofAlloc(allocator, '\n', std.math.maxInt(u32)) orelse break;
        defer allocator.free(orig_line);

        var returnless = if (orig_line[orig_line.len - 1] == '\r') orig_line[0 .. orig_line.len - 1] else orig_line;

        var converted = try iconv.convert(allocator, returnless);
        defer allocator.free(converted);

        var without_identifier = converted[1..];

        switch (converted[0]) {
            '@' => {
                self.audio_path = try allocator.dupe(u8, without_identifier);
            },
            '+' => {
                var space_idx = std.mem.indexOf(u8, without_identifier, &.{' '}).?;

                var lyric = Lyric{
                    .time = try std.fmt.parseFloat(f64, without_identifier[0..space_idx]),
                    .text = try allocator.dupe(u8, without_identifier[(space_idx + 1)..]),
                };

                try lyrics.append(lyric);
            },
            '*' => {
                var space_idx = std.mem.indexOf(u8, without_identifier, &.{' '}).?;

                var lyric = LyricKanji{
                    .time = try std.fmt.parseFloat(f64, without_identifier[0..space_idx]),
                    .time_end = std.math.inf(f64),
                    .text = try allocator.dupe(u8, without_identifier[(space_idx + 1)..]),
                };

                try lyrics_kanji.append(lyric);
            },
            '=' => {
                try beat_lines.append(.{
                    .type = .bar,
                    .time = try std.fmt.parseFloat(f64, without_identifier),
                });
            },
            '-' => {
                try beat_lines.append(.{
                    .type = .beat,
                    .time = try std.fmt.parseFloat(f64, without_identifier),
                });
            },
            '/' => {
                if (lyrics_kanji.items.len > 0) {
                    lyrics_kanji.items[lyrics_kanji.items.len - 1].time_end = try std.fmt.parseFloat(f64, without_identifier);
                }
            },
            else => {
                return error.UnexpectedCharacterWhileParsingFumen;
            },
        }
    }

    self.lyrics = try lyrics.toOwnedSlice();
    self.lyrics_kanji = try lyrics_kanji.toOwnedSlice();
    self.beat_lines = try beat_lines.toOwnedSlice();

    self.fumen_folder = try dir.realpathAlloc(allocator, ".");

    return self;
}
