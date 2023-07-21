const std = @import("std");
const clap = @import("clap");

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

    var reader = file.reader();

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

    const ItemType = enum {
        separator,
        lyric,
        kanji_lyric,
        lyirc_and_kanji_lyric,
        bar_line,
        beat_line,
    };

    var time_array = std.ArrayList(struct {
        time: f64,
        type: ItemType,
    }).init(allocator);
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
                //TODO: processCommand
                @panic("TODO");
            },
            '\'' => {
                var iter = std.mem.tokenizeAny(u8, line[1..], " \t\n");

                while (iter.next()) |lyric| {
                    try lyrics_array.append(allocator.dupe(u8, lyric));
                }
            },
            '"' => {
                var iter = std.mem.tokenizeAny(u8, line[1..], " \t\n");

                while (iter.next()) |lyric_kanji| {
                    try kanji_lyircs_array.append(allocator.dupe(u8, lyric_kanji));
                }
            },
        }
    }
}
