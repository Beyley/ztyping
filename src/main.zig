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
    const window = c.SDL_CreateWindow("ztyping", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 640, 480, c.SDL_WINDOW_SHOWN) orelse {
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

    //Setup the error callbacks
    gfx.setErrorCallbacks(device);

    //Create our shader module
    var shader = try gfx.createShaderModule(device);
    defer c.wgpuShaderModuleDrop(shader);

    var preferred_surface_format = c.wgpuSurfaceGetPreferredFormat(surface, adapter);

    var bind_group_layouts = try gfx.createBindGroupLayouts(device);
    defer bind_group_layouts.deinit();

    var render_pipeline_layout = try gfx.createPipelineLayout(device, bind_group_layouts);
    defer c.wgpuPipelineLayoutDrop(render_pipeline_layout);

    var render_pipeline = try gfx.createRenderPipeline(device, render_pipeline_layout, shader, preferred_surface_format);
    defer c.wgpuRenderPipelineDrop(render_pipeline);

    var isRunning = true;
    while (isRunning) {
        var ev: c.SDL_Event = undefined;

        if (c.SDL_PollEvent(&ev) != 0) {
            if (ev.type == c.SDL_QUIT) {
                isRunning = false;
            }
        }

        var mat = zmath.orthographicOffCenterLh(0, 640, 0, 480, 0, 1);
        _ = mat;
    }
}
