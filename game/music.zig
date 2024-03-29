const std = @import("std");

const Fumen = @import("fumen.zig");
const Ranking = @import("ranking.zig");

const Gfx = @import("gfx.zig");
const Screen = @import("screen.zig");
const Fontstash = @import("fontstash.zig");
const Conv = @import("conv.zig");

const Self = @This();

title: []const u8,
artist: []const u8,
author: []const u8,
level: u3,
fumen_file_name: []const u8,
ranking_file_name: []const u8,
comment: []const []const u8,
folder_path: []const u8,
///The index assigned at load time for the song, used for "no sort" option, to return to original order
sort_idx: usize,

fumen: *Fumen,
ranking: Ranking,

allocator: std.mem.Allocator,

pub fn deinit(self: *Self) void {
    self.allocator.free(self.title);
    self.allocator.free(self.artist);
    self.allocator.free(self.author);
    self.allocator.free(self.fumen_file_name);
    self.allocator.free(self.ranking_file_name);
    self.allocator.free(self.folder_path);

    for (self.comment) |comment| {
        self.allocator.free(comment);
    }

    self.allocator.free(self.comment);

    self.fumen.deinit();
    self.allocator.destroy(self.fumen);

    self.* = undefined;
}

pub fn readFromFile(conv: Conv, allocator: std.mem.Allocator, path: std.fs.Dir, file: std.fs.File, sort_idx: usize) !Self {
    var self: Self = undefined;
    self.sort_idx = sort_idx;
    self.allocator = allocator;

    var comments = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (comments.items) |comment| {
            allocator.free(comment);
        }
        comments.deinit();
    }

    //Set to 12 to match COMMENT_N_LINES in UTyping.cpp
    try comments.ensureTotalCapacity(12);

    var title: ?[]const u8 = null;
    var artist: ?[]const u8 = null;
    var author: ?[]const u8 = null;
    var fumen_file_name: ?[]const u8 = null;
    var ranking_file_name: ?[]const u8 = null;

    errdefer if (title) |title_ptr| allocator.free(title_ptr);
    errdefer if (artist) |artist_ptr| allocator.free(artist_ptr);
    errdefer if (author) |author_ptr| allocator.free(author_ptr);
    errdefer if (fumen_file_name) |fumen_file_name_ptr| allocator.free(fumen_file_name_ptr);
    errdefer if (ranking_file_name) |ranking_file_name_ptr| allocator.free(ranking_file_name_ptr);

    const orig_file = try file.readToEndAlloc(allocator, 10000);
    defer allocator.free(orig_file);

    var read_file = std.ArrayList(u8).init(allocator);
    defer read_file.deinit();
    try conv.sjisToUtf8(orig_file, read_file.writer());

    var iter = std.mem.split(u8, read_file.items, "\n");

    var i: usize = 0;
    while (iter.next()) |orig_line| {
        //Skip blank lines
        if (orig_line.len == 0) continue;

        var line = if (orig_line[orig_line.len - 1] == '\r') orig_line[0 .. orig_line.len - 1] else orig_line;

        //If the last char is \r, strip it out
        if (line.len > 0 and line[line.len - 1] == '\r') {
            line = line[0..(line.len - 1)];
        }

        if (i == 0) {
            title = try allocator.dupe(u8, line);
        } else if (i == 1) {
            artist = try allocator.dupe(u8, line);
        } else if (i == 2) {
            author = try allocator.dupe(u8, line);
        } else if (i == 3) {
            self.level = try std.fmt.parseUnsigned(u3, line, 10);

            //While i dont like this behaviour, it matches UTyping
            if (self.level == 0) {
                return error.MusicInvalidLevel;
            }
        } else if (i == 4) {
            fumen_file_name = try allocator.dupe(u8, line);
        } else if (i == 5) {
            ranking_file_name = try allocator.dupe(u8, line);
        } else {
            try comments.append(try allocator.dupe(u8, line));
        }

        i += 1;
    }

    self.title = title.?;
    self.artist = artist.?;
    self.author = author.?;
    self.fumen_file_name = fumen_file_name.?;
    self.ranking_file_name = ranking_file_name.?;

    //i hate the look of this so much
    errdefer {
        for (self.comment) |comment| {
            allocator.free(comment);
        }

        allocator.free(self.comment);
    }

    self.comment = try comments.toOwnedSlice();

    self.folder_path = try path.realpathAlloc(allocator, ".");
    errdefer allocator.free(self.folder_path);

    const fumen_path = try path.realpathAlloc(allocator, self.fumen_file_name);
    defer allocator.free(fumen_path);

    var fumen_file = try std.fs.openFileAbsolute(fumen_path, .{});
    defer fumen_file.close();

    self.fumen = try allocator.create(Fumen);
    errdefer allocator.destroy(self.fumen);
    self.fumen.* = try Fumen.readFromFile(conv, allocator, fumen_file, path);
    errdefer self.fumen.deinit();

    const ranking_path = path.realpathAlloc(allocator, self.ranking_file_name) catch |err| blk: {
        //If we got a FileNotFound error, write out a new blank ranking file
        if (err == std.fs.Dir.OpenError.FileNotFound) {
            const ranking = Ranking.init();

            var new_ranking_file = try path.createFile(self.ranking_file_name, .{});

            try ranking.writeRanking(new_ranking_file.writer());

            new_ranking_file.close();

            break :blk try path.realpathAlloc(allocator, self.ranking_file_name);
        } else {
            return err;
        }
    };
    defer allocator.free(ranking_path);

    var ranking_file = try std.fs.openFileAbsolute(ranking_path, .{});
    defer ranking_file.close();

    self.ranking = try Ranking.readRanking(ranking_file);
    errdefer self.ranking.deinit();

    return self;
}

pub fn readUTypingList(conv: Conv, allocator: std.mem.Allocator) ![]Self {
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

    var i: usize = 0;
    while (true) {
        var line = try reader.readUntilDelimiterOrEofAlloc(allocator, '\n', 100) orelse break;
        defer allocator.free(line);

        //Normalize, aka remove \r and change `\` to `/`
        const normalized = try std.mem.replaceOwned(u8, allocator, if (line[line.len - 1] == '\r') line[0 .. line.len - 1] else line, &.{'\\'}, &.{'/'});
        defer allocator.free(normalized);

        var music_file = try std.fs.cwd().openFile(normalized, .{});
        defer music_file.close();

        var music_dir = try std.fs.cwd().openDir(std.fs.path.dirname(normalized) orelse "", .{});
        defer music_dir.close();

        const music = try readFromFile(conv, allocator, music_dir, music_file, i);

        try music_list.append(music);
        i += 1;
    }

    return try music_list.toOwnedSlice();
}

const title_x = 40;
const title_y = (30 - 30 / 2);
const num_x = (Screen.display_width - 25);
const num_y = (60 - 44);
const artist_y = num_y;
const level_x = (Screen.display_width - 270);
const level_y = (60 - 22);
const author_x_f = (Screen.display_width - 30);
const author_y_f = level_y;

const achievement_x = (title_x - 25);
const achievement_y = (30 - 24 / 2);

pub fn draw(
    self: Self,
    render_state: Screen.RenderState,
    y: f32,
    brightness: f32,
    music_idx: usize,
    music_count: usize,
) !void {
    const title_state = Fontstash.Fontstash.State{
        .font = Fontstash.Mincho,
        .size = Fontstash.ptToPx(30),
        .alignment = .{
            .vertical = .top,
        },
    };

    const scaleVec = @as(Gfx.Vector2, @splat(render_state.gfx.scale));

    const color = Gfx.ColorF{ brightness, brightness, brightness, 1 };
    const title_width = (try render_state.fontstash.textBounds(self.title, title_state)).x2;

    const width_num: f32 = blk: { //draw right-aligned text for the index
        var context = Fontstash.Fontstash.WriterContext{
            .draw = false,
            .draw_position = .{ 0, 0 },
            .state = Fontstash.Normal,
        };
        context.state.size *= render_state.gfx.scale;

        var writer = try render_state.fontstash.context.writer(&context);
        try std.fmt.format(writer, "{d}/{d}", .{ music_idx + 1, music_count });
        var bounds = context.bounds;
        //Adjust for resolution
        bounds.br /= @splat(render_state.gfx.scale);
        bounds.tl /= @splat(render_state.gfx.scale);
        context.draw_position = Gfx.Vector2{ num_x - bounds.br[0], num_y + y } * scaleVec;
        context.draw = true;
        context.state.color = color;
        writer = try render_state.fontstash.context.writer(&context);
        try std.fmt.format(writer, "{d}/{d}", .{ music_idx + 1, music_count });
        break :blk bounds.br[0];
    };

    { //artist
        const width = (try render_state.fontstash.textBounds(self.artist, Fontstash.Normal)).x2;
        var x = (Screen.display_width - 150) - width * 2 / 3;

        const width_l = x - (title_x + title_width);
        const width_r = (num_x - width_num) - (x + width);

        if (width_l <= 20 or width_r <= 20) {
            x += (width_r - width_l) / 4;
        }

        if (width_l < 0 or width_l + width_r <= 0) {
            x = title_x + title_width;
        } else if (width_r < 0) {
            x += width_r;
        }

        var state = Fontstash.Normal;
        state.color = color;
        _ = try render_state.fontstash.drawText(.{ x, y + artist_y }, self.artist, state);
    }

    { //fumen author
        var fumen_author_color = color * @as(Gfx.ColorF, @splat(2)) / @as(Gfx.ColorF, @splat(3));
        fumen_author_color[3] = 1;

        var context = Fontstash.Fontstash.WriterContext{
            .draw = false,
            .draw_position = .{ 0, 0 },
            .state = Fontstash.Normal,
        };
        context.state.size *= render_state.gfx.scale;

        var writer = try render_state.fontstash.context.writer(&context);
        try std.fmt.format(writer, "(譜面作成　{s})", .{self.author});
        var bounds = context.bounds;
        //Adjust for resolution
        bounds.br /= @splat(render_state.gfx.scale);
        bounds.tl /= @splat(render_state.gfx.scale);
        context.draw_position = Gfx.Vector2{ author_x_f - bounds.br[0], author_y_f + y } * scaleVec;
        context.draw = true;
        context.state.color = fumen_author_color;
        writer = try render_state.fontstash.context.writer(&context);
        try std.fmt.format(writer, "(譜面作成　{s})", .{self.author});
    }

    { //difficulty
        for (0..5) |i| {
            const star_color = if (self.level <= i) blk: {
                var tmp = color / @as(Gfx.ColorF, @splat(2));
                tmp[3] = 1;
                break :blk tmp;
            } else Gfx.ColorF{ brightness, brightness, 0, 1 };
            const str = if (self.level <= i) "☆" else "★";

            var state = Fontstash.Normal;
            state.color = star_color;
            _ = try render_state.fontstash.drawText(
                .{ level_x + 16 * @as(f32, @floatFromInt(i)), level_y + y },
                str,
                state,
            );
        }
    }

    { //achievement
        //TODO
    }

    var state = title_state;
    state.color = color;
    _ = try render_state.fontstash.drawText(.{ title_x, title_y + y }, self.title, state);
}

pub fn drawComment(self: Self, render_state: Screen.RenderState, pos: Gfx.Vector2) !void {
    for (self.comment, 0..) |comment, i| {
        _ = try render_state.fontstash.drawText(
            Gfx.Vector2{
                30,
                2 + 20 * @as(f32, @floatFromInt(i)),
            } + pos,
            comment,
            Fontstash.Normal,
        );
    }
}

pub fn drawPlayData(self: Self, render_state: Screen.RenderState, pos: Gfx.Vector2) !void {
    _ = self;
    _ = pos;
    _ = render_state;
}
