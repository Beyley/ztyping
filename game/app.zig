const std = @import("std");
const bass = @import("bass");
const core = @import("mach-core");
const gpu = core.gpu;
const builtin = @import("builtin");
const Gfx = @import("gfx.zig");
const Screen = @import("screen.zig");
const ScreenStack = @import("screen_stack.zig");
const Renderer = @import("renderer.zig");
const Fontstash = @import("fontstash.zig");
const Music = @import("music.zig");
const Convert = @import("convert.zig");
const Config = @import("config.zig");

const AudioTracker = @import("audio_tracker.zig");

pub const App = @This();

is_running: bool,
///The tracker for our audio state
audio_tracker: AudioTracker,
///The list of all loaded maps
map_list: []Music,
///The current map being played
current_map: ?Music,
///The loaded convert file
convert: Convert,
///The counter time frequency
counter_freq: f64,
///The current time counter
counter_curr: u64,
///The config instances
config: Config,
///The random instance used by the app
random: std.rand.DefaultPrng = std.rand.DefaultPrng.init(35698752),
///The name of the user, this is owned by the main menu instance at the bottom of the screen stack
name: []const u8,

///Our main texture atlas
gfx: Gfx,
texture: Gfx.Texture,
renderer: Renderer,
fontstash: Fontstash,
screen_stack: ScreenStack,

pub fn init(app: *App) !void {
    try core.init(.{
        .title = "ilo nanpa pi ilo nanpa",
        .power_preference = .low_power,
    });

    const config = try Config.readConfig();

    //Initialize our graphics
    var gfx: Gfx = try Gfx.init(app.config);

    app.* = .{
        .is_running = true,
        .audio_tracker = .{
            .music = null,
        },
        .map_list = try Music.readUTypingList(core.allocator),
        .convert = try Convert.readUTypingConversions(core.allocator),
        .current_map = null,
        .counter_freq = 0,
        .counter_curr = 0,
        .config = config,
        .name = undefined,
        .gfx = try Gfx.init(config),
        .texture = try Gfx.createTexture(core.allocator, @embedFile("content/atlas.qoi")),
        .renderer = undefined,
        .fontstash = undefined,
        .screen_stack = ScreenStack.init(core.allocator),
    };
    std.debug.print("loaded {d} maps!\n", .{app.map_list.len});

    const bass_window_ptr: usize = 0;

    try bass.init(.default, null, .{}, bass_window_ptr);
    defer bass.deinit();

    try bass.setConfig(.global_stream_volume, @intFromFloat(app.config.volume * 10000));

    //Create the bind group for the texture
    // try texture.createBindGroup(gfx.device, gfx.sampler, gfx.bind_group_layouts);

    gfx.updateProjectionMatrixBuffer();

    //Init the renderer
    app.renderer = try Renderer.init(core.allocator, &gfx, app.texture);

    //Init the font stash
    try app.fontstash.init(&app.gfx, core.allocator);

    //Load the main menu
    try app.screen_stack.load(&Screen.MainMenu.MainMenu, gfx, app);
}

pub fn deinit(app: *App) void {
    defer core.deinit();
    defer app.gfx.deinit();
    defer app.texture.deinit();
    defer app.fontstash.deinit();
    defer {
        //Pop all of the screens
        while (app.screen_stack.count() != 0) {
            _ = app.screen_stack.pop();
        }

        //Deinit the stack
        app.screen_stack.deinit();
    }
    defer {
        for (0..app.map_list.len) |i| {
            app.map_list[i].deinit();
        }

        core.allocator.free(app.map_list);
    }
    defer {
        for (app.convert.conversions) |conversion| {
            conversion.deinit();
        }

        app.convert.deinit();
    }

    app.gfx.deinit();
    app.renderer.deinit();
}

pub fn update(app: *App) !bool {
    std.debug.print("update\n", .{});

    //Get the top screen
    var screen = app.screen_stack.top();

    var event_iter = core.pollEvents();
    while (event_iter.next()) |event| {
        switch (event) {
            .close => return true,
            .key_press => |ev| {
                if (screen.key_down) |key_down| {
                    try key_down(screen, ev.key);
                }
            },
            .char_input => |ev| {
                if (screen.char) |char| {
                    try char(screen, ev.codepoint);
                }
            },
            else => {},
        }
    }

    const back_buffer_view = core.swap_chain.getCurrentTextureView().?;
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
        .load_op = .clear,
        .store_op = .store,
    };

    const command_encoder = core.device.createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
    });
    //Begin the render pass
    const render_pass_encoder = command_encoder.beginRenderPass(&render_pass_info);

    //Render it
    try screen.render(screen, .{
        .gfx = &app.gfx,
        .renderer = &app.renderer,
        .fontstash = &app.fontstash,
        .render_pass_encoder = render_pass_encoder,
        .app = app,
    });

    // if (builtin.mode == .Debug) {
    //     var open = false;
    //     _ = c.igBegin("fps", &open, 0);
    //     c.igText("%fms %dfps", state.delta_time * 1000, @as(usize, @intFromFloat(1 / state.delta_time)));
    //     c.igEnd();
    // }

    // c.igRender();
    // c.ImGui_ImplWGPU_RenderDrawData(c.igGetDrawData(), render_pass_encoder.c);

    render_pass_encoder.end();
    render_pass_encoder.release();

    var command = command_encoder.finish(null);
    command_encoder.release();

    core.queue.submit(&.{command});
    command.release();

    core.swap_chain.present();

    if (screen.close_screen) {
        _ = app.screen_stack.pop();
        screen.close_screen = false;

        const top = app.screen_stack.top();
        if (top.reenter) |re_enter| {
            try re_enter(top);
        }
    } else if (screen.screen_push) |new_screen| {
        try app.screen_stack.load(new_screen, app.gfx, app);
        screen.screen_push = null;
    }

    return false;
}
