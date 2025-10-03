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
    flip: bool = false,
    axis_keys: [4]bool = [_]bool{false} ** 4,
};

fn handle_key(ctx: *MyContext, key: u32, pressed: bool) void {
    switch (key) {
        @as(u32, @intFromEnum(swr.KeyMap.A)) => ctx.axis_keys[LEFT] = pressed,
        @as(u32, @intFromEnum(swr.KeyMap.D)) => ctx.axis_keys[RIGHT] = pressed,
        @as(u32, @intFromEnum(swr.KeyMap.W)) => ctx.axis_keys[UP] = pressed,
        @as(u32, @intFromEnum(swr.KeyMap.S)) => ctx.axis_keys[DOWN] = pressed,
        else => {},
    }

    if (pressed) {
        if (key == @as(u32, @intFromEnum(swr.KeyMap.A))) {
            ctx.flip = true;
        }
        if (key == @as(u32, @intFromEnum(swr.KeyMap.D))) {
            ctx.flip = false;
        }
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
// TODO: Renderer thread setup and flags
// TODO: Composite modes on pipeline (dst hint src hint)
// TODO: Write custom hand-rolled upscaler(leveraging zig comptime to generate specialized versions of it)
pub fn main() !void {
    const appInfo = swr.AppInfo{
        .title = "Hello swr",
        .size = .{
            .hor = 160,
            .vert = 120,
        },
    };
    const pipelineInfo = swr.PipelineInfo{
        .pixel_format = .RGBA32,
        .scale = 4,
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

        var new_x: i64 = @as(i64, @intCast(@as(i32, @intCast(context.x)) + h_vel));
        var new_y: i64 = @as(i64, @intCast(@as(i32, @intCast(context.y)) + v_vel));

        new_x = std.math.clamp(new_x, 0, @as(i64, @intCast(pipeline.framebuffer.size.hor - 10)));
        new_y = std.math.clamp(new_y, 0, @as(i64, @intCast(pipeline.framebuffer.size.vert - 10)));

        context.x = @as(u32, @intCast(new_x));
        context.y = @as(u32, @intCast(new_y));

        const fb = pipeline.get_framebuffer();

        const split_index = fb.index(pipeline.framebuffer.size.hor, pipeline.framebuffer.size.vert / 2 + pipeline.framebuffer.size.vert / 4);
        const sky = fb.buffer[0..split_index];
        const ground = fb.buffer[split_index..];

        @memset(sky, PipelineType.Pixel{ .r = 200, .g = 240, .b = 250, .a = 255 });
        @memset(ground, PipelineType.Pixel{ .r = 20, .g = 100, .b = 50, .a = 255 });

        const offset: u32 = if (context.flip) 1 else 0;

        for (0..10) |x| {
            for (0..10) |y| {
                fb.buffer[fb.index(3 + @as(u32, @truncate(x)), 3 + @as(u32, @truncate(y)))] = .{ .r = 255, .g = 255, .b = 150, .a = 255 };

                if ((offset == 1 and x == 0 and y == 0) or (offset == 0 and x == 9 and y == 0)) continue;
                const color: PipelineType.Pixel = if ((x == 0 or x == 9 or y == 0 or y == 9) or ((x == 3 - offset or x == 7 - offset) and y == 3) or (x > 2 - offset - offset and x < 9 - offset - offset and y == 7)) .{ .r = 0, .g = 0, .b = 0, .a = 255 } else .{ .r = 255, .g = 255, .b = 255, .a = 255 };

                fb.buffer[fb.index(context.x + @as(u32, @truncate(x)), context.y + @as(u32, @truncate(y)))] = color;
            }
        }

        pipeline.refresh();
    }
}
