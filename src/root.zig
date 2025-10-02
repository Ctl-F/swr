const std = @import("std");
const sdl = @cImport(@cInclude("SDL3/SDL.h"));

pub const Dim = struct {
    width: u32,
    height: u32,

    pub inline fn area(this: @This()) u32 {
        return this.width * this.height;
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

            const window = sdl.SDL_CreateWindow(info.title, @intCast(info.size.width * info.scale), @intCast(info.size.height * info.scale), 0);
            if (window == null) {
                return HostError.CouldNotCreateWindow;
            }
            errdefer sdl.SDL_DestroyWindow(window);

            const surface = sdl.SDL_GetWindowSurface(window);
            if (surface == null) {
                return HostError.CouldNotObtainHostFramebuffer;
            }

            const staging_buffer = if (comptime FramebufferType != Pixel_RGBA32) BUFFER: {
                const n_staging_buffer = sdl.SDL_CreateSurface(@intCast(info.size.width), @intCast(info.size.height), sdl.SDL_PIXELFORMAT_RGBA32);
                if (n_staging_buffer == null) {
                    return HostError.CouldNotAllocateStagingBuffer;
                }
                break :BUFFER n_staging_buffer;
            } else EBUFFER: {
                const n_staging_buffer = sdl.SDL_CreateSurfaceFrom(@intCast(info.size.width), @intCast(info.size.height), sdl.SDL_PIXELFORMAT_RGBA32, framebuffer.ptr, @intCast(info.size.width * @sizeOf(u32)));
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

            pub inline fn index(this: @This(), x: u32, y: u32) usize {
                return @as(usize, @intCast(x + y * this.size.width));
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
