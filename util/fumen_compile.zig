const std = @import("std");
const clap = @import("clap");

const SliceIterator = @import("slice_iterator.zig").SliceIterator;

const io = std.io;

const param_str =
    \\-h, --help    Display this help and exit
    \\<str>...  File path
;

const Info = struct {
    ///The speed of the song, based on tempo
    speed: f64,
    ///The list of bases we are going to be using
    base: std.ArrayList(usize),
    ///Which base value we are going to use next
    base_pos: usize,
    ///Whether to half the time between some notes
    base_half: bool,
    ///The current time of the fumen
    time: f64,
    ///Every nth beat line becomes a bar line
    beat_numerator: usize,
    ///How many beat lines there are per full "speed" amount
    beat_denominator: usize,
    beat_int: usize,
    beat_frac: f64,
};

fn stripNewline(line: []u8) []u8 {
    if (line.len == 0) {
        return line;
    }
    return if (line[line.len - 1] == '\r') line[0 .. line.len - 1] else line;
}

const ItemType = enum {
    ///0
    typing_cutoff,
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
        .beat_numerator = 0,
        .beat_denominator = 0,
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
    var buffered_writer = std.io.bufferedWriter(output_file.writer());
    var writer = buffered_writer.writer();

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
            //Marks the end of the map
            'e' => {
                //Break out of the loop
                break :loop;
            },
            //Comment
            '#' => {
                //Skip lines which start with hashtags
            },
            //Just a command to process (legacy/undocumented?)
            '@' => {
                //Process a command
                try processCommand(line[1..], &info);
            },
            //Set of lyrics
            '\'' => {
                //Tokenize the line to split up all the lyrics
                var iter = std.mem.tokenizeAny(u8, line[1..], " \t");

                //Iterate over all lyrics
                while (iter.next()) |lyric| {
                    //Append the lyrics to the array
                    try lyrics_array.append(try allocator.dupe(u8, lyric));
                }
            },
            //Kanji lyric
            '"' => {
                try kanji_lyircs_array.append(try allocator.dupe(u8, line[1..]));
            },
            //If its anything else, we need special handling
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
                        //End of command, invalid as it should be handled by the start of command handler
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
                        //Part of the timing information, contains a typing cutoff, then both a hiragana and kanji lyric
                        '*' => {
                            try time_array.append(.{ info.time, .typing_cutoff });
                            try time_array.append(.{ info.time, .lyirc_and_kanji_lyric });
                            try timeAdd(&info, &time_array);
                        },
                        //Part of the timing information, contains a typing cutoff, then a kanji lyric
                        '%' => {
                            try time_array.append(.{ info.time, .typing_cutoff });
                            try time_array.append(.{ info.time, .kanji_lyric });
                            try timeAdd(&info, &time_array);
                        },
                        //Part of the timing information, only a lyric
                        '+' => {
                            try time_array.append(.{ info.time, .lyric });
                            try timeAdd(&info, &time_array);
                        },
                        //Part of the timing information, indicates nothing at this time
                        '-' => {
                            try timeAdd(&info, &time_array);
                        },
                        //Part of the timing information, indicates a typing cutoff
                        '/' => {
                            try time_array.append(.{ info.time, .typing_cutoff });
                            try timeAdd(&info, &time_array);
                        },
                        //Other character handling
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

    //Append a typing cutoff after the end of the song
    try time_array.append(.{ info.time, .typing_cutoff });

    //Create an iterator over the lyrics and kanji lyrics arrays
    var lyric_itr = SliceIterator([]const u8).new(lyrics_array.items);
    var kanji_lyric_itr = SliceIterator([]const u8).new(kanji_lyircs_array.items);

    //Flag for whether or not to write a typing cutoff, so we dont write unnessesary cutoffs
    var skip_typing_cutoff = true;
    for (time_array.items) |item| {
        switch (item[1]) {
            .typing_cutoff => {
                //If we should not skip a typing cutoff, write a typing cutoff
                if (!skip_typing_cutoff) {
                    try std.fmt.format(writer, "/{d}\n", .{item[0]});
                }

                //Mark to skip all next typing cutoffs
                skip_typing_cutoff = true;
            },
            //Gameplay lyric
            .lyric => {
                try std.fmt.format(writer, "+{d} {s}\n", .{ item[0], lyric_itr.next() orelse unreachable });
                //Mark that a note has happened, so a typing cutoff can happen again
                skip_typing_cutoff = false;
            },
            //Kanji lyric
            .kanji_lyric => {
                try std.fmt.format(writer, "*{d} {s}\n", .{ item[0], kanji_lyric_itr.next() orelse unreachable });
                //Mark that a kanji lyric has happened, so a typing cutoff can happen again,
                //Note that this is used to end kanji lyrics, alongside stopping you from typing a note
                skip_typing_cutoff = false;
            },
            //Both gameplay lyric and kanji lyric
            .lyirc_and_kanji_lyric => {
                try std.fmt.format(writer, "*{d} {s}\n", .{ item[0], kanji_lyric_itr.next() orelse unreachable });
                try std.fmt.format(writer, "+{d} {s}\n", .{ item[0], lyric_itr.next() orelse unreachable });
                //Mark that a lyric has happened, so a typing cutoff can happen again
                skip_typing_cutoff = false;
            },
            //Beat line
            .beat_line => {
                try std.fmt.format(writer, "-{d}\n", .{item[0]});
            },
            //Bar line
            .bar_line => {
                try std.fmt.format(writer, "={d}\n", .{item[0]});
            },
        }
    }

    //Flush the buffered writer
    try buffered_writer.flush();
}

///Adds the amount of time of one note to the global time counter
fn timeAdd(info: *Info, time_array: *TimeArray) !void {
    //If the speed is negative,
    if (info.speed <= 0) {
        //Something has gone wrong
        return error.InvalidSpeed;
    }

    //If there are no bases,
    if (info.base.items.len == 0) {
        //Something has gone wrong
        return error.MissingBaseValue;
    }

    //Get the time length of the current base
    var length = 1 / @as(f64, @floatFromInt(info.base.items[info.base_pos]));
    //Increment the current base we are working on
    info.base_pos += 1;
    //Once we reach the end of the base, reset it
    info.base_pos %= info.base.items.len;

    //Halve the base length if required
    if (info.base_half) {
        length /= 2;
    }

    //Get the time of each note by multiplying it by speed
    var d_time = length * info.speed;

    //If the beat denominator is specified
    if (info.beat_denominator > 0) {
        //Multiply the beat length by the denominator, this specifies how many beats per bar there are
        var d_beat = length * @as(f64, @floatFromInt(info.beat_denominator));

        while (info.beat_frac + d_beat > -0.001) {
            try time_array.append(.{
                info.time - info.speed * (info.beat_frac / @as(f64, @floatFromInt(info.beat_denominator))),
                if (info.beat_int == 0) ItemType.bar_line else ItemType.beat_line,
            });

            info.time += info.speed / @as(f64, @floatFromInt(info.beat_denominator));
            d_time -= info.speed / @as(f64, @floatFromInt(info.beat_denominator));

            info.beat_int += 1;

            info.beat_int %= info.beat_numerator;
            d_beat -= 1;
        }
        info.beat_frac += d_beat;
    }
    info.time += d_time;
}

///Processes a command sent to the compiler, which effects the current state
fn processCommand(cmd: []const u8, info: *Info) !void {
    switch (cmd[0]) {
        //Sets the tempo
        't' => {
            try setSpeed(info, cmd[1..]);
        },
        //Sets the base of the following lyrics
        'b', 'l' => {
            try setBase(info, cmd[1..]);
        },
        //Sets the time signature
        'B' => {
            try setTimeSignature(info, cmd[1..]);
        },
        //A rest for some amount of time
        'r' => {
            //Increment the time counter by the amount specified in the command
            info.time += try std.fmt.parseFloat(f64, cmd[1..]);
        },
        //Unhandled command, lets print a warning
        else => {
            std.debug.print("UNHANDLED COMMAND {s}\n", .{cmd});
        },
    }
}

///Sets the speed of the song, in the format of `d=bpm` where BPM gets divided by divisor, then converted to seconds per beat
fn setSpeed(info: *Info, speed: []const u8) !void {
    var iter = std.mem.tokenizeAny(u8, speed, "= \t\n");

    //Parse out the BPM and BPM divisor
    var bpm_divsor: f64 = @floatFromInt(try std.fmt.parseInt(usize, iter.next() orelse return error.MissingTimeSignature, 0));
    var bpm = try std.fmt.parseFloat(f64, iter.next() orelse return error.MissingBPM);

    //Validate BPM and BPM divisor are within valid ranges
    if (bpm_divsor <= 0) return error.InvalidTimeSignature;
    if (bpm <= 0) return error.InvalidBPM;

    //Sets the speed to the tempo in miliseconds, with the BPM divided by the divisor
    info.speed = 60 / (bpm / bpm_divsor);
}

///Sets the base of the notes, aka the length of time between each note in the source file, as a divisor of BPM
fn setBase(info: *Info, base: []const u8) !void {
    //Clear the current base array
    info.base.clearRetainingCapacity();

    //Tokenize the base string
    var iter = std.mem.tokenizeAny(u8, base, ", \t\n");
    //Every token
    while (iter.next()) |item| {
        //Parse the base from the token
        var base_value = try std.fmt.parseInt(usize, item, 0);

        //Verify the value is valid
        if (base_value <= 0) {
            return error.InvalidBaseValue;
        }

        //Append the base value to the list of base values
        try info.base.append(base_value);
    }

    //If there are no base values,
    if (info.base.items.len == 0) {
        //Something has gone wrong
        return error.EmptyBase;
    }
}

///Sets the time signature of the following notes
fn setTimeSignature(info: *Info, beat: []const u8) !void {
    //Tokenize the time signature
    var iter = std.mem.tokenizeAny(u8, beat, ":/ \t\n");

    //Parse out the numerator
    info.beat_numerator = try std.fmt.parseInt(usize, iter.next() orelse return error.MissingBeatNu, 0);

    //Specifying zero cancells the time signature
    if (info.beat_numerator == 0) {
        info.beat_numerator = 0;
        info.beat_denominator = 0;
        info.beat_frac = 0;
        info.beat_int = 0;
        return;
    }

    //Parse out the denominator
    info.beat_denominator = try std.fmt.parseInt(usize, iter.next() orelse return error.MissingBeatDe, 0);

    //Validate the beat denominator
    if (info.beat_denominator == 0) {
        return error.InvalidTimeSignatureDenominator;
    }

    //Get the last item in the time signature command
    if (iter.next()) |d_str| {
        //TODO: what the fuck does this do
        var d = try std.fmt.parseFloat(f64, d_str);

        //The integer part of the beat
        info.beat_int = @intFromFloat(@ceil(d));
        //The float part of the beat
        info.beat_frac = d - @as(f64, @floatFromInt(info.beat_int));
    } else {
        info.beat_frac = 0;
        info.beat_int = 0;
    }

    //Modulo the beat int based on the beat numerator
    info.beat_int %= info.beat_numerator;
}
