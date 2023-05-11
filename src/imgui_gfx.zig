const std = @import("std");
const zmath = @import("zmath");

const c = @import("main.zig").c;

const Gfx = @import("gfx.zig");

const RenderResources = struct {
    font_texture: Gfx.Texture,
    sampler: c.WGPUSampler,
    buffer: Gfx.Buffer,
    bind_group: Gfx.BindGroup,
    image_bind_groups: c.ImGuiStorage,
    image_bind_group: Gfx.BindGroup,
    image_bind_group_layout: Gfx.BindGroupLayout,
};

const FrameResources = struct {
    index_buffer: Gfx.Buffer,
    vertex_buffer: Gfx.Buffer,
    index_buffer_host: [*]c.ImDrawIdx,
    vertex_buffer_host: [*]c.ImDrawVert,
    index_buffer_size: u64,
    vertex_buffer_size: u64,
};

const Uniforms = struct {
    mvp: zmath.Mat,
    gamma: f32,
};

const WGPUData = struct {
    device: Gfx.Device,
    queue: Gfx.Queue,
    render_target_format: c.WGPUTextureFormat = c.WGPUTextureFormat_Undefined,
    depth_stencil_format: c.WGPUTextureFormat = c.WGPUTextureFormat_Undefined,
    pipeline_state: Gfx.RenderPipeline,
};
