const std = @import("std");
const IConv = @import("iconv.zig");

const Self = @This();

pub const Conversion = struct {
    allocator: std.mem.Allocator,
    hiragana: []const u8,
    romaji: []const u8,
    length: usize,

    pub fn deinit(self: Conversion) void {
        self.allocator.free(self.hiragana);
        self.allocator.free(self.romaji);
    }
};

conversions: []const Conversion,
allocator: std.mem.Allocator,

pub fn deinit(self: Self) void {
    self.allocator.free(self.conversions);
}

pub fn readUTypingConversions(allocator: std.mem.Allocator) !Self {
    var file = try std.fs.cwd().openFile("convert.dat", .{});
    defer file.close();

    var raw_data = try allocator.alloc(u8, try file.getEndPos());
    defer allocator.free(raw_data);

    _ = try file.readAll(raw_data);

    var iconv = IConv.ziconv_open("Shift_JIS", "UTF-8");
    defer IConv.ziconv_close(iconv);

    var data = try iconv.convert(allocator, raw_data);
    defer allocator.free(data);

    var conversions = std.ArrayList(Conversion).init(allocator);
    errdefer {
        for (conversions.items) |item| {
            item.deinit();
        }

        conversions.deinit();
    }

    var stream = std.io.fixedBufferStream(data);
    var reader = stream.reader();

    while (true) {
        var raw_line = try reader.readUntilDelimiterOrEofAlloc(allocator, '\n', 50) orelse break;
        defer allocator.free(raw_line);

        var line = if (raw_line[raw_line.len - 1] == '\r') raw_line[0..(raw_line.len - 1)] else raw_line;

        var idx1 = std.mem.indexOf(u8, line, "\t") orelse return error.InvalidConvertFile;
        var idx2 = std.mem.indexOfPos(u8, line, idx1 + 1, "\t");

        var romaji = line[0..idx1];
        var hiragana = line[(idx1 + 1)..(idx2 orelse line.len)];
        var end_cut = if (idx2 == null) "" else line[(idx2.? + 1)..];

        try conversions.append(.{
            .allocator = allocator,
            .hiragana = try allocator.dupe(u8, hiragana),
            .romaji = try allocator.dupe(u8, romaji),
            .length = romaji.len - end_cut.len,
        });
    }

    return .{
        .allocator = allocator,
        .conversions = try conversions.toOwnedSlice(),
    };
}
