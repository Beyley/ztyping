const std = @import("std");

const Self = @This();

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

const Context = extern struct {
    context: ?*anyopaque,
};

extern fn ziconv_open(src: [*c]const u8, dst: [*c]const u8) Context;
extern fn ziconv_close(context: Context) void;
extern fn ziconv_convert(context: Context, src: [*c][*c]u8, dst: [*c][*c]u8, src_len: *usize, dst_len: *usize) usize;

pub fn readFromFile(allocator: std.mem.Allocator, file: *std.fs.File) !Self {
    var self: Self = undefined;
    self.allocator = allocator;

    var iconv = ziconv_open("Shift_JIS", "UTF-8");
    defer ziconv_close(iconv);

    var comments = std.ArrayList([]const u8).init(allocator);
    errdefer comments.deinit();

    //Set to 12 to match COMMENT_N_LINES in UTyping.cpp
    try comments.ensureTotalCapacity(12);

    var i: usize = 0;
    while (true) {
        var orig_line = try file.reader().readUntilDelimiterOrEofAlloc(allocator, '\n', std.math.maxInt(u32)) orelse break;
        defer allocator.free(orig_line);

        var returnless = if (orig_line[orig_line.len - 1] == '\r') orig_line[0 .. orig_line.len - 1] else orig_line;

        var dest_line = try allocator.alloc(u8, returnless.len + (returnless.len / 2));
        defer allocator.free(dest_line);

        var orig_c_ptr: [*c]u8 = returnless.ptr;
        var dst_c_ptr: [*c]u8 = dest_line.ptr;
        var orig_bytes_left = returnless.len;
        var dest_bytes_left = dest_line.len;

        while (orig_bytes_left > 0) {
            var ret = ziconv_convert(iconv, &orig_c_ptr, &dst_c_ptr, &orig_bytes_left, &dest_bytes_left);
            if (ret == @bitCast(usize, @as(isize, -1))) {
                return error.UnableToConvertShiftJISToUTF8;
            }

            //If theres still more source bytes, and the destination is full
            if (orig_bytes_left > 0 and dest_bytes_left == 0) {
                //Allocate a new bigger array
                var new = try allocator.alloc(u8, dest_line.len + orig_bytes_left * 2);
                //Copy the old data into the new array
                @memcpy(new[0..dest_line.len], dest_line);

                //Mark that we have more space now
                dest_bytes_left += new.len - dest_line.len;

                //Free the old destination array
                allocator.free(dest_line);

                //Set the old destination array to the new one
                dest_line = new;
            }
        }

        var line = dest_line[0 .. dest_line.len - dest_bytes_left];

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
