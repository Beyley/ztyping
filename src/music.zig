const std = @import("std");

const Self = @This();

const IConv = @import("iconv.zig");

title: []const u8,
artist: []const u8,
author: []const u8,
level: u3,
fumen_file_name: []const u8,
ranking_file_name: []const u8,
comment: []const []const u8,

allocator: std.mem.Allocator,

pub fn deinit(self: *Self) void {
    self.allocator.free(self.title);
    self.allocator.free(self.artist);
    self.allocator.free(self.author);
    self.allocator.free(self.fumen_file_name);
    self.allocator.free(self.ranking_file_name);

    for (self.comment) |comment| {
        self.allocator.free(comment);
    }

    self.allocator.free(self.comment);
}

pub fn readFromFile(allocator: std.mem.Allocator, file: *std.fs.File) !Self {
    var self: Self = undefined;
    self.allocator = allocator;

    var iconv = IConv.ziconv_open("Shift_JIS", "UTF-8");
    defer IConv.ziconv_close(iconv);

    var comments = std.ArrayList([]const u8).init(allocator);
    errdefer comments.deinit();

    //Set to 12 to match COMMENT_N_LINES in UTyping.cpp
    try comments.ensureTotalCapacity(12);

    var i: usize = 0;
    while (true) {
        var orig_line = try file.reader().readUntilDelimiterOrEofAlloc(allocator, '\n', std.math.maxInt(u32)) orelse break;
        defer allocator.free(orig_line);

        var returnless = if (orig_line[orig_line.len - 1] == '\r') orig_line[0 .. orig_line.len - 1] else orig_line;

        var line = try iconv.convert(allocator, returnless);
        defer allocator.free(line);

        //If the last char is \r, strip it out
        if (line.len > 0 and line[line.len - 1] == '\r') {
            line = line[0..(line.len - 1)];
        }

        if (i == 0) {
            self.title = try allocator.dupe(u8, line);
        } else if (i == 1) {
            self.artist = try allocator.dupe(u8, line);
        } else if (i == 2) {
            self.author = try allocator.dupe(u8, line);
        } else if (i == 3) {
            self.level = try std.fmt.parseUnsigned(u3, line, 0);
        } else if (i == 4) {
            self.fumen_file_name = try allocator.dupe(u8, line);
        } else if (i == 5) {
            self.ranking_file_name = try allocator.dupe(u8, line);
        } else {
            try comments.append(try allocator.dupe(u8, line));
        }

        i += 1;
    }

    self.comment = try comments.toOwnedSlice();

    return self;
}
