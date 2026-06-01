const std = @import("std");

pub fn simpleTypeName(comptime T: type) []const u8 {
    const full = @typeName(T);
    const idx = std.mem.lastIndexOf(u8, full, ".") orelse return full;
    // TODO: this could break
    return full[idx + 1 ..];
}
