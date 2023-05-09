const Gfx = @import("gfx.zig");

const Self = @This();

pub const MainMenu = @import("screens/main_menu.zig").MainMenu;

render: *const fn (Gfx, Gfx.RenderPassEncoder, Gfx.Texture) void,
