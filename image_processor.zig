const std = @import("std");
const img = @import("libs/zigimg/zigimg.zig");

const Image = struct {
    width: u32,
    height: u32,
    image: img.Image,
};

pub fn processImages(step: *std.Build.Step, progress_node: *std.Progress.Node) !void {
    progress_node.setEstimatedTotalItems(1);

    var allocator = step.owner.allocator;

    var images = std.ArrayList(Image).init(allocator);
    defer {
        //Free all the images
        for (0..images.items.len) |i| {
            images.items[i].image.deinit();
        }
        images.deinit();
    }

    var png_files = try find_png_files(allocator, root_path ++ "content/");
    defer allocator.free(png_files);

    for (png_files) |file_path| {
        var file = try std.fs.openFileAbsolute(file_path, .{});
        defer file.close();

        var image_stream: img.Image.Stream = .{ .file = file };

        var image = try img.png.load(&image_stream, allocator, .{ .temp_allocator = allocator });
        try images.append(.{
            .width = @intCast(u32, image.width),
            .height = @intCast(u32, image.height),
            .image = image,
        });
        std.debug.print("found image {s} with size {d}x{d}\n", .{ file_path, image.width, image.height });
    }

    const bin_size = 4096;

    // var start = std.time.nanoTimestamp();
    var packed_images = try packImages(allocator, Image, images.items, .{ .w = bin_size, .h = bin_size });
    defer allocator.free(packed_images);
    // var end = std.time.nanoTimestamp();
    // std.debug.print("took {d}ms to pack\n", .{@intToFloat(f64, end - start) / std.time.ns_per_ms});

    var final_image = try img.Image.create(allocator, bin_size, bin_size, .rgba32);
    defer final_image.deinit();

    for (0..final_image.pixels.rgba32.len) |i| {
        final_image.pixels.rgba32[i] = .{
            .r = 0,
            .g = 0,
            .b = 0,
            .a = 0,
        };
    }

    var output_file = try std.fs.createFileAbsolute(root_path ++ "src/content/atlas.qoi", .{});
    defer output_file.close();

    var output_stream = .{ .file = output_file };

    try img.qoi.QOI.writeImage(allocator, &output_stream, final_image, .{ .qoi = .{} });
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

fn root() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

const root_path = root() ++ "/";
