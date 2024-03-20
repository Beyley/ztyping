const std = @import("std");

const SliceIterator = @import("slice_iterator").SliceIterator;
const Self = @This();

const DataTable = @embedFile("sjis-unicode.txt");

map: std.AutoHashMap(u16, [2]u21),

pub fn init(allocator: std.mem.Allocator) !Self {
    var map = std.AutoHashMap(u16, [2]u21).init(allocator);
    errdefer map.deinit();

    var line_iterator = std.mem.split(u8, DataTable, "\n");

    while (line_iterator.next()) |line| {
        //Skip all comments or blank lines
        if (line.len == 0 or line[0] == '#')
            continue;

        var tokenizer = std.mem.tokenize(u8, line, " \t");

        const sjis_str = tokenizer.next() orelse return error.Oops;
        const unicode_str = (tokenizer.next() orelse return error.Oops2);

        // Skip comments...
        if (unicode_str[0] == '#') continue;

        const sjis = try std.fmt.parseInt(u16, sjis_str[2..], 16);

        // We dont really care about null bytes
        if (sjis == 0) continue;

        var unicode_iter = std.mem.split(u8, unicode_str[2..], "+");

        try map.put(sjis, .{
            try std.fmt.parseInt(u21, unicode_iter.next().?, 16),
            try std.fmt.parseInt(u21, unicode_iter.next() orelse "0", 16),
        });
    }

    return .{
        .map = map,
    };
}

pub fn deinit(self: *Self) void {
    self.map.deinit();
}

pub fn sjisToUtf8(self: Self, sjis: []const u8, writer: anytype) !void {
    var unicode: [std.math.maxInt(u3)]u8 = undefined;

    var iter = SliceIterator(u8).new(sjis);
    while (iter.next()) |c| {
        //If this is the start to a multibyte sequence, then read the second byte aswell for the conversion3
        if ((c >= 0x81 and c <= 0x9F) or (c >= 0xE0 and c <= 0xFC)) {
            const next = iter.next() orelse return error.InvalidSjis;

            const codepoints = self.map.get(std.mem.readInt(u16, &.{ c, next }, .big));

            if (codepoints == null) {
                std.debug.print("Unknown SJIS sequence {x}{x}\n", .{ c, next });
            }

            for (codepoints orelse .{ '?', 0 }) |codepoint| {
                if (codepoint == 0) continue;

                const unicode_slice = unicode[0..try std.unicode.utf8Encode(
                    codepoint,
                    &unicode,
                )];

                try writer.writeAll(unicode_slice);
            }
        } else {
            const codepoints = self.map.get(c);

            if (codepoints == null) {
                std.debug.print("Unknown SJIS sequence {x}\n", .{c});
            }

            for (codepoints orelse .{ '?', 0 }) |codepoint| {
                if (codepoint == 0) continue;

                const unicode_slice = unicode[0..try std.unicode.utf8Encode(
                    codepoint,
                    &unicode,
                )];

                try writer.writeAll(unicode_slice);
            }
        }
    }
}
