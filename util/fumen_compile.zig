const std = @import("std");
const clap = @import("clap");

const SliceIterator = @import("slice_iterator.zig").SliceIterator;

const io = std.io;

const param_str =
    \\-h, --help    Display this help and exit
    \\<str>...  File path
;

const Info = struct {
    speed: f64,
    base: std.ArrayList(usize),
    base_pos: usize,
    base_half: bool,
    time: f64,
    beat_nu: usize,
    beat_de: usize,
    beat_int: usize,
    beat_frac: f64,
};

fn stripNewline(line: []u8) []u8 {
    return if (line[line.len - 1] == '\r') line[0 .. line.len - 1] else line;
}

const ItemType = enum {
    ///0
    separator,
    ///1
    lyric,
    ///2
    kanji_lyric,
    ///3
    lyirc_and_kanji_lyric,
    ///-1
    bar_line,
    ///-2
    beat_line,
};

const TimeArray = std.ArrayList(struct { f64, ItemType });

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("MEMORY LEAK WAAAAA");
    var allocator = gpa.allocator();

    const params = comptime clap.parseParamsComptime(param_str);

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
    }) catch |err| {
        // Report useful error and exit
        diag.report(io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        return std.debug.print("ztyping fumen compiler\n{s}\n", .{param_str});
    }

    if (res.positionals.len != 1) {
        return std.debug.print("You must provide a file path.\n", .{});
    }

    const file_name = try std.fs.realpathAlloc(allocator, res.positionals[0]);
    defer allocator.free(file_name);

    const dir_name = std.fs.path.dirname(file_name) orelse unreachable;

    const file = try std.fs.openFileAbsolute(file_name, .{});
    defer file.close();

    var buffered_reader = std.io.bufferedReader(file.reader());

    var reader = buffered_reader.reader();

    var info = Info{
        .speed = -1,
        .base = std.ArrayList(usize).init(allocator),
        .base_pos = 0,
        .base_half = false,
        .time = 0.0,
        .beat_nu = 0,
        .beat_de = 0,
        .beat_int = 0,
        .beat_frac = 0,
    };
    defer info.base.deinit();

    var time_array = TimeArray.init(allocator);
    defer time_array.deinit();

    var lyrics_array = std.ArrayList([]const u8).init(allocator);
    defer {
        for (lyrics_array.items) |lyric| {
            allocator.free(lyric);
        }
        lyrics_array.deinit();
    }
    var kanji_lyircs_array = std.ArrayList([]const u8).init(allocator);
    defer {
        for (kanji_lyircs_array.items) |lyric| {
            allocator.free(lyric);
        }
        kanji_lyircs_array.deinit();
    }

    var buf: [1024]u8 = undefined;

    //Get the destnation name from the source file
    const dest_name = stripNewline(try reader.readUntilDelimiterOrEof(&buf, '\n') orelse return error.UnexpectedEOF);

    if (dest_name.len == 0) {
        return error.InvalidDestinationName;
    }

    //Get the full path of the destination file
    const dest_name_path = try std.fs.path.resolve(allocator, &.{ dir_name, dest_name });
    defer allocator.free(dest_name_path);

    //Open the output file for writing
    const output_file = try std.fs.createFileAbsolute(dest_name_path, .{});
    defer output_file.close();

    //Get the writer for the output file
    var writer = output_file.writer();

    //Write the path of the music file
    try std.fmt.format(writer, "@{s}\n", .{stripNewline(try reader.readUntilDelimiterOrEof(&buf, '\n') orelse return error.UnexpectedEOF)});

    //Iterate over every line in the file
    loop: while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |raw_line| {
        const line = stripNewline(raw_line);

        //If the line is blank, skip it
        if (line.len == 0) {
            continue;
        }

        switch (line[0]) {
            'e' => {
                //Break out of the loop
                break :loop;
            },
            '#' => {
                //Skip hashtags
            },
            '@' => {
                try processCommand(line[1..], &info);
            },
            '\'' => {
                var iter = std.mem.tokenizeAny(u8, line[1..], " \t\n");

                while (iter.next()) |lyric| {
                    try lyrics_array.append(try allocator.dupe(u8, lyric));
                }
            },
            '"' => {
                var iter = std.mem.tokenizeAny(u8, line[1..], "\t\n");

                while (iter.next()) |lyric_kanji| {
                    try kanji_lyircs_array.append(try allocator.dupe(u8, lyric_kanji));
                }
            },
            else => {
                var i: usize = 0;
                while (i < line.len) : (i += 1) {
                    const char = line[i];

                    switch (char) {
                        //Start of command
                        '[' => {
                            const si = i;

                            while (line[i] != ']') {
                                i += 1;

                                //If we have reached the end of the line, there was no `]`, so throw an error
                                if (i == line.len) {
                                    return error.MissingEndBracket;
                                }
                            }

                            try processCommand(line[si + 1 .. i], &info);
                        },
                        ']' => {
                            return error.UnexpectedEndBracket;
                        },
                        //Start of base half
                        '{' => {
                            if (info.base_half) {
                                return error.UnexpectedBaseHalfStart;
                            }

                            if (info.base.items.len > 1) {
                                return error.UnexpectedBaseHalfStart;
                            }

                            info.base_half = true;
                        },
                        //End of base half
                        '}' => {
                            if (!info.base_half) {
                                return error.UnexpectedBaseHalfEnd;
                            }

                            info.base_half = false;
                        },
                        '*' => { //separator, lyric, and kanji lyric
                            try time_array.append(.{ info.time, .separator });
                            try time_array.append(.{ info.time, .lyirc_and_kanji_lyric });
                            try timeAdd(&info, &time_array);
                        },
                        '%' => { //separator + kanji lyric
                            try time_array.append(.{ info.time, .separator });
                            try time_array.append(.{ info.time, .kanji_lyric });
                            try timeAdd(&info, &time_array);
                        },
                        '+' => { //lyric
                            try time_array.append(.{ info.time, .lyric });
                            try timeAdd(&info, &time_array);
                        },
                        '-' => { //blank space
                            try timeAdd(&info, &time_array);
                        },
                        '/' => { //separator
                            try time_array.append(.{ info.time, .separator });
                            try timeAdd(&info, &time_array);
                        },
                        else => {
                            //If we encounter a non-whitespace character, then throw a warning, else, ignore
                            if (!std.ascii.isWhitespace(char)) {
                                std.debug.print("UNHANDLED CHAR '{c}'\n", .{char});
                            }
                        },
                    }
                }
            },
        }
    }

    try time_array.append(.{ info.time, .separator });

    var lyric_itr = SliceIterator([]const u8).new(lyrics_array.items);
    var kanji_lyric_itr = SliceIterator([]const u8).new(kanji_lyircs_array.items);

    var flag = true;
    for (time_array.items) |item| {
        switch (item[1]) {
            .separator => {
                if (!flag) {
                    try std.fmt.format(writer, "/{d}\n", .{item[0]});
                }

                flag = true;
            },
            .lyric => {
                try std.fmt.format(writer, "+{d} {s}\n", .{ item[0], lyric_itr.next() orelse unreachable });
            },
            .kanji_lyric => {
                try std.fmt.format(writer, "*{d} {s}\n", .{ item[0], kanji_lyric_itr.next() orelse unreachable });
                flag = false;
            },
            .lyirc_and_kanji_lyric => {
                try std.fmt.format(writer, "*{d} {s}\n", .{ item[0], kanji_lyric_itr.next() orelse unreachable });
                try std.fmt.format(writer, "+{d} {s}\n", .{ item[0], lyric_itr.next() orelse unreachable });
                flag = false;
            },
            .beat_line => {
                try std.fmt.format(writer, "-{d}\n", .{item[0]});
            },
            .bar_line => {
                try std.fmt.format(writer, "={d}\n", .{item[0]});
            },
        }
    }
}

fn timeAdd(info: *Info, time_array: *TimeArray) !void {
    if (info.speed <= 0) {
        return error.InvalidSpeed;
    }

    if (info.base.items.len == 0) {
        return error.InvalidBase;
    }

    var length = 1 / @as(f64, @floatFromInt(info.base.items[info.base_pos]));
    info.base_pos += 1;
    info.base_pos %= info.base.items.len;

    if (info.base_half) {
        length /= 2;
    }

    var d_time = length * info.speed;

    if (info.beat_de > 0) {
        var d_beat = length * @as(f64, @floatFromInt(info.beat_de));

        while (info.beat_frac + d_beat > -0.001) {
            try time_array.append(.{
                info.time - info.speed * (info.beat_frac / @as(f64, @floatFromInt(info.beat_de))),
                if (info.beat_int == 0) ItemType.bar_line else ItemType.beat_line,
            });

            info.time += info.speed / @as(f64, @floatFromInt(info.beat_de));
            d_time -= info.speed / @as(f64, @floatFromInt(info.beat_de));

            info.beat_int += 1;

            info.beat_int %= info.beat_nu;
            d_beat -= 1;
        }
        info.beat_frac += d_beat;
    }
    info.time += d_time;
}

fn processCommand(cmd: []const u8, info: *Info) !void {
    switch (cmd[0]) {
        't' => {
            try setSpeed(info, cmd[1..]);
        },
        'b', 'l' => {
            try setBase(info, cmd[1..]);
        },
        'B' => {
            try setBeat(info, cmd[1..]);
        },
        'r' => {
            //Increment the time in the info by the amount specified in the rest command
            info.time += try std.fmt.parseFloat(f64, cmd[1..]);
        },
        else => {
            std.debug.print("UNHANDLED COMMAND {s}\n", .{cmd});
        },
    }
}

fn setSpeed(info: *Info, speed: []const u8) !void {
    var iter = std.mem.tokenizeAny(u8, speed, "= \t\n");

    var k: f64 = @floatFromInt(try std.fmt.parseInt(usize, iter.next() orelse return error.MissingTimeSignature, 0));
    var t = try std.fmt.parseFloat(f64, iter.next() orelse return error.MissingBPM);

    if (k <= 0) return error.InvalidTimeSignature;
    if (t <= 0) return error.InvalidBPM;

    info.speed = 60 / (t / k);
}

fn setBase(info: *Info, base: []const u8) !void {
    info.base.clearRetainingCapacity();

    var iter = std.mem.tokenizeAny(u8, base, ", \t\n");
    while (iter.next()) |item| {
        var k = try std.fmt.parseInt(usize, item, 0);

        if (k <= 0) {
            return error.InvalidBaseValue;
        }

        try info.base.append(k);
    }

    if (info.base.items.len == 0) {
        return error.EmptyBase;
    }
}

fn setBeat(info: *Info, beat: []const u8) !void {
    var iter = std.mem.tokenizeAny(u8, beat, ":/ \t\n");

    var nu = try std.fmt.parseInt(usize, iter.next() orelse return error.MissingBeatNu, 0);

    //Specifying zero cancells the time signature
    if (nu == 0) {
        info.beat_nu = 0;
        info.beat_de = 0;
        info.beat_frac = 0;
        info.beat_int = 0;
    }

    var de = try std.fmt.parseInt(usize, iter.next() orelse return error.MissingBeatDe, 0);

    if (de == 0) {
        return error.InvalidDe;
    }

    if (iter.next()) |d_str| {
        var d = try std.fmt.parseFloat(f64, d_str);

        //The integer part of the beat
        info.beat_int = @intFromFloat(@ceil(d));
        //The float part of the beat
        info.beat_frac = d - @as(f64, @floatFromInt(info.beat_int));
    } else {
        //If you dont set the position, its on beat 0
        info.beat_frac = 0;
        info.beat_int = 0;
    }

    info.beat_de = de;
    info.beat_nu = nu;

    info.beat_int %= info.beat_nu;
}
