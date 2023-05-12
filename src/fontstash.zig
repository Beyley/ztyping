const std = @import("std");

const c = @import("main.zig").c;

const Gfx = @import("gfx.zig");
const Renderer = @import("renderer.zig");

const Self = @This();

gfx: *Gfx,
renderer: Renderer,
context: *c.FONScontext,
gothic: c_int,
mincho: c_int,
texture: ?Gfx.Texture = null,
allocator: std.mem.Allocator,
font_size: f32 = 0,

pub fn init(self: *Self, gfx: *Gfx, allocator: std.mem.Allocator) !void {
    self.allocator = allocator;
    self.gfx = gfx;

    var params = c.FONSparams{
        .renderCreate = create,
        .renderDelete = delete,
        .renderDraw = draw,
        .renderResize = resize,
        .renderUpdate = update,
        .width = 4096,
        .height = 4096,
        .flags = c.FONS_ZERO_TOPLEFT,
        .userPtr = self,
    };

    self.context = c.fonsCreateInternal(&params) orelse return error.UnableToCreateFontStashContext;

    self.renderer = try Renderer.init(allocator, gfx.*, self.texture.?);

    var gothic_data = @embedFile("fonts/gothic.ttf");
    var mincho_data = @embedFile("fonts/mincho.ttf");

    self.gothic = c.fonsAddFontMem(self.context, "gothic", gothic_data.ptr, @intCast(c_int, gothic_data.len), 0);
    if (self.gothic == c.FONS_INVALID) return error.UnableToAddFont;

    self.mincho = c.fonsAddFontMem(self.context, "mincho", mincho_data.ptr, @intCast(c_int, mincho_data.len), 0);
    if (self.mincho == c.FONS_INVALID) return error.UnableToAddFont;
}

pub fn setGothic(self: *Self) void {
    c.fonsSetFont(self.context, self.gothic);
}

pub fn setMincho(self: *Self) void {
    c.fonsSetFont(self.context, self.mincho);
}

pub fn setSizePt(self: *Self, size: f32) void {
    self.setSizePx(size / (4.0 / 3.0));
}

pub fn setSizePx(self: *Self, size: f32) void {
    self.font_size = size;
    c.fonsSetSize(self.context, size);
}

pub fn setColor(self: *Self, color: Gfx.ColorB) void {
    c.fonsSetColor(self.context, @bitCast(c_uint, color));
}

pub const Alignment = enum(c_int) {
    left = 1,
    center = 2,
    right = 4,
    top = 8,
    middle = 16,
    bottom = 32,
    baseline = 64,
};

pub fn setAlign(self: *Self, alignment: Alignment) void {
    c.fonsSetAlign(self.context, @enumToInt(alignment));
}

pub fn reset(self: *Self) void {
    c.fonsClearState(self.context);
}

pub fn verticalMetrics(self: *Self) struct { ascender: f32, descender: f32, line_height: f32 } {
    var ascender: f32 = 0;
    var descender: f32 = 0;
    var line_height: f32 = 0;
    c.fonsVertMetrics(self.context, &ascender, &descender, &line_height);

    return .{
        .ascender = ascender,
        .descender = descender,
        //NOTE: fontstash seems to give us double the line height that is correct,
        //      so lets just divide by 2 to get an actually useful number...
        .line_height = line_height / 2,
    };
}

pub fn drawText(self: *Self, position: Gfx.Vector2, text: [:0]const u8) void {
    _ = c.fonsDrawText(self.context, position[0], position[1], text.ptr, null);
}

pub fn deinit(self: *Self) void {
    c.fonsDeleteInternal(self.context);
}

fn toSelf(ptr: *anyopaque) *Self {
    return @ptrCast(*Self, @alignCast(@alignOf(Self), ptr));
}

fn create(self_ptr: ?*anyopaque, width: c_int, height: c_int) callconv(.C) c_int {
    var self = toSelf(self_ptr.?);

    self.texture = self.gfx.device.createBlankTexture(@intCast(u32, width), @intCast(u32, height)) catch {
        // return 0;
        @panic("Unable to create texture!");
    };

    self.texture.?.createBindGroup(self.gfx.device, self.gfx.sampler, self.gfx.bind_group_layouts) catch {
        @panic("Unable to create bind group texture");
    };

    return 1;
}

fn resize(self_ptr: ?*anyopaque, width: c_int, height: c_int) callconv(.C) c_int {
    var self = toSelf(self_ptr.?);

    //If the texture exists,
    if (self.texture) |_| {
        //Free it
        self.texture.?.deinit();
    }

    self.texture = self.gfx.device.createBlankTexture(@intCast(u32, width), @intCast(u32, height)) catch {
        @panic("Unable to create texture!");
        // return 0;
    };

    return 1;
}

fn update(self_ptr: ?*anyopaque, rect: [*c]c_int, data: [*c]const u8) callconv(.C) void {
    var self = toSelf(self_ptr.?);

    var rect_x = @intCast(usize, rect[0]);
    var rect_y = @intCast(usize, rect[1]);
    _ = rect_y;
    var w = @intCast(usize, rect[2] - rect[0]);
    var h = @intCast(usize, rect[3] - rect[1]);

    var full = self.allocator.alloc(Gfx.ColorB, @intCast(usize, w * h)) catch {
        @panic("Unable to allocate for pixel   w i d e n i n g");
    };
    defer self.allocator.free(full);

    //TODO: can we SIMD this?
    // for (0..w * h) |i| {
    //     full[i] = .{ 255, 255, 255, data[i] };
    // }

    for (0..h) |y| {
        for (0..w) |x| {
            full[y * w + x] = .{ 255, 255, 255, data[y * self.texture.?.width + x + rect_x] };
        }
    }

    std.debug.print("updating texture...\n", .{});

    self.gfx.queue.writeTexture(
        self.texture.?,
        Gfx.ColorB,
        full,
        c.WGPUOrigin3D{
            .x = @intCast(u32, rect[0]),
            .y = @intCast(u32, rect[1]),
            .z = 0,
        },
        c.WGPUExtent3D{
            .width = @intCast(u32, w),
            .height = @intCast(u32, h),
            .depthOrArrayLayers = 1,
        },
    );
}

fn draw(self_ptr: ?*anyopaque, verts: [*c]const f32, tcoords: [*c]const f32, colors: [*c]const c_uint, nverts: c_int) callconv(.C) void {
    var self = toSelf(self_ptr.?);

    var reserved = self.renderer.reserve(@intCast(u64, nverts), @intCast(u64, nverts)) catch {
        @panic("Unable to reserve data from renderer");
    };

    for (0..@intCast(usize, nverts)) |i| {
        reserved.vtx[i] = Gfx.Vertex{
            .position = .{ verts[i * 2], verts[i * 2 + 1] },
            .tex_coord = .{ tcoords[i * 2], tcoords[i * 2 + 1] },
            .vertex_col = Gfx.colorBToF(@bitCast(Gfx.ColorB, colors[i])),
        };

        reserved.idx[@intCast(usize, i)] = @intCast(u16, i + reserved.idx_offset);
    }
}

fn delete(self_ptr: ?*anyopaque) callconv(.C) void {
    var self = toSelf(self_ptr.?);

    if (self.texture != null) {
        self.texture.?.deinit();
    }

    self.renderer.deinit();
}
