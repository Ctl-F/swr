const std = @import("std");
const sdl = @cImport(@cInclude("SDL3/SDL.h"));

pub const Dim = struct {
    hor: u32,
    vert: u32,

    pub inline fn area(this: @This()) u32 {
        return this.hor * this.vert;
    }
};

pub const Rect = struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,

    pub inline fn area(this: @This()) u32 {
        return this.width * this.height;
    }

    pub fn overlaps(this: @This(), other: @This()) @This() {
        const this_x1 = this.x;
        const this_y1 = this.y;
        const this_x2 = this.x + this.width;
        const this_y2 = this.y + this.height;
        const other_x1 = other.x;
        const other_y1 = other.y;
        const other_x2 = other.x + other.width;
        const other_y2 = other.y + other.height;

        return this_x1 <= other_x2 and this_x2 >= other_x1 and this_y1 <= other_y2 and this_y2 >= other_y1;
    }

    pub fn get_overlaping_rect(this: @This(), other: @This()) @This() {
        std.debug.assert(this.overlaps(other));

        const this_x1 = this.x;
        const this_y1 = this.y;
        const this_x2 = this.x + this.width;
        const this_y2 = this.y + this.height;
        const other_x1 = other.x;
        const other_y1 = other.y;
        const other_x2 = other.x + other.width;
        const other_y2 = other.y + other.height;

        const new_x1 = @max(this_x1, other_x1);
        const new_y1 = @max(this_y1, other_y1);
        const new_x2 = @min(this_x2, other_x2);
        const new_y2 = @min(this_y2, other_y2);

        return .{
            .x = new_x1,
            .y = new_y1,
            .width = new_x2 - new_x1,
            .height = new_y2 - new_y1,
        };
    }
};

pub const KeyMap = enum(u32) {
    A = sdl.SDL_SCANCODE_A,
    B = sdl.SDL_SCANCODE_B,
    C = sdl.SDL_SCANCODE_C,
    D = sdl.SDL_SCANCODE_D,
    E = sdl.SDL_SCANCODE_E,
    F = sdl.SDL_SCANCODE_F,
    G = sdl.SDL_SCANCODE_G,
    H = sdl.SDL_SCANCODE_H,
    I = sdl.SDL_SCANCODE_I,
    J = sdl.SDL_SCANCODE_J,
    K = sdl.SDL_SCANCODE_K,
    L = sdl.SDL_SCANCODE_L,
    M = sdl.SDL_SCANCODE_M,
    N = sdl.SDL_SCANCODE_N,
    O = sdl.SDL_SCANCODE_O,
    P = sdl.SDL_SCANCODE_P,
    Q = sdl.SDL_SCANCODE_Q,
    R = sdl.SDL_SCANCODE_R,
    S = sdl.SDL_SCANCODE_S,
    T = sdl.SDL_SCANCODE_T,
    U = sdl.SDL_SCANCODE_U,
    V = sdl.SDL_SCANCODE_V,
    W = sdl.SDL_SCANCODE_W,
    X = sdl.SDL_SCANCODE_X,
    Y = sdl.SDL_SCANCODE_Y,
    Z = sdl.SDL_SCANCODE_Z,
};

pub const Format = enum {
    RGBA32,
    RGBD32,
    PID16D16,
    PID8A8D16,
};

pub const Pixel_RGBA32 = packed struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

pub const Pixel_RGBD32 = packed struct {
    r: u8,
    g: u8,
    b: u8,
    depth: i8,
};

pub const Pixel_PID16D16 = packed struct {
    id: u16,
    depth: i16,
};

pub const Pixel_PID8A8D16 = packed struct {
    id: u8,
    a: u8,
    depth: i16,
};

pub const PipelineInfo = struct {
    pixel_format: Format,
};

pub const Canvas = struct {
    size: Dim,
    buffer: []u32,
};

pub const AppInfo = struct {
    title: [*c]const u8,
    size: Dim,
    scale: u8,
};

pub const HostError = error{
    CouldNotAllocateFramebuffer,
    CouldNotAllocateStagingBuffer,
    CouldNotInit,
    CouldNotCreateWindow,
    CouldNotObtainHostFramebuffer,
};

pub fn create_pipeline(comptime pipelineInfo: PipelineInfo) type {
    const FramebufferType = switch (pipelineInfo.pixel_format) {
        .RGBA32 => Pixel_RGBA32,
        .RGBD32 => Pixel_RGBD32,
        .PID16D16 => Pixel_PID16D16,
        .PID8A8D16 => Pixel_PID8A8D16,
    };

    if (FramebufferType == Pixel_PID16D16 or FramebufferType == Pixel_PID8A8D16 or FramebufferType == Pixel_RGBD32) {
        @compileError("Pallatized pixel formats are not yet supported");
    }

    return struct {
        const This = @This();
        pub const Pixel = FramebufferType;

        allocator: std.mem.Allocator,
        info: AppInfo,
        framebuffer: Canvas,
        host: ?*sdl.SDL_Window,
        host_framebuffer: ?*sdl.SDL_Surface,
        host_staging_buffer: ?*sdl.SDL_Surface,

        pub fn init(allocator: std.mem.Allocator, info: AppInfo) HostError!This {
            const framebuffer = allocator.alloc(u32, info.size.area()) catch return HostError.CouldNotAllocateFramebuffer;
            errdefer allocator.free(framebuffer);

            if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
                return HostError.CouldNotInit;
            }
            errdefer sdl.SDL_Quit();

            const window = sdl.SDL_CreateWindow(info.title, @intCast(info.size.hor * info.scale), @intCast(info.size.vert * info.scale), 0);
            if (window == null) {
                return HostError.CouldNotCreateWindow;
            }
            errdefer sdl.SDL_DestroyWindow(window);

            const surface = sdl.SDL_GetWindowSurface(window);
            if (surface == null) {
                return HostError.CouldNotObtainHostFramebuffer;
            }

            const staging_buffer = if (comptime FramebufferType != Pixel_RGBA32) BUFFER: {
                const n_staging_buffer = sdl.SDL_CreateSurface(@intCast(info.size.hor), @intCast(info.size.vert), sdl.SDL_PIXELFORMAT_RGBA32);
                if (n_staging_buffer == null) {
                    return HostError.CouldNotAllocateStagingBuffer;
                }
                break :BUFFER n_staging_buffer;
            } else EBUFFER: {
                const n_staging_buffer = sdl.SDL_CreateSurfaceFrom(@intCast(info.size.hor), @intCast(info.size.vert), sdl.SDL_PIXELFORMAT_RGBA32, framebuffer.ptr, @intCast(info.size.hor * @sizeOf(u32)));
                if (n_staging_buffer == null) {
                    return HostError.CouldNotAllocateStagingBuffer;
                }
                break :EBUFFER n_staging_buffer;
            };
            errdefer sdl.SDL_DestroySurface(staging_buffer);

            return This{
                .allocator = allocator,
                .framebuffer = .{
                    .size = info.size,
                    .buffer = framebuffer,
                },
                .info = info,
                .host = window,
                .host_framebuffer = surface,
                .host_staging_buffer = staging_buffer,
            };
        }

        pub fn poll_events(
            this: This,
            context: ?*anyopaque,
            comptime quitHandler: fn (ctx: ?*anyopaque) void,
            comptime keyHandler: fn (ctx: ?*anyopaque, key: u32, pressed: bool) void,
            comptime mouseHandler: fn (ctx: ?*anyopaque, btn: u32, pressed: bool) void,
            comptime mouseMoveHandler: fn (ctx: ?*anyopaque, x: f32, y: f32, xrel: f32, yrel: f32) void,
        ) void {
            _ = this;
            var event: sdl.SDL_Event = undefined;
            while (sdl.SDL_PollEvent(&event)) {
                switch (event.type) {
                    sdl.SDL_EVENT_QUIT => quitHandler(context),
                    sdl.SDL_EVENT_KEY_DOWN => keyHandler(context, @intCast(event.key.scancode), true),
                    sdl.SDL_EVENT_KEY_UP => keyHandler(context, @intCast(event.key.scancode), false),
                    sdl.SDL_EVENT_MOUSE_BUTTON_DOWN => mouseHandler(context, @intCast(event.button.button), true),
                    sdl.SDL_EVENT_MOUSE_BUTTON_UP => mouseHandler(context, @intCast(event.button.button), false),
                    sdl.SDL_EVENT_MOUSE_MOTION => mouseMoveHandler(context, event.motion.x, event.motion.y, event.motion.xrel, event.motion.yrel),
                    else => {},
                }
            }
        }

        pub fn refresh(this: This) void {
            comptime if (FramebufferType != Pixel_RGBA32) {
                @compileError("Not Implemented");
            };

            _ = sdl.SDL_BlitSurfaceScaled(this.host_staging_buffer, null, this.host_framebuffer, null, sdl.SDL_SCALEMODE_NEAREST);
            _ = sdl.SDL_UpdateWindowSurface(this.host);
        }

        pub fn deinit(this: This) void {
            this.allocator.free(this.framebuffer.buffer);
            sdl.SDL_DestroySurface(this.host_staging_buffer);
            sdl.SDL_DestroyWindow(this.host);
            sdl.SDL_Quit();
        }

        pub const Surface = struct {
            size: Dim,
            buffer: []FramebufferType,
            allocator: ?std.mem.Allocator = null,

            pub fn blank(this: This, size: Dim) !@This() {
                std.debug.assert(size.area() > 0);

                const buffer = try this.allocator.alloc(FramebufferType, size.hor * size.vert);
                return .{
                    .allocator = this.allocator,
                    .size = size,
                    .buffer = buffer,
                };
            }

            pub fn deinit(this: @This()) void {
                if (this.allocator) |allocator| {
                    allocator.free(this.buffer);
                }
            }

            pub inline fn index(this: @This(), x: u32, y: u32) usize {
                return @as(usize, @intCast(x + y * this.size.hor));
            }

            pub fn blit_to(this: @This(), source_region: ?Rect, target: @This(), target_region: ?Rect) !void {
                const src_rect: Rect = source_region orelse .{ .x = 0, .y = 0, .width = this.size.hor, .height = this.size.vert };
                const dest_rect: Rect = target_region orelse .{ .x = 0, .y = 0, .width = target.size.hor, .height = target.size.vert };
                _ = src_rect;
                _ = dest_rect;
                //TODO: implement
                @compileError("Not implemented");
            }
        };

        pub fn get_framebuffer(this: This) Surface {
            comptime if (@sizeOf(FramebufferType) != @sizeOf(u32)) {
                @compileError("Framebuffer cannot be safely converted to specified pixel format.");
            };

            const addr: [*]FramebufferType = @ptrCast(@alignCast(this.framebuffer.buffer.ptr));
            return .{
                .size = this.framebuffer.size,
                .buffer = addr[0..this.framebuffer.buffer.len],
            };
        }
    };
}
