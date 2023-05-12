const std = @import("std");
const zaudio = @import("zaudio");
const zmath = @import("zmath");
const Gfx = @import("gfx.zig");
const Screen = @import("screen.zig");
const ScreenStack = @import("screen_stack.zig");
const Renderer = @import("renderer.zig");

pub const c = @cImport({
    @cInclude("fontstash.h");
    @cInclude("SDL.h");
    @cInclude("SDL_syswm.h");
    @cInclude("wgpu.h");
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "1");
    @cDefine("CIMGUI_USE_SDL2", "1");
    @cDefine("CIMGUI_USE_WGPU", "1");
    @cInclude("cimgui.h");
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

    var imgui_context = c.igCreateContext(null);
    defer c.igDestroyContext(imgui_context);

    c.igSetCurrentContext(imgui_context);

    if (!c.ImGui_ImplSDL2_InitForD3D(window)) {
        return error.UnableToInitSDL2ImGui;
    }
    defer c.ImGui_ImplSDL2_Shutdown();

    if (!c.ImGui_ImplWGPU_Init(gfx.device.c, 1, gfx.surface.getPreferredFormat(gfx.adapter), c.WGPUTextureFormat_Undefined)) {
        return error.UnableToInitWGPUImGui;
    }
    defer c.ImGui_ImplWGPU_Shutdown();

    //Create the initial WGPU ImGui device objects
    if (!c.ImGui_ImplWGPU_CreateDeviceObjects()) {
        return error.UnableToCreateImGuiWGPUDeviceObjects;
    }

    //Create the texture
    var texture = try gfx.device.createTexture(gfx.queue, allocator, @embedFile("content/atlas.qoi"));
    defer texture.deinit();

    //Create the bind group for the texture
    try texture.createBindGroup(gfx.device, gfx.sampler, gfx.bind_group_layouts);

    gfx.updateProjectionMatrixBuffer(gfx.queue, window);

    var renderer = try Renderer.init(allocator, gfx, texture);
    defer renderer.deinit();

    var screen_stack = ScreenStack.init(allocator);
    defer {
        while (screen_stack.count() != 0) {
            _ = screen_stack.pop();
        }

        screen_stack.deinit();
    }

    try screen_stack.load(&Screen.MainMenu.MainMenu, gfx);

    var old_width: c_int = 0;
    var old_height: c_int = 0;
    c.SDL_GL_GetDrawableSize(window, &old_width, &old_height);

    var isRunning = true;
    while (isRunning) {
        var ev: c.SDL_Event = undefined;

        while (c.SDL_PollEvent(&ev) != 0) {
            _ = c.ImGui_ImplSDL2_ProcessEvent(&ev);

            if (ev.type == c.SDL_QUIT) {
                isRunning = false;
            }
            if (ev.type == c.SDL_KEYDOWN) {
                if (ev.key.keysym.sym == c.SDLK_ESCAPE)
                    isRunning = false;
            }
        }

        var width: c_int = 0;
        var height: c_int = 0;
        c.SDL_GL_GetDrawableSize(window, &width, &height);

        if (width != old_width or height != old_height) {
            c.ImGui_ImplWGPU_InvalidateDeviceObjects();

            //Create a new swapchain
            try gfx.recreateSwapChain(window);
            gfx.updateProjectionMatrixBuffer(gfx.queue, window);

            if (!c.ImGui_ImplWGPU_CreateDeviceObjects()) {
                return error.UnableToCreateImGuiDeviceObjects;
            }

            old_height = height;
            old_width = width;
        }

        c.ImGui_ImplWGPU_NewFrame();
        c.ImGui_ImplSDL2_NewFrame();
        c.igNewFrame();

        //Get the current texture view for the swap chain
        var next_texture = try gfx.swap_chain.?.getCurrentSwapChainTexture();

        //Create a command encoder
        var command_encoder = try gfx.device.createCommandEncoder(&c.WGPUCommandEncoderDescriptor{
            .nextInChain = null,
            .label = "Command Encoder",
        });

        //Begin the render pass
        var render_pass_encoder = try command_encoder.beginRenderPass(next_texture);

        //Get the top screen
        var screen = screen_stack.top();
        //Render it
        screen.render(screen, gfx, render_pass_encoder, texture);

        try renderer.begin();

        var reserved = try renderer.reserve(4, 6);
        reserved.copyIn(&.{
            Gfx.Vertex{
                .position = .{ 0, 0 },
                .tex_coord = Gfx.getUVsFromAtlas("note").tl,
                .vertex_col = .{ 1, 1, 1, 1 },
            },
            Gfx.Vertex{
                .position = .{ 400, 0 },
                .tex_coord = Gfx.getUVsFromAtlas("note").tr,
                .vertex_col = .{ 1, 1, 1, 1 },
            },
            Gfx.Vertex{
                .position = .{ 0, 400 },
                .tex_coord = Gfx.getUVsFromAtlas("note").bl,
                .vertex_col = .{ 1, 1, 1, 1 },
            },
            Gfx.Vertex{
                .position = .{ 400, 400 },
                .tex_coord = Gfx.getUVsFromAtlas("note").br,
                .vertex_col = .{ 1, 1, 1, 1 },
            },
        }, &.{
            0 + reserved.idx_offset,
            2 + reserved.idx_offset,
            1 + reserved.idx_offset,
            1 + reserved.idx_offset,
            2 + reserved.idx_offset,
            3 + reserved.idx_offset,
        });

        reserved = try renderer.reserve(4, 6);
        reserved.copyIn(&.{
            Gfx.Vertex{
                .position = .{ 100, 0 },
                .tex_coord = Gfx.getUVsFromAtlas("icon").tl,
                .vertex_col = .{ 1, 1, 1, 1 },
            },
            Gfx.Vertex{
                .position = .{ 500, 0 },
                .tex_coord = Gfx.getUVsFromAtlas("icon").tr,
                .vertex_col = .{ 1, 1, 1, 1 },
            },
            Gfx.Vertex{
                .position = .{ 100, 400 },
                .tex_coord = Gfx.getUVsFromAtlas("icon").bl,
                .vertex_col = .{ 1, 1, 1, 1 },
            },
            Gfx.Vertex{
                .position = .{ 500, 400 },
                .tex_coord = Gfx.getUVsFromAtlas("icon").br,
                .vertex_col = .{ 1, 1, 1, 1 },
            },
        }, &.{
            0 + reserved.idx_offset,
            2 + reserved.idx_offset,
            1 + reserved.idx_offset,
            1 + reserved.idx_offset,
            2 + reserved.idx_offset,
            3 + reserved.idx_offset,
        });

        try renderer.end();

        try renderer.draw(&render_pass_encoder);

        c.igRender();
        c.ImGui_ImplWGPU_RenderDrawData(c.igGetDrawData(), render_pass_encoder.c);

        render_pass_encoder.end();

        var command_buffer = try command_encoder.finish(&c.WGPUCommandBufferDescriptor{
            .label = "Command buffer",
            .nextInChain = null,
        });

        gfx.queue.submit(&.{command_buffer});

        gfx.swap_chain.?.swapChainPresent();

        c.wgpuTextureViewDrop(next_texture);
    }
}
