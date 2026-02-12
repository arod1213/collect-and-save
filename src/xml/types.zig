const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const print = std.debug.print;
const c = @cImport({
    @cInclude("libxml/parser.h");
    @cInclude("libxml/tree.h");
});

fn cPtrToNull(comptime T: type, x: [*c]T) ?T {
    if (x == null) {
        return null;
    }
    return x.*;
}

// FIELD PARSE TYPES
pub const Doc = struct {
    ptr: *c.xmlDoc,
    root: ?Node,

    pub fn initFromBuffer(buffer: []const u8) !Doc {
        const doc = c.xmlReadMemory(@ptrCast(buffer), @intCast(buffer.len), null, null, 0);
        if (doc == null) return error.ParseFailed;

        const root = if (c.xmlDocGetRootElement(doc)) |r| Node.init(r.*) else null;
        return .{
            .ptr = doc,
            .root = root,
        };
    }

    pub fn init(path: []const u8) !Doc {
        const doc = c.xmlReadFile(@ptrCast(path), null, 0);
        if (doc == null) return error.ParseFailed;

        const root = if (c.xmlDocGetRootElement(doc)) |r| Node.init(r.*) else null;
        return .{
            .ptr = doc,
            .root = root,
        };
    }

    pub fn deinit(self: *Doc) void {
        c.xmlFreeDoc(self.ptr);
    }
};

pub const NodeType = enum(c_uint) {
    Element = c.XML_ELEMENT_NODE,
    Atrribute = c.XML_ATTRIBUTE_NODE,
    Text = c.XML_TEXT_NODE,
    CDataSection = c.XML_CDATA_SECTION_NODE,
    Comment = c.XML_COMMENT_NODE,
    Document = c.XML_DOCUMENT_NODE,
    PI = c.XML_PI_NODE,
    EntityRef = c.XML_ENTITY_REF_NODE,
    DocumentFrag = c.XML_DOCUMENT_FRAG_NODE,
};

pub const Node = struct {
    ptr: c.xmlNode,
    name: []const u8,
    next_node: ?c.xmlNode,
    child_node: ?c.xmlNode,
    parent_node: ?c.xmlNode,
    node_type: NodeType,

    pub fn init(ptr: c.xmlNode) Node {
        const node_type = std.meta.intToEnum(NodeType, ptr.type) catch .Text;
        return .{
            .ptr = ptr,
            .name = std.mem.span(ptr.name),
            .child_node = cPtrToNull(c.xmlNode, ptr.children),
            .parent_node = cPtrToNull(c.xmlNode, ptr.parent),
            .next_node = cPtrToNull(c.xmlNode, ptr.next),
            .node_type = node_type,
        };
    }

    pub fn getProperty(self: *const Node, name: [:0]const u8) ![]const u8 {
        // TODO check this
        const value = c.xmlGetProp(@ptrCast(&self.ptr), @ptrCast(name.ptr));
        if (value == null) {
            return error.InvalidField;
        }
        return std.mem.span(value);
    }

    pub fn parent(self: *const Node) ?Node {
        return if (self.parent) |n| Node.init(n) else null;
    }

    pub fn children(self: *const Node) ?Node {
        return if (self.child_node) |n| Node.init(n) else null;
    }

    pub fn next(self: *const Node) ?Node {
        return if (self.next_node) |n| Node.init(n) else null;
    }
};
