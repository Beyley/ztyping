const std = @import("std");

const c = @import("main.zig").c;

const Gfx = @import("gfx.zig");

const Self = @This();

const RenderBuffer = struct {
    vtx_buf: Gfx.Buffer,
    idx_buf: Gfx.Buffer,
    used_vtx: u64 = 0,
    used_idx: u64 = 0,
    ///Recording periods that this buffer has been stuck in the queue without being re-used
    recording_periods_since_used: usize = 0,
};

gfx: Gfx,
arena_allocator: std.heap.ArenaAllocator,
allocator: std.mem.Allocator,
///The main texture of the renderer, aka the atlas
texture: Gfx.Texture,
started: bool,
recorded_buffers: std.ArrayList(RenderBuffer),
queued_buffers: std.ArrayList(RenderBuffer),
recording_buffer: ?RenderBuffer = null,
//The in-progress CPU side buffers that get uploaded to the GPU upon a call to dump()
cpu_vtx: []Gfx.Vertex,
cpu_idx: []IndexType,

pub fn init(allocator: std.mem.Allocator, gfx: Gfx, texture: Gfx.Texture) !Self {
    var self: Self = Self{
        .gfx = gfx,
        .started = false,
        .arena_allocator = std.heap.ArenaAllocator.init(allocator),
        .texture = texture,
        .recorded_buffers = undefined,
        .allocator = undefined,
        .queued_buffers = undefined,
        .cpu_vtx = undefined,
        .cpu_idx = undefined,
    };
    self.allocator = self.arena_allocator.allocator();
    self.recorded_buffers = std.ArrayList(RenderBuffer).init(self.allocator);
    self.queued_buffers = std.ArrayList(RenderBuffer).init(self.allocator);
    self.cpu_vtx = try self.allocator.alloc(Gfx.Vertex, vtx_per_buf);
    self.cpu_idx = try self.allocator.alloc(IndexType, vtx_per_buf);

    //I think quad_per_buf * 3 is a good amount of tris for most 2d scenes
    const common_max_capacity = 3;

    try self.recorded_buffers.ensureTotalCapacity(common_max_capacity);
    try self.queued_buffers.ensureTotalCapacity(common_max_capacity);

    try self.createRenderBuffer();

    return self;
}

const quad_per_buf = 5000;
const vtx_per_buf = quad_per_buf * 4;
const idx_per_buf = quad_per_buf * 6;
const IndexType = u16;

fn createRenderBuffer(self: *Self) !void {
    try self.queued_buffers.append(RenderBuffer{
        .vtx_buf = try self.gfx.device.createBuffer(Gfx.Vertex, vtx_per_buf, .vertex),
        .idx_buf = try self.gfx.device.createBuffer(IndexType, idx_per_buf, .index),
    });
}

///Begins recording draw commands
pub fn begin(self: *Self) !void {
    //Ensure we arent started yet
    std.debug.assert(!self.started);
    //Ensure we dont have a current recording buffer
    std.debug.assert(self.recording_buffer == null);

    //Go through all recorded buffers, and set their used counts to 0, resetting them for the next use
    for (0..self.recorded_buffers.items.len) |i| {
        self.recorded_buffers.items[i].used_vtx = 0;
        self.recorded_buffers.items[i].used_idx = 0;
    }

    //Move all recorded buffers into the queued buffers list
    try self.queued_buffers.appendSlice(self.recorded_buffers.items);
    //Clear out the recorded buffer list
    self.recorded_buffers.clearRetainingCapacity();

    //Pop the last item out of the queued buffers, and put it onto the recording buffer
    self.recording_buffer = self.queued_buffers.pop();

    //Mark that we have started recording
    self.started = true;
}

///Ends the recording period, prepares for calling draw()
pub fn end(self: *Self) !void {
    std.debug.assert(self.started);

    try self.dump();

    //TODO: iterate all the unused queued buffers, increment their "time since used" counts,
    //      and dispose ones that have been left for some amount of times

    //Mark that we have finished recording
    self.started = false;
}

///Dumps the current recording buffer to the recorded list, or to the unused list, if empty
///Guarentees that self.recording_buffer == null after the call, caller must reset it in whatever way needed.
fn dump(self: *Self) !void {
    std.debug.assert(self.started);
    std.debug.assert(self.recording_buffer != null);

    if (self.recording_buffer) |recording_buffer| {
        //If it was used,
        if (recording_buffer.used_idx != 0) {
            //Write the CPU buffer to the GPU buffer, slicing only the data we need to write, the rest of the buffer is left untouched
            self.gfx.queue.writeBuffer(recording_buffer.vtx_buf, 0, Gfx.Vertex, self.cpu_vtx[0..recording_buffer.used_vtx]);
            self.gfx.queue.writeBuffer(recording_buffer.idx_buf, 0, IndexType, self.cpu_idx[0..recording_buffer.used_idx]);

            //Add to the recorded buffers
            try self.recorded_buffers.append(recording_buffer);
        } else {
            //Add to the empty queued buffers
            try self.queued_buffers.append(recording_buffer);
        }
    }

    //Mark that there is no recording buffer anymore
    self.recording_buffer = null;
}

pub const ReservedData = struct {
    vtx: []Gfx.Vertex,
    idx: []IndexType,
    idx_offset: u16,

    pub fn copyIn(self: ReservedData, vtx: []const Gfx.Vertex, idx: []const IndexType) void {
        @memcpy(self.vtx, vtx);
        @memcpy(self.idx, idx);
    }
};

pub inline fn reserveTexQuad(self: *Self, comptime tex_name: []const u8, position: Gfx.Vector2, scale: Gfx.Vector2, col: Gfx.ColorF) !void {
    const uvs = Gfx.getTexUVsFromAtlas(tex_name);
    const size = Gfx.getTexSizeFromAtlas(tex_name);

    var reserved = try self.reserve(4, 6);
    reserved.copyIn(&.{
        Gfx.Vertex{
            .position = position,
            .tex_coord = uvs.tl,
            .vertex_col = col,
        },
        Gfx.Vertex{
            .position = position + (Gfx.Vector2{ size[0], 0 } * scale),
            .tex_coord = uvs.tr,
            .vertex_col = col,
        },
        Gfx.Vertex{
            .position = position + (Gfx.Vector2{ 0, size[1] } * scale),
            .tex_coord = uvs.bl,
            .vertex_col = col,
        },
        Gfx.Vertex{
            .position = position + (size * scale),
            .tex_coord = uvs.br,
            .vertex_col = col,
        },
    }, &.{
        0 + reserved.idx_offset,
        2 + reserved.idx_offset,
        1 + reserved.idx_offset,
        1 + reserved.idx_offset,
        2 + reserved.idx_offset,
        3 + reserved.idx_offset,
    });
}

pub fn reserve(self: *Self, vtx_count: u64, idx_count: u64) !ReservedData {
    //Assert that we arent trying to reserve more than the max buffer size
    std.debug.assert(vtx_count < vtx_per_buf);
    std.debug.assert(idx_count < idx_per_buf);
    //Assert that we have a buffer to record to
    std.debug.assert(self.recording_buffer != null);
    //Assert that we have started recording
    std.debug.assert(self.started);

    var recording_buf: RenderBuffer = self.recording_buffer.?;

    //If the vertex count or index count would put us over the limit of the current recording buffer
    if (recording_buf.used_vtx + vtx_count > vtx_per_buf or recording_buf.used_idx + idx_count > idx_per_buf) {
        try self.dump();

        //If theres no more queued buffers,
        if (self.queued_buffers.items.len == 0) {
            //Create a new render buffer
            try self.createRenderBuffer();
        }

        //Pop the latest buffer off the queue
        self.recording_buffer = self.queued_buffers.pop();
    }

    //Increment the recording buffer's counts
    self.recording_buffer.?.used_vtx += vtx_count;
    self.recording_buffer.?.used_idx += idx_count;

    //Return the 2 slices of data
    return .{
        .vtx = self.cpu_vtx[self.recording_buffer.?.used_vtx - vtx_count .. self.recording_buffer.?.used_vtx],
        .idx = self.cpu_idx[self.recording_buffer.?.used_idx - idx_count .. self.recording_buffer.?.used_idx],
        .idx_offset = @intCast(u16, self.recording_buffer.?.used_vtx - vtx_count),
    };
}

pub fn draw(self: *Self, encoder: *Gfx.RenderPassEncoder) !void {
    //We should never be started
    std.debug.assert(!self.started);

    //Set the pipeline
    encoder.setPipeline(self.gfx.render_pipeline);
    encoder.setBindGroup(0, self.gfx.projection_matrix_bind_group, &.{});
    encoder.setBindGroup(1, self.texture.bind_group.?, &.{});

    for (self.recorded_buffers.items) |recorded_buffera| {
        var recorded_buffer: RenderBuffer = recorded_buffera;

        encoder.setVertexBuffer(0, recorded_buffer.vtx_buf, 0, recorded_buffer.vtx_buf.size);
        encoder.setIndexBuffer(recorded_buffer.idx_buf, IndexType, 0, recorded_buffer.idx_buf.size);
        encoder.drawIndexed(@intCast(u32, recorded_buffer.used_idx), 1, 0, 0, 0);
    }
}

pub fn deinit(self: *Self) void {
    //TODO: iterate over all recorded and queued buffers, and dispose the GPU objects

    //De-init all the resources
    self.arena_allocator.deinit();
}
