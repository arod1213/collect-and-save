const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const print = std.debug.print;

pub const c = @import("lib.zig").c;
pub const write = @import("write.zig");
pub const parse = @import("parse.zig");
pub const find = @import("find.zig");
pub const types = @import("types.zig");

const Doc = types.Doc;
const Node = types.Node;

pub fn parserSetup() void {
    c.xmlInitParser();
}
pub fn parserDeinit() void {
    c.xmlCleanupParser();
}
