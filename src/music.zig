const std = @import("std");

const IConv = @import("iconv.zig");
const Fumen = @import("fumen.zig");

const Self = @This();

title: [:0]const u8,
artist: [:0]const u8,
author: [:0]const u8,
level: u3,
fumen_file_name: [:0]const u8,
ranking_file_name: [:0]const u8,
comment: []const [:0]const u8,

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

    var comments = std.ArrayList([:0]const u8).init(allocator);
    errdefer {
        for (comments.items) |comment| {
            allocator.free(comment);
        }
        comments.deinit();
    }

    //Set to 12 to match COMMENT_N_LINES in UTyping.cpp
    try comments.ensureTotalCapacity(12);

    var title: ?[:0]const u8 = null;
    var artist: ?[:0]const u8 = null;
    var author: ?[:0]const u8 = null;
    var fumen_file_name: ?[:0]const u8 = null;
    var ranking_file_name: ?[:0]const u8 = null;

    errdefer if (title) |title_ptr| allocator.free(title_ptr);
    errdefer if (artist) |artist_ptr| allocator.free(artist_ptr);
    errdefer if (author) |author_ptr| allocator.free(author_ptr);
    errdefer if (fumen_file_name) |fumen_file_name_ptr| allocator.free(fumen_file_name_ptr);
    errdefer if (ranking_file_name) |ranking_file_name_ptr| allocator.free(ranking_file_name_ptr);

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
            title = try allocator.dupeZ(u8, line);
        } else if (i == 1) {
            artist = try allocator.dupeZ(u8, line);
        } else if (i == 2) {
            author = try allocator.dupeZ(u8, line);
        } else if (i == 3) {
            self.level = try std.fmt.parseUnsigned(u3, line, 0);
        } else if (i == 4) {
            fumen_file_name = try allocator.dupeZ(u8, line);
        } else if (i == 5) {
            ranking_file_name = try allocator.dupeZ(u8, line);
        } else {
            try comments.append(try allocator.dupeZ(u8, line));
        }

        //While i dont like this behaviour, it matches UTyping
        if (self.level == 0) {
            return error.MusicInvalidLevel;
        }

        i += 1;
    }

    self.title = title.?;
    self.artist = artist.?;
    self.author = author.?;
    self.fumen_file_name = fumen_file_name.?;
    self.ranking_file_name = ranking_file_name.?;

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

    self.fumen = try Fumen.readFromFile(allocator, &fumen_file, path);
    errdefer self.fumen.deinit();

    return self;
}

pub fn readUTypingList(allocator: std.mem.Allocator) ![]Self {
    var list_file = try std.fs.cwd().openFile("UTyping_list.txt", .{});
    defer list_file.close();

    var reader = list_file.reader();

    var music_list = std.ArrayList(Self).init(allocator);
    errdefer {
        for (0..music_list.items.len) |i| {
            music_list.items[i].deinit();
        }
        music_list.deinit();
    }

    while (true) {
        var line = try reader.readUntilDelimiterOrEofAlloc(allocator, '\n', 100) orelse break;
        defer allocator.free(line);

        //Normalize, aka remove \r and change `\` to `/`
        var normalized = try std.mem.replaceOwned(u8, allocator, if (line[line.len - 1] == '\r') line[0 .. line.len - 1] else line, &.{'\\'}, &.{'/'});
        defer allocator.free(normalized);

        var music_file = try std.fs.cwd().openFile(normalized, .{});
        defer music_file.close();

        var music_dir = try std.fs.cwd().openDir(std.fs.path.dirname(normalized) orelse "", .{});
        defer music_dir.close();

        var music = try readFromFile(allocator, music_dir, &music_file);

        try music_list.append(music);
    }

    return try music_list.toOwnedSlice();
}
