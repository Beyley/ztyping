const std = @import("std");
const Conv = @import("conv.zig");
const App = @import("app.zig");

const Self = @This();

pub const Conversion = struct {
    allocator: std.mem.Allocator,
    hiragana: []const u8,
    romaji: []const u8,
    end_cut: ?[]const u8,
    length: usize,

    pub fn deinit(self: Conversion) void {
        self.allocator.free(self.hiragana);
        self.allocator.free(self.romaji);
        if (self.end_cut) |end_cut| {
            self.allocator.free(end_cut);
        }
    }
};

conversions: []const Conversion,
allocator: std.mem.Allocator,

pub fn deinit(self: Self) void {
    self.allocator.free(self.conversions);
}

fn conversionLessThan(context: void, lhs: Conversion, rhs: Conversion) bool {
    _ = context;
    return lhs.hiragana.len > rhs.hiragana.len;
}

pub fn readUTypingConversions(conv: Conv, allocator: std.mem.Allocator) !Self {
    var file = try std.fs.cwd().openFile("convert.dat", .{});
    defer file.close();

    const raw_data = try allocator.alloc(u8, try file.getEndPos());
    defer allocator.free(raw_data);

    _ = try file.readAll(raw_data);

    //Do the initial conversion from Shift_JIS to UTF-8
    var converted_data = std.ArrayList(u8).init(allocator);
    defer converted_data.deinit();
    try conv.sjisToUtf8(raw_data, converted_data.writer());

    //Allocate a staging buffer to do the replacements in
    var raw_replaced_data = try allocator.alloc(u8, converted_data.items.len);
    defer allocator.free(raw_replaced_data);

    //NOTE: this is safe as the tilde and backslash are both 1 byte long, while the overline and yen sign are both longer, so the data is always guarenteed to be shoretr
    //Replace the tilde with the overline
    const underlines_replaced = std.mem.replace(u8, converted_data.items, "‾", "~", raw_replaced_data);
    //Replace the yen sign with the backslash
    const yen_replaced = std.mem.replace(u8, raw_replaced_data[0..(raw_replaced_data.len - underlines_replaced * ("‾".len - "~".len))], "¥", "\\", converted_data.items);

    //Calculate the length to cut off the end of the file, as the replacements will have shortened it
    const length_to_cut = underlines_replaced * ("‾".len - "~".len) + yen_replaced * ("¥".len - "\\".len);

    //Cut off the end of the file
    const data = converted_data.items[0..(converted_data.items.len - length_to_cut)];

    var conversions = std.ArrayList(Conversion).init(allocator);
    errdefer {
        for (conversions.items) |item| {
            item.deinit();
        }

        conversions.deinit();
    }

    var stream = std.io.fixedBufferStream(data);
    var reader = stream.reader();

    var buf: [50]u8 = undefined;
    while (true) {
        var raw_line = try reader.readUntilDelimiterOrEof(&buf, '\n') orelse break;

        var line = if (raw_line[raw_line.len - 1] == '\r') raw_line[0..(raw_line.len - 1)] else raw_line;

        const idx1 = std.mem.indexOf(u8, line, "\t") orelse return error.InvalidConvertFile;
        const idx2 = std.mem.indexOfPos(u8, line, idx1 + 1, "\t");

        const romaji = line[0..idx1];
        const hiragana = line[(idx1 + 1)..(idx2 orelse line.len)];
        var end_cut: ?[]const u8 = if (idx2 == null) null else line[(idx2.? + 1)..];

        //The end cut must not be empty, so if it is, set it to null
        if (end_cut != null and end_cut.?.len == 0) {
            end_cut = null;
        }

        //The romaji must be at least 1 char long
        if (romaji.len == 0) {
            return error.InvalidConvertFile;
        }

        //The hiragana must be at least 1 char long
        if (hiragana.len == 0) {
            return error.InvalidConvertFile;
        }

        //If the end cut is present, the romaji must not be only 1 char long
        if (end_cut != null and romaji.len == 1) {
            return error.InvalidConvertFile;
        }

        //If the end cut is present, it must be 1 char long
        if (end_cut != null and end_cut.?.len != 1) {
            return error.InvalidConvertFile;
        }

        try conversions.append(.{
            .allocator = allocator,
            .hiragana = try allocator.dupe(u8, hiragana),
            .romaji = try allocator.dupe(u8, romaji),
            .end_cut = if (end_cut == null) null else try allocator.dupe(u8, end_cut.?),
            .length = if (end_cut == null) romaji.len else romaji.len - end_cut.?.len,
        });
    }

    std.debug.print("parsed {d} hiragana/romaji conversions\n", .{conversions.items.len});

    std.mem.sort(Conversion, conversions.items, {}, conversionLessThan);

    return .{
        .allocator = allocator,
        .conversions = try conversions.toOwnedSlice(),
    };
}
