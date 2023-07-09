const std = @import("std");
const IConv = @import("iconv.zig");
const RenderState = @import("screen.zig").RenderState;
const Gfx = @import("gfx.zig");
const Fontstash = @import("fontstash.zig");

pub const Lyric = struct {
    //A valid hit result for the note, the explicit numbers are to match up with the stat gauge
    pub const HitResult = enum(usize) {
        excellent = 0,
        good = 1,
        fair = 2,
        poor = 3,
    };

    text: [:0]const u8,
    time: f64,

    /// The hit result that they *could* get if they completed the note
    /// This is set when they press the first romaji of the note
    pending_hit_result: ?HitResult = null,
    ///The final hit result of the note, `null` means unset/unplayed
    hit_result: ?HitResult = null,

    ///Reset the status of the notes, allowing a song to be played again safely with the same note object
    pub fn resetHitStatus(self: *Lyric) void {
        self.hit_result = null;
        self.pending_hit_result = null;
    }
};
pub const LyricCutoff = struct {
    time: f64,
};
pub const LyricKanji = struct {
    pub const Part = struct {
        text: [:0]const u8,
        color: Gfx.ColorF,
    };

    parts: []const Part,
    time: f64,
    time_end: f64,

    pub fn draw(self: LyricKanji, x: f32, y: f32, render_state: RenderState) !void {
        //TODO: fade in lyrics letter by letter

        var acc_x = x;
        for (self.parts) |part| {
            const state = .{
                .font = Fontstash.Gothic,
                .size = Fontstash.ptToPx(16),
                .color = part.color,
                .alignment = .{
                    .horizontal = .left,
                },
            };

            try render_state.fontstash.drawText(
                .{ acc_x, y },
                part.text,
                state,
            );

            const bounds = try render_state.fontstash.textBounds(part.text, state);
            acc_x += bounds.x2 - bounds.x1;
        }
    }
};
pub const BeatLine = struct {
    pub const Type = enum {
        bar,
        beat,
    };

    time: f64,
    type: Type,
};

audio_path: [:0]const u8,
lyrics: []Lyric,
lyric_cutoffs: []const LyricCutoff,
lyrics_kanji: []const LyricKanji,
beat_lines: []const BeatLine,
fumen_folder: []const u8,
time_length: f64,

allocator: std.mem.Allocator,

const Self = @This();

pub fn deinit(self: Self) void {
    for (self.lyrics) |lyric| {
        self.allocator.free(lyric.text);
    }

    for (self.lyrics_kanji) |lyric_kanji| {
        for (lyric_kanji.parts) |part| {
            self.allocator.free(part.text);
        }

        self.allocator.free(lyric_kanji.parts);
    }

    self.allocator.free(self.audio_path);
    self.allocator.free(self.lyrics);
    self.allocator.free(self.lyric_cutoffs);
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
        .lyric_cutoffs = &.{},
        .time_length = 0,
    };

    var iconv = IConv.ziconv_open("Shift_JIS", "UTF-8");
    defer IConv.ziconv_close(iconv);

    var lyrics = std.ArrayList(Lyric).init(allocator);
    errdefer {
        for (lyrics.items) |lyric| {
            allocator.free(lyric.text);
        }
        lyrics.deinit();
    }

    var lyrics_kanji = std.ArrayList(LyricKanji).init(allocator);
    errdefer lyrics_kanji.deinit();

    var lyric_cutoffs = std.ArrayList(LyricCutoff).init(allocator);
    errdefer lyric_cutoffs.deinit();

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
                self.audio_path = try allocator.dupeZ(u8, without_identifier);
            },
            '+' => {
                var space_idx = std.mem.indexOf(u8, without_identifier, &.{' '}).?;

                var lyric = Lyric{
                    .time = try std.fmt.parseFloat(f64, without_identifier[0..space_idx]),
                    .text = try allocator.dupeZ(u8, without_identifier[(space_idx + 1)..]),
                };

                try lyrics.append(lyric);
            },
            '*' => {
                const space_idx = std.mem.indexOf(u8, without_identifier, &.{' '}).?;

                const time = try std.fmt.parseFloat(f64, without_identifier[0..space_idx]);

                if (lyrics_kanji.items.len > 0) {
                    lyrics_kanji.items[lyrics_kanji.items.len - 1].time_end = time;
                }

                //The raw text of the lyric
                const raw_text = try allocator.dupe(u8, without_identifier[(space_idx + 1)..]);
                defer allocator.free(raw_text);

                //Split the text by "\|"
                var split_iterator = std.mem.splitSequence(u8, raw_text, "¥|");

                var part_list = std.ArrayList(LyricKanji.Part).init(allocator);
                defer part_list.deinit();
                errdefer {
                    for (part_list.items) |part| {
                        allocator.free(part.text);
                    }
                }

                var grey = false;
                var next = split_iterator.next();
                while (next != null) {
                    try part_list.append(LyricKanji.Part{
                        .text = try allocator.dupeZ(u8, next.?),
                        .color = if (grey) .{ 0.25, 0.25, 1.0 / 3.0, 1 } else Gfx.WhiteF,
                    });

                    //Flip grey, since every split in UTyping is a alternating color of grey, white
                    grey = !grey;
                    next = split_iterator.next();
                }

                var lyric = LyricKanji{
                    .time = time,
                    .time_end = std.math.inf(f64),
                    .parts = try part_list.toOwnedSlice(),
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
                var time = try std.fmt.parseFloat(f64, without_identifier);

                if (lyrics_kanji.items.len > 0) {
                    lyrics_kanji.items[lyrics_kanji.items.len - 1].time_end = time;
                }

                self.time_length = time;

                try lyric_cutoffs.append(.{ .time = time });
            },
            else => {
                return error.UnexpectedCharacterWhileParsingFumen;
            },
        }
    }

    self.lyrics = try lyrics.toOwnedSlice();
    self.lyric_cutoffs = try lyric_cutoffs.toOwnedSlice();
    self.lyrics_kanji = try lyrics_kanji.toOwnedSlice();
    self.beat_lines = try beat_lines.toOwnedSlice();

    self.fumen_folder = try dir.realpathAlloc(allocator, ".");

    return self;
}
