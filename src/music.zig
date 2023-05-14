const std = @import("std");

const IConv = @import("iconv.zig");
const Fumen = @import("fumen.zig");

const Self = @This();

title: []const u8,
artist: []const u8,
author: []const u8,
level: u3,
fumen_file_name: []const u8,
ranking_file_name: []const u8,
comment: []const []const u8,

fumen: Fumen,

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
    self.fumen.deinit();
}

pub fn readFromFile(allocator: std.mem.Allocator, path: std.fs.Dir, file: *std.fs.File) !Self {
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

        //While i dont like this behaviour, it matches UTyping
        if (self.level == 0) {
            return error.MusicInvalidLevel;
        }

        i += 1;
    }

    //i hate the look of this so much
    errdefer allocator.free(self.title);
    errdefer allocator.free(self.ranking_file_name);
    errdefer allocator.free(self.fumen_file_name);
    errdefer allocator.free(self.author);
    errdefer allocator.free(self.artist);
    errdefer {
        for (self.comment) |comment| {
            allocator.free(comment);
        }

        allocator.free(self.comment);
    }

    self.comment = try comments.toOwnedSlice();

    var fumen_path = try path.realpathAlloc(allocator, self.fumen_file_name);
    defer allocator.free(fumen_path);

    var fumen_file = try std.fs.openFileAbsolute(fumen_path, .{});
    defer fumen_file.close();

    self.fumen = try Fumen.readFromFile(allocator, &fumen_file);
    errdefer self.fumen.deinit();

    return self;
}
