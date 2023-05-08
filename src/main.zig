const std = @import("std");
const zaudio = @import("zaudio");
const zmath = @import("zmath");
const Gfx = @import("gfx.zig");
const Screen = @import("screen.zig");

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
    const audio_engine = try zaudio.Engine.create(null);
    defer audio_engine.destroy();

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

    //Initialize our graphics
    var gfx: Gfx = try Gfx.init(window);
    defer gfx.deinit();

    //Create the texture
    var texture = try gfx.createTexture(allocator, @embedFile("content/atlas.qoi"));
    defer texture.deinit();

    //Create the bind group for the texture
    var texture_bind_group = try texture.createBindGroup(&gfx);
    defer c.wgpuBindGroupDrop(texture_bind_group);

    gfx.updateProjectionMatrixBuffer(window);

    var screen_stack = std.ArrayList(Screen).init(allocator);
    defer screen_stack.deinit();

    //3 is the common deepest, main menu -> song select -> gameplay
    try screen_stack.ensureUnusedCapacity(3);

    try screen_stack.append(Screen.MainMenu);

    var isRunning = true;
    while (isRunning) {
        var ev: c.SDL_Event = undefined;

        if (c.SDL_PollEvent(&ev) != 0) {
            if (ev.type == c.SDL_QUIT) {
                isRunning = false;
            }
            if (ev.type == c.SDL_WINDOWEVENT) {
                if (ev.window.event == c.SDL_WINDOWEVENT_RESIZED) {
                    //Create a new swapchain
                    gfx.swap_chain = try gfx.createSwapChainOptimal(window);
                    gfx.updateProjectionMatrixBuffer(window);
                }
            }
        }

        //Get the current texture view for the swap chain
        var next_texture = try gfx.getCurrentSwapChainTexture();

        //Create a command encoder
        var command_encoder = try gfx.createCommandEncoder(&c.WGPUCommandEncoderDescriptor{
            .nextInChain = null,
            .label = "Command Encoder",
        });

        //Begin the render pass
        var render_pass_encoder = try command_encoder.beginRenderPass(next_texture);

        //Set the pipeline
        render_pass_encoder.setPipeline(gfx.render_pipeline);
        render_pass_encoder.setBindGroup(0, gfx.projection_matrix_bind_group, &.{});

        var screen = screen_stack.getLast();
        screen.render(gfx, render_pass_encoder);

        render_pass_encoder.end();

        var command_buffer = try command_encoder.finish(&c.WGPUCommandBufferDescriptor{
            .label = "Command buffer",
            .nextInChain = null,
        });

        gfx.queueSubmit(&.{command_buffer});

        gfx.swapChainPresent();

        c.wgpuTextureViewDrop(next_texture);
    }
}
