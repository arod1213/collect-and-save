const std = @import("std");
const zli = @import("zli");

const Input = struct {
    a: u8,
    b: []const u8 = "yes",

    pub fn format(self: Input, w: *std.Io.Writer) !void {
        try w.print("a is {any}\n", .{self.a});
        try w.print("b is {s}\n", .{self.b});
    }
};

pub fn main() !void {
    const args = std.os.argv;
    // const input = try zli.parseOrdered(Input, args, .start);
    const alloc = std.heap.page_allocator;
    const input = try zli.parseNamed(Input, alloc, args);
    std.log.info("{f}", .{input});
}
