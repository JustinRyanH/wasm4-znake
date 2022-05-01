const std = @import("std");
const RendererVals = @import("renderer_vals.zig");
const LocalMem = @import("local_mem.zig");
pub const FONT = RendererVals.FONT;
const SimpleRenderer = @This();
const mem = std.mem;

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    setPixel: fn (ptr: *anyopaque, x: i32, y: i32) void,
    setPixelAlternative: fn (ptr: *anyopaque, x: i32, y: i32) void,
    setFrontendPallete: fn (ptr: *anyopaque, color: u2) void,
    setBackgroundPallete: fn (ptr: *anyopaque, color: ?u2) void,
    getHeight: fn (ptr: *anyopaque) i32,
    getWidth: fn (ptr: *anyopaque) i32,
};

pub fn init(
    pointer: anytype,
    comptime setPixelFn: fn (ptr: @TypeOf(pointer), x: i32, y: i32) void,
    comptime setPixelAltFn: fn (ptr: @TypeOf(pointer), x: i32, y: i32) void,
    comptime setFrontendPalleteFn: fn (ptr: @TypeOf(pointer), color: u2) void,
    comptime setBackgroundPalleteFn: fn (ptr: @TypeOf(pointer), color: ?u2) void,
    comptime widthFn: fn (ptr: @TypeOf(pointer)) i32,
    comptime heightFn: fn (ptr: @TypeOf(pointer)) i32,
) SimpleRenderer {
    const Ptr = @TypeOf(pointer);
    const ptr_info = @typeInfo(Ptr);

    std.debug.assert(ptr_info == .Pointer); // Must be a pointer
    std.debug.assert(ptr_info.Pointer.size == .One); // Must be a single-item pointer

    const alignment = ptr_info.Pointer.alignment;

    const gen = struct {
        fn setPixelImpl(ptr: *anyopaque, x: i32, y: i32) void {
            const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
            return @call(.{ .modifier = .always_inline }, setPixelFn, .{ self, x, y });
        }
        fn setPixelAlternativeImpl(ptr: *anyopaque, x: i32, y: i32) void {
            const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
            return @call(.{ .modifier = .always_inline }, setPixelAltFn, .{ self, x, y });
        }
        fn setFrontendPalleteImpl(ptr: *anyopaque, color: u2) void {
            const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
            return @call(.{ .modifier = .always_inline }, setFrontendPalleteFn, .{ self, color });
        }

        fn setBackgroundPalleteImpl(ptr: *anyopaque, color: ?u2) void {
            const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
            return @call(.{ .modifier = .always_inline }, setBackgroundPalleteFn, .{ self, color });
        }

        fn getHeightImpl(ptr: *anyopaque) i32 {
            const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
            return @call(.{ .modifier = .always_inline }, heightFn, .{self});
        }

        fn getWidthImpl(ptr: *anyopaque) i32 {
            const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
            return @call(.{ .modifier = .always_inline }, widthFn, .{self});
        }

        const vtable = VTable{
            .setBackgroundPallete = setBackgroundPalleteImpl,
            .setFrontendPallete = setFrontendPalleteImpl,
            .setPixel = setPixelImpl,
            .setPixelAlternative = setPixelAlternativeImpl,
            .getHeight = getHeightImpl,
            .getWidth = getWidthImpl,
        };
    };

    return .{
        .ptr = pointer,
        .vtable = &gen.vtable,
    };
}

pub fn setForegroundPallete(self: *SimpleRenderer, color: u2) void {
    return self.vtable.setFrontendPallete(self.ptr, color);
}

pub fn setBackgroundPallete(self: *SimpleRenderer, color: u2) void {
    return self.vtable.setFrontendPallete(self.ptr, color);
}

pub fn setPixel(self: *SimpleRenderer, x: i32, y: i32) void {
    return self.vtable.setPixel(self.ptr, x, y);
}

pub fn setAltPixel(self: *SimpleRenderer, x: i32, y: i32) void {
    return self.vtable.setPixelAlternative(self.ptr, x, y);
}

pub fn getWidth(self: *SimpleRenderer) i32 {
    return self.vtable.getWidth(self.ptr);
}

pub fn getHeight(self: *SimpleRenderer) i32 {
    return self.vtable.getHeight(self.ptr);
}

pub fn reset(self: *SimpleRenderer) void {
    var x: i32 = 0;
    while (x < self.getWidth()) : (x += 1) {
        var y: i32 = 0;
        while (y < self.getHeight()) : (y += 1) {
            self.setPixel(x, y);
        }
    }
}

pub fn drawRect(self: *SimpleRenderer, x: i32, y: i32, width: u16, height: u16) void {
    const realX = std.math.clamp(x, 0, self.getWidth());
    const realY = std.math.clamp(y, 0, self.getHeight());
    const x2 = std.math.clamp(x + width, 0, self.getWidth());
    const y2 = std.math.clamp(y + height, 0, self.getHeight());

    var i = realX;
    while (i < x2) : (i += 1) {
        var j = realY;
        while (j < y2) : (j += 1) {
            self.setPixel(@intCast(i32, i), @intCast(i32, j));
        }
    }
}

pub fn blitBits(self: *SimpleRenderer, src: []const RendererVals.DrawPixel, dst_x: u8, dst_y: u8, width: u8, height: u8, src_x: usize, src_y: usize) void {
    _ = self;
    _ = src;
    _ = dst_x;
    _ = dst_y;
    _ = width;
    _ = height;
    _ = src_x;
    _ = src_y;
}

pub fn blitBytes(self: *SimpleRenderer, source: []const u8, dst_x: u8, dst_y: u8, width: u8, height: u8, src_x: usize, src_y: usize) void {
    const test_source = LocalMem.bitcastSlice(RendererVals.DrawPixel, source);
    std.debug.assert(test_source.len == source.len * 8);
    self.blitBits(test_source, dst_x, dst_y, width, height, src_x, src_y);
    _ = test_source;
    const min_x = std.math.clamp(dst_x, 0, self.getWidth());
    const max_x = std.math.clamp(dst_x + width - 1, 0, self.getWidth());
    const min_y = std.math.clamp(dst_y, 0, self.getHeight());
    const max_y = std.math.clamp(dst_y + height - 1, 0, self.getHeight());
    const source_start = src_y * width + src_x;
    var x: i32 = min_x;
    var y: i32 = min_y;

    for (source[source_start..]) |byte| {
        const commands = RendererVals.bytemaskToDraws(byte);
        for (commands) |cmd| {
            switch (cmd) {
                .background => self.setAltPixel(x, y),
                .foreground => self.setPixel(x, y),
            }
            if (x >= max_x) {
                y += 1;
                x = min_x;
            } else {
                x += 1;
            }
            if (y > max_y) {
                return;
            }
        }
    }
}

pub fn drawText(self: *SimpleRenderer, text: []const u8, x: u8, y: u8) void {
    var i: u8 = x;
    for (text) |byte| {
        var source_start: usize = (byte - 32);
        source_start = source_start << 3;
        if (i > self.getWidth()) return;
        self.blitBytes(&FONT, i, y, 8, 8, source_start, 0);
        i += 8;
    }
}
