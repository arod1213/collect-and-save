const std = @import("std");
const zxml = @import("zxml");

pub const Other = struct {
    weirdness: []const u8 = "very",
    info: ?[]const u8 = null,
};

pub const Abc = struct {
    name: []const u8 = "aidan",
    old: bool,
    other: Other = .{},
    age: usize,
};

pub fn main() !void {
    zxml.parserSetup();
    defer zxml.parserDeinit();

    const alloc = std.heap.page_allocator;

    var doc = try zxml.types.Doc.new();
    // defer doc.deinit(); // -> double free ??

    const node = try zxml.types.Node.new("hello", null);
    node.setProperty("Value", "ABC");
    try doc.setRoot(node);
    _ = try zxml.types.Node.new("son", node);

    const x: Abc = .{ .age = 55, .old = true };
    const sub_child = try zxml.write.structToNode(Abc, alloc, x);
    sub_child.attach(&node);

    try doc.save("./output.xml");
}
