const std = @import("std");
const img = @import("zigimg");

const Image = struct {
    width: u32,
    height: u32,
    image: img.Image,
    name: []const u8,
    fn pathological_multiplier(self: Image) f32 {
        return @as(f32, @floatFromInt(@max(self.width, self.height))) / @as(f32, @floatFromInt(@min(self.width, self.height))) * @as(f32, @floatFromInt(self.width)) * @as(f32, @floatFromInt(self.height));
    }
    fn sorting_func(context: void, a: Image, b: Image) bool {
        _ = context;
        return a.pathological_multiplier() > b.pathological_multiplier();
    }
};

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    try processImages(allocator, args[1]);
}

pub fn processImages(allocator: std.mem.Allocator, root_path: []const u8) !void {
    var images = std.ArrayList(Image).init(allocator);
    defer {
        //Free all the images
        for (0..images.items.len) |i| {
            images.items[i].image.deinit();
        }
        images.deinit();
    }

    std.debug.assert(std.fs.path.isAbsolute(root_path));

    const content_path = try std.mem.concat(allocator, u8, &.{ root_path, "content/" });
    defer allocator.free(content_path);

    var png_files = try find_png_files(allocator, content_path);
    defer allocator.free(png_files);

    const atlas_gen_folder = try std.mem.concat(allocator, u8, &.{ root_path, "zig-cache/atlas-gen/" });
    defer allocator.free(atlas_gen_folder);

    //ignore errors, just try to make it
    std.fs.makeDirAbsolute(atlas_gen_folder) catch |err| {
        if (err != std.os.MakeDirError.PathAlreadyExists) {
            return err;
        }
    };

    var cache_dir = try std.fs.openDirAbsolute(atlas_gen_folder, .{});
    defer cache_dir.close();

    var hashes: [][]u8 = try allocator.alloc([]u8, png_files.len);
    defer allocator.free(hashes);

    var needs_rebuild: bool = false;
    for (png_files, 0..) |file_path, i| {
        //Open the png file
        var file = try std.fs.openFileAbsolute(file_path, .{});
        defer file.close();

        //Get the length of the PNG file
        var len = try file.getEndPos();

        //allocate a buffer for the file
        var buf = try allocator.alloc(u8, len);
        defer allocator.free(buf);

        //Read the whole file
        _ = try file.readAll(buf);

        //Create an array which will store our hash
        var hash = [std.crypto.hash.sha2.Sha256.digest_length]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };

        //Hash the file
        std.crypto.hash.sha2.Sha256.hash(buf, &hash, .{});

        //Get a hex escaped version of the hash
        var hash_hex = std.ArrayList(u8).init(allocator);
        try std.fmt.format(hash_hex.writer(), "{s}\n", .{std.fmt.fmtSliceHexLower(&hash)});
        //Store the first 8 chars of the hash (too long and windows gets pissy)
        hashes[i] = (try hash_hex.toOwnedSlice())[0..8];

        //Try to open the file which may contain the hash
        var cache_file = cache_dir.openFile(hashes[i], .{});

        //If the file failed to open, then we need to rebuild
        var cach_file_val = cache_file catch {
            needs_rebuild = true;
            continue;
        };

        //Close the file if we make it here
        cach_file_val.close();
    }

    if (!needs_rebuild) {
        return;
    }

    for (png_files, 0..) |file_path, i| {
        //Open the PNG file
        var file = try std.fs.openFileAbsolute(file_path, .{});
        defer file.close();

        var image_stream: img.Image.Stream = .{ .file = file };

        var path_without_root = file_path[root_path.len..];

        var path_without_content = path_without_root["content/".len..];

        var name = path_without_content[0 .. path_without_content.len - 4];

        //Load the file
        var image = try img.png.load(&image_stream, allocator, .{ .temp_allocator = allocator });
        try images.append(.{
            .width = @as(u32, @intCast(image.width)) + 2,
            .height = @as(u32, @intCast(image.height)) + 2,
            .image = image,
            .name = name,
        });
        // std.debug.print("found image {s} with size {d}x{d}\n", .{ file_path, image.width, image.height });

        //Create the cache file if it does not exist
        var cache_file = try cache_dir.createFile(hashes[i], .{});
        cache_file.close();
    }

    std.sort.block(Image, images.items, {}, Image.sorting_func);

    const bin_size = 4096;

    var packed_images = try packImages(allocator, Image, images.items, .{ .w = bin_size, .h = bin_size });
    defer allocator.free(packed_images);

    var final_image = try img.Image.create(allocator, bin_size, bin_size, .rgba32);
    defer final_image.deinit();

    //zero-init the image
    for (0..final_image.pixels.rgba32.len) |i| {
        final_image.pixels.rgba32[i] = .{
            .r = 0,
            .g = 0,
            .b = 0,
            .a = 0,
        };
    }

    for (packed_images) |packed_image| {
        switch (packed_image.image.image.pixels) {
            .rgba32 => |pix| {
                for (0..(packed_image.image.height - 2)) |y| {
                    std.mem.copyForwards(img.color.Rgba32, final_image.pixels.rgba32[((y + 1 + packed_image.pos.y) * final_image.width) + (packed_image.pos.x + 1) ..], pix[y * (packed_image.image.width - 2) .. (y + 1) * (packed_image.image.width - 2)]);
                }
            },
            .rgb24 => |pix| {
                for (0..(packed_image.image.width - 2)) |x| {
                    for (0..(packed_image.image.height - 2)) |y| {
                        var pixel = pix[y * (packed_image.image.width - 2) + x];
                        final_image.pixels.rgba32[(y + 1 + packed_image.pos.y) * final_image.width + packed_image.pos.x + 1 + x] = .{ .r = pixel.r, .g = pixel.g, .b = pixel.b, .a = 255 };
                    }
                }
            },
            else => return error.UnknownImageFormat,
        }
    }

    const output_content_folder = try std.mem.concat(allocator, u8, &.{ root_path, "src/content/" });
    defer allocator.free(output_content_folder);

    const output_atlas_image = try std.mem.concat(allocator, u8, &.{ output_content_folder, "atlas.qoi" });
    defer allocator.free(output_atlas_image);

    const output_atlas_code = try std.mem.concat(allocator, u8, &.{ output_content_folder, "atlas.zig" });
    defer allocator.free(output_atlas_code);

    std.fs.makeDirAbsolute(output_content_folder) catch {};

    var output_file = try std.fs.createFileAbsolute(output_atlas_image, .{});
    defer output_file.close();

    var output_stream = .{ .file = output_file };

    try img.qoi.QOI.writeImage(allocator, &output_stream, final_image, .{ .qoi = .{} });

    var output_atlas_info = try std.fs.createFileAbsolute(output_atlas_code, .{});
    defer output_atlas_info.close();

    try output_atlas_info.writeAll("pub const Rectangle = struct {x: comptime_float, y: comptime_float, w: comptime_float, h: comptime_float};\n\n");

    try output_atlas_info.writeAll(try std.fmt.allocPrint(allocator, "pub const atlas_width: comptime_float = {d};\npub const atlas_height: comptime_float = {d};\n\n", .{ bin_size, bin_size }));

    for (packed_images) |packed_image| {
        var image_rect = try std.fmt.allocPrint(allocator,
            \\pub const {s}: Rectangle = .{{.x = {d}, .y = {d}, .w = {d}, .h = {d}}};
        , .{
            packed_image.image.name,
            packed_image.pos.x + 1,
            packed_image.pos.y + 1,
            packed_image.image.width - 2,
            packed_image.image.height - 2,
        });

        try output_atlas_info.writeAll(image_rect);
        try output_atlas_info.writeAll("\n");
    }
}

///Finds all png files in a folder recursively
///Caller owns returned memory
fn find_png_files(allocator: std.mem.Allocator, search_path: []const u8) ![]const []const u8 {
    var png_list = std.ArrayList([]const u8).init(allocator);

    var dir = try std.fs.openIterableDirAbsolute(search_path, .{});
    defer dir.close();

    var walker: std.fs.IterableDir.Walker = try dir.walk(allocator);
    defer walker.deinit();

    var itr_next: ?std.fs.IterableDir.Walker.WalkerEntry = try walker.next();
    while (itr_next != null) {
        var next: std.fs.IterableDir.Walker.WalkerEntry = itr_next.?;

        //if the file is a png file
        if (std.mem.endsWith(u8, next.path, ".png")) {
            var item = try allocator.alloc(u8, next.path.len + search_path.len);

            //copy the root first
            std.mem.copy(u8, item, search_path);

            //copy the filepath next
            std.mem.copy(u8, item[search_path.len..], next.path);

            try png_list.append(item);
        }

        itr_next = try walker.next();
    }

    return png_list.toOwnedSlice();
}

fn PackedImage(comptime T: type) type {
    return struct {
        image: T,
        pos: struct { x: u32, y: u32 },
    };
}

const EmptySpace = struct {
    x: u32,
    y: u32,
    w: u32,
    h: u32,
};

//Pack the images, caller owns returned memory
pub fn packImages(allocator: std.mem.Allocator, comptime T: type, images: []const T, bin_size: struct { w: u32, h: u32 }) ![]const PackedImage(T) {
    var empty_spaces = std.ArrayList(EmptySpace).init(allocator);
    defer empty_spaces.deinit();
    //lets do a conservative estimate here, each image will at most create 2 empty spaces, so lets assume they will!
    try empty_spaces.ensureTotalCapacity(images.len * 2);

    var packed_images = std.ArrayList(PackedImage(T)).init(allocator);
    try packed_images.ensureTotalCapacity(images.len);

    try empty_spaces.append(.{
        .x = 0,
        .y = 0,
        .w = bin_size.w,
        .h = bin_size.h,
    });

    for (images) |image| {
        var candidate_space_index: ?usize = null;

        //Iterate backwards through all the items
        for (0..empty_spaces.items.len) |j| {
            var i = empty_spaces.items.len - 1 - j;
            var empty_space: EmptySpace = empty_spaces.items[i];

            //If the empty space can fit the image
            if (empty_space.w >= image.width and empty_space.h >= image.height) {
                candidate_space_index = i;
            }
        }

        if (candidate_space_index == null) {
            return error.UnableToFitRect;
        }

        var empty_space: EmptySpace = empty_spaces.items[candidate_space_index.?];

        // std.debug.print("space: {d}/{d}/{d}/{d}\n", .{ empty_space.x, empty_space.y, empty_space.w, empty_space.h });
        try packed_images.append(.{
            .image = image,
            .pos = .{
                .x = empty_space.x,
                .y = empty_space.y,
            },
        });

        //Erase the space we just filled, by swapping the old item with the last element of the array
        empty_spaces.items[candidate_space_index.?] = empty_spaces.pop();

        //If the image is an exact fit, then dont add the splits, just continue on
        if (empty_space.w == image.width and empty_space.h == image.height) {
            continue;
        }
        var rect1: EmptySpace = .{
            .x = empty_space.x + image.width,
            .y = empty_space.y,
            .w = empty_space.w - image.width,
            .h = image.height,
        };
        var rect2: EmptySpace = .{
            .x = empty_space.x,
            .y = empty_space.y + image.height,
            .w = empty_space.w,
            .h = empty_space.h - image.height,
        };

        //If rect1 has less area than rect2, swap the 2 items,
        //since we always want to append the smaller split *last*
        if (rect1.w * rect1.h < rect2.w * rect2.h) {
            // std.debug.print("swapping...\n", .{});
            std.mem.swap(EmptySpace, &rect1, &rect2);
        }

        //Only add the new cut space if it has actual area
        if (rect1.w != 0 and rect1.h != 0) {
            // std.debug.print("adding rect1: {d}/{d}/{d}/{d}\n", .{ rect1.x, rect1.y, rect1.w, rect1.h });

            try empty_spaces.append(rect1);
        }
        if (rect2.w != 0 and rect2.h != 0) {
            // std.debug.print("adding rect2: {d}/{d}/{d}/{d}\n", .{ rect2.x, rect2.y, rect2.w, rect2.h });

            try empty_spaces.append(rect2);
        }
    }

    return packed_images.toOwnedSlice();
}
