const std = @import("std");
const bass = @import("bass");
const zmath = @import("zmath");
const builtin = @import("builtin");
const Gfx = @import("gfx.zig");
const Screen = @import("screen.zig");
const ScreenStack = @import("screen_stack.zig");
const Renderer = @import("renderer.zig");
const Fontstash = @import("fontstash.zig");
const Music = @import("music.zig");
const GameState = @import("game_state.zig");
const Convert = @import("convert.zig");

pub const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_syswm.h");
    @cInclude("wgpu.h");
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "1");
    @cDefine("CIMGUI_USE_SDL2", "1");
    @cDefine("CIMGUI_USE_WGPU", "1");
    @cInclude("cimgui.h");
    if (builtin.target.isDarwin()) {
        @cInclude("osx_helper.h");
    }
});

pub fn main() !void {
    //The scale of the window
    const scale = 2;

    const use_gpa = std.debug.runtime_safety;

    var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 10 }){};
    //Deinit the GPA, if in use
    defer if (use_gpa and gpa.deinit() == .leak) {
        @panic("Memory leak!");
    };

    var allocator: std.mem.Allocator = blk: {
        // If we should use the GPA,
        if (use_gpa) {
            //Set the allocator to the allocator of the general purpose allocator
            break :blk gpa.allocator();
        } else {
            // Otherwise, use the C allocator
            break :blk std.heap.c_allocator;
        }
    };

    var state: GameState = GameState{
        .is_running = true,
        .audio_tracker = .{
            .music = null,
        },
        .map_list = undefined,
        .convert = undefined,
        .current_map = null,
        .delta_time = 0,
        .counter_freq = 0,
        .counter_curr = 0,
    };

    //Initialize SDL
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        std.debug.print("SDL init failed! err:{s}\n", .{c.SDL_GetError()});
        return error.InitSdlFailure;
    }
    defer c.SDL_Quit();
    std.debug.print("Initialized SDL\n", .{});

    //Create the window
    const window = c.SDL_CreateWindow("ztyping", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 640 * scale, 480 * scale, c.SDL_WINDOW_SHOWN) orelse {
        std.debug.print("SDL window creation failed! err:{s}\n", .{c.SDL_GetError()});
        return error.CreateWindowFailure;
    };
    defer c.SDL_DestroyWindow(window);
    std.debug.print("Created SDL window\n", .{});

    var bass_window_ptr: ?*anyopaque = null;

    if (builtin.os.tag == .windows) {
        var info: c.SDL_SysWMinfo = undefined;
        c.SDL_GetVersion(&info.version);
        var result = c.SDL_GetWindowWMInfo(window, &info);

        if (result == c.SDL_FALSE) {
            return error.UnableToRetrieveWindowWMInfo;
        }

        //If the window is using the Windows backend
        if (info.subsystem == c.SDL_SYSWM_WINDOWS) {
            //Set the bass window ptr to the HWND
            bass_window_ptr = info.info.win.window;
        }
    }

    try bass.init(.default, null, .{}, bass_window_ptr);
    defer bass.deinit();

    try bass.setConfig(.global_stream_volume, 0.1 * 10000);

    //Initialize our graphics
    var gfx: Gfx = try Gfx.init(window, scale);
    defer gfx.deinit();

    var imgui_context = c.igCreateContext(null);
    defer c.igDestroyContext(imgui_context);

    c.igSetCurrentContext(imgui_context);

    var imgui_io = c.igGetIO();

    //Create a font config
    var font_config = c.ImFontConfig_ImFontConfig();
    //Mark that the atlas does *not* own the font data
    font_config.*.FontDataOwnedByAtlas = false;

    var mincho_data = @embedFile("fonts/mincho.ttf");
    //Create the font from the mincho ttf
    var mincho = c.ImFontAtlas_AddFontFromMemoryTTF(imgui_io.*.Fonts, @constCast(mincho_data.ptr), mincho_data.len, 15, font_config, c.ImFontAtlas_GetGlyphRangesJapanese(imgui_io.*.Fonts));

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

    c.igSetCurrentFont(mincho);

    //Create the texture
    var texture = try gfx.device.createTexture(gfx.queue, allocator, @embedFile("content/atlas.qoi"));
    defer texture.deinit();

    //Create the bind group for the texture
    try texture.createBindGroup(gfx.device, gfx.sampler, gfx.bind_group_layouts);

    gfx.updateProjectionMatrixBuffer(gfx.queue, window);

    var renderer = try Renderer.init(allocator, &gfx, texture);
    defer renderer.deinit();

    var screen_stack = ScreenStack.init(allocator);
    defer {
        while (screen_stack.count() != 0) {
            _ = screen_stack.pop();
        }

        screen_stack.deinit();
    }

    var fontstash: *Fontstash = try allocator.create(Fontstash);
    defer allocator.destroy(fontstash);

    try fontstash.init(&gfx, allocator);
    defer fontstash.deinit();

    var old_width: c_int = 0;
    var old_height: c_int = 0;
    c.SDL_GL_GetDrawableSize(window, &old_width, &old_height);

    state.map_list = try Music.readUTypingList(allocator);
    defer {
        for (0..state.map_list.len) |i| {
            state.map_list[i].deinit();
        }

        allocator.free(state.map_list);
    }

    state.convert = try Convert.readUTypingConversions(allocator);
    defer {
        for (state.convert.conversions) |conversion| {
            conversion.deinit();
        }

        state.convert.deinit();
    }

    std.debug.print("parsed {d} maps!\n", .{state.map_list.len});

    const freq: f64 = @floatFromInt(c.SDL_GetPerformanceFrequency());
    state.counter_freq = freq;
    var delta_start = c.SDL_GetPerformanceCounter();

    try screen_stack.load(&Screen.MainMenu.MainMenu, gfx, &state);
    while (state.is_running) {
        var current_counter = c.SDL_GetPerformanceCounter();
        state.counter_curr = current_counter;
        const delta_time: f64 = @as(f64, @floatFromInt((current_counter - delta_start))) / freq;
        state.delta_time = delta_time;
        delta_start = c.SDL_GetPerformanceCounter();

        // std.debug.print("delta: {d}ms\n", .{delta_time});

        var ev: c.SDL_Event = undefined;

        //Get the top screen
        var screen = screen_stack.top();

        while (c.SDL_PollEvent(&ev) != 0) {
            _ = c.ImGui_ImplSDL2_ProcessEvent(&ev);

            switch (ev.type) {
                c.SDL_QUIT => {
                    state.is_running = false;
                },
                c.SDL_KEYDOWN => {
                    if (screen.key_down) |keyDown| {
                        try keyDown(screen, ev.key.keysym);
                    }
                },
                c.SDL_TEXTINPUT => {
                    //Get the end of the arr
                    var end = std.mem.indexOf(u8, &ev.text.text, &.{0}) orelse 32;

                    //Send the event to the screen
                    if (screen.char) |char| {
                        try char(screen, ev.text.text[0..end]);
                    }
                },
                c.SDL_MOUSEMOTION => {},
                else => {},
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

        //Render it
        try screen.render(screen, .{
            .gfx = &gfx,
            .renderer = &renderer,
            .fontstash = fontstash,
            .render_pass_encoder = &render_pass_encoder,
        });

        if (builtin.mode == .Debug) {
            var open = false;
            _ = c.igBegin("fps", &open, 0);
            c.igText("%fms %dfps", state.delta_time * 1000, @as(usize, @intFromFloat(1 / state.delta_time)));
            c.igEnd();
        }

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

        if (screen.close_screen) {
            _ = screen_stack.pop();
            screen.close_screen = false;
        } else if (screen.screen_push) |new_screen| {
            try screen_stack.load(new_screen, gfx, &state);
            screen.screen_push = null;
        }
    }
}
