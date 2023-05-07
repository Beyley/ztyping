const std = @import("std");
const zaudio = @import("zaudio");
const zmath = @import("zmath");
const gfx = @import("gfx.zig");

pub const c = @cImport({
    @cInclude("fontstash.h");
    @cInclude("SDL.h");
    @cInclude("SDL_syswm.h");
    @cInclude("wgpu.h");
    // @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "1");
    // @cInclude("cimgui.h");
});

pub var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;
pub var allocator: std.mem.Allocator = undefined;

pub fn main() !void {
    //Create the allocator to be used in the lifetime of the app
    gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("Memory leak!");
    allocator = gpa.allocator();

    //Initialize zaudio
    zaudio.init(allocator);
    defer zaudio.deinit();

    //Initialize our audio engine
    const engine = try zaudio.Engine.create(null);
    defer engine.destroy();

    //Initialize SDL
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        std.debug.print("SDL init failed! err:{s}\n", .{c.SDL_GetError()});
        return error.InitSdlFailure;
    }
    defer c.SDL_Quit();
    std.debug.print("Initialized SDL\n", .{});

    //Create the window
    const window = c.SDL_CreateWindow("ztyping", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 640, 480, c.SDL_WINDOW_SHOWN | c.SDL_WINDOW_RESIZABLE) orelse {
        std.debug.print("SDL window creation failed! err:{s}\n", .{c.SDL_GetError()});
        return error.CreateWindowFailure;
    };
    defer c.SDL_DestroyWindow(window);
    std.debug.print("Created SDL window\n", .{});

    //Create the webgpu instance
    var instance = try gfx.createInstance();
    defer c.wgpuInstanceDrop(instance);

    //Create the webgpu surface
    var surface = try gfx.createSurface(instance, window);
    defer c.wgpuSurfaceDrop(surface);

    //Request an adapter
    var adapter = try gfx.requestAdapter(instance, surface);
    defer c.wgpuAdapterDrop(adapter);

    //Request a device
    var device = try gfx.requestDevice(adapter);
    defer c.wgpuDeviceDrop(device);

    //Get the queue
    var queue = c.wgpuDeviceGetQueue(device) orelse return error.UnableToGetDeviceQueue;

    //Setup the error callbacks
    gfx.setErrorCallbacks(device);

    //Create our shader module
    var shader = try gfx.createShaderModule(device);
    defer c.wgpuShaderModuleDrop(shader);

    //Get the surface format
    var preferred_surface_format = c.wgpuSurfaceGetPreferredFormat(surface, adapter);

    //Create the bind group layouts
    var bind_group_layouts = try gfx.createBindGroupLayouts(device);
    defer bind_group_layouts.deinit();

    //Create the render pipeline layout
    var render_pipeline_layout = try gfx.createPipelineLayout(device, bind_group_layouts);
    defer c.wgpuPipelineLayoutDrop(render_pipeline_layout);

    //Create the render pipeline
    var render_pipeline = try gfx.createRenderPipeline(device, render_pipeline_layout, shader, preferred_surface_format);
    defer c.wgpuRenderPipelineDrop(render_pipeline);

    //Create the swapchain
    var swap_chain = try gfx.createSwapChain(device, surface, preferred_surface_format, window);
    defer c.wgpuSwapChainDrop(swap_chain);

    //Create the texture
    var texture = try gfx.createTexture(allocator, device, queue, @embedFile("content/atlas.qoi"));
    defer texture.deinit();

    //Create the projection matrix buffer
    var projection_matrix_buffer = try gfx.createBuffer(device, @sizeOf(zmath.Mat), "Projection Matrix Buffer");
    defer c.wgpuBufferDrop(projection_matrix_buffer);

    // var mat = zmath.orthographicOffCenterLh(0, 640, 0, 480, 0, 1);

    var isRunning = true;
    while (isRunning) {
        var ev: c.SDL_Event = undefined;

        if (c.SDL_PollEvent(&ev) != 0) {
            if (ev.type == c.SDL_QUIT) {
                isRunning = false;
            }
            if (ev.type == c.SDL_WINDOWEVENT) {
                if (ev.window.event == c.SDL_WINDOWEVENT_RESIZED) {
                    //Delete old swapchain
                    c.wgpuSwapChainDrop(swap_chain);
                    //Create a new swapchain
                    swap_chain = try gfx.createSwapChain(device, surface, preferred_surface_format, window);
                }
            }
        }

        //Get the current texture view
        var next_texture = c.wgpuSwapChainGetCurrentTextureView(swap_chain) orelse return error.UnableToGetSwapChainTextureView;

        //Create a command encoder
        var command_encoder = c.wgpuDeviceCreateCommandEncoder(device, &c.WGPUCommandEncoderDescriptor{
            .nextInChain = null,
            .label = "Command Encoder",
        }) orelse return error.UnableToCreateCommandEncoder;

        //Begin a render pass
        var render_pass_encoder = c.wgpuCommandEncoderBeginRenderPass(command_encoder, &c.WGPURenderPassDescriptor{
            .label = "Render Pass Encoder",
            .colorAttachmentCount = 1,
            .colorAttachments = &c.WGPURenderPassColorAttachment{
                .view = next_texture,
                .loadOp = c.WGPULoadOp_Clear,
                .storeOp = c.WGPUStoreOp_Store,
                .clearValue = c.WGPUColor{
                    .r = 0,
                    .g = 1,
                    .b = 0,
                    .a = 1,
                },
                .resolveTarget = null,
            },
            .depthStencilAttachment = null,
            .occlusionQuerySet = null,
            .timestampWriteCount = 0,
            .timestampWrites = null,
            .nextInChain = null,
        }) orelse return error.UnableToBeginRenderPass;

        //Set the pipeline
        c.wgpuRenderPassEncoderSetPipeline(render_pass_encoder, render_pipeline);

        //TODO: draw things here

        c.wgpuRenderPassEncoderEnd(render_pass_encoder);
        var command_buffer = c.wgpuCommandEncoderFinish(command_encoder, &c.WGPUCommandBufferDescriptor{
            .label = "Command buffer",
            .nextInChain = null,
        });
        c.wgpuQueueSubmit(queue, 1, &command_buffer);

        c.wgpuSwapChainPresent(swap_chain);
        c.wgpuTextureViewDrop(next_texture);
    }
}
