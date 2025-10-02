const std = @import("std");
const swr = @import("swr");

const DOWN: usize = 3;
const UP: usize = 2;
const RIGHT: usize = 1;
const LEFT: usize = 0;

const MyContext = struct {
    should_run: bool,
    x: u32 = 0,
    y: u32 = 0,
    axis_keys: [4]bool = [_]bool{false} ** 4,
};

fn handle_key(ctx: *MyContext, key: u32, pressed: bool) void {
    switch (key) {
        swr.KeyMap.A => ctx.axis_keys[LEFT] = pressed,
        swr.KeyMap.D => ctx.axis_keys[RIGHT] = pressed,
        swr.KeyMap.W => ctx.axis_keys[UP] = pressed,
        swr.KeyMap.S => ctx.axis_keys[DOWN] = pressed,
        else => {},
    }
}

fn handle_mouse(ctx: *MyContext, button: u32, pressed: bool) void {
    _ = ctx;
    _ = button;
    _ = pressed;
}

fn handle_mouse_move(ctx: *MyContext, x: f32, y: f32, xrel: f32, yrel: f32) void {
    _ = ctx;
    _ = x;
    _ = y;
    _ = xrel;
    _ = yrel;
}

fn handle_quit(ctx: *MyContext) void {
    ctx.should_run = false;
}

fn v_handle_quit(ctx: ?*anyopaque) void {
    if (ctx) |cx| {
        return handle_quit(@ptrCast(@alignCast(cx)));
    }
    unreachable;
}

fn v_handle_key(ctx: ?*anyopaque, key: u32, pressed: bool) void {
    if (ctx) |cx| {
        return handle_key(@ptrCast(@alignCast(cx)), key, pressed);
    }
    unreachable;
}

fn v_handle_mouse(ctx: ?*anyopaque, button: u32, pressed: bool) void {
    if (ctx) |cx| {
        return handle_mouse(@ptrCast(@alignCast(cx)), button, pressed);
    }
    unreachable;
}

fn v_handle_mouse_move(ctx: ?*anyopaque, x: f32, y: f32, xrel: f32, yrel: f32) void {
    if (ctx) |cx| {
        return handle_mouse_move(@ptrCast(@alignCast(cx)), x, y, xrel, yrel);
    }
    unreachable;
}

pub fn main() !void {
    const appInfo = swr.AppInfo{
        .title = "Hello swr",
        .size = .{
            .width = 160,
            .height = 120,
        },
        .scale = 4,
    };
    const pipelineInfo = swr.PipelineInfo{
        .pixel_format = .RGBA32,
    };

    var GPA = std.heap.DebugAllocator(.{}).init;
    const allocator = GPA.allocator();

    var context = MyContext{
        .should_run = true,
    };

    const PipelineType = swr.create_pipeline(pipelineInfo);
    var pipeline = try PipelineType.init(allocator, appInfo);
    defer pipeline.deinit();

    while (context.should_run) {
        pipeline.poll_events(
            &context,
            v_handle_quit,
            v_handle_key,
            v_handle_mouse,
            v_handle_mouse_move,
        );

        const h_vel = @as(i32, @intFromBool(context.axis_keys[RIGHT])) -
            @as(i32, @intFromBool(context.axis_keys[LEFT]));
        const v_vel = @as(i32, @intFromBool(context.axis_keys[DOWN])) -
            @as(i32, @intFromBool(context.axis_keys[UP]));

        context.x += h_vel;
        context.y += v_vel;

        const fb = pipeline.get_framebuffer();
        @memset(fb.buffer, PipelineType.Pixel{ .r = 20, .g = 10, .b = 10, .a = 255 });

        fb.buffer[fb.index(context.x + 5, context.y)] = .{ .r = 255, .g = 255, .b = 255, .a = 255 };
        fb.buffer[fb.index(context.x + 10, context.y)] = .{ .r = 255, .g = 255, .b = 255, .a = 255 };

        for (0..10) |x| {
            fb.buffer[fb.index(context.x + @as(u32, @truncate(x)), context.y + 5)] = .{ .r = 255, .g = 255, .b = 255, .a = 255 };
        }

        pipeline.refresh();
    }
}
