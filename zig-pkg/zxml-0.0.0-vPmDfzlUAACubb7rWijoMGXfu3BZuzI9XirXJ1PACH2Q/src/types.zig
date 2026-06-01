const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const print = std.debug.print;
const c = @import("lib.zig").c;

pub const ParseType = enum(c_uint) {
    huge = c.XML_PARSE_HUGE,
    compact = c.XML_PARSE_COMPACT,
    big_lines = c.XML_PARSE_BIG_LINES,
};

pub const Doc = struct {
    ptr: *c.xmlDoc,
    root: ?Node,

    const Self = @This();
    pub fn new() !Self {
        return .{
            .ptr = c.xmlNewDoc("1.0"),
            .root = null,
        };
    }

    pub fn save(self: *const Doc, filename: []const u8) !void {
        const res = c.xmlSaveFormatFileEnc(@ptrCast(filename), self.ptr, "UTF-8", 0);
        if (res < 0) return error.FailedSave;
    }

    pub fn setRoot(self: *Self, node: Node) !void {
        _ = c.xmlDocSetRootElement(self.ptr, node.ptr);
        self.root = node;
    }

    pub fn initFromBuffer(buffer: []const u8, parse_type: ParseType) !Self {
        const doc = c.xmlReadMemory(@ptrCast(buffer), @intCast(buffer.len), null, null, @intFromEnum(parse_type));
        if (doc == null) return error.ParseFailed;

        const root_elem = c.xmlDocGetRootElement(doc);
        const root = if (root_elem != null) Node.init(root_elem.*) else null;
        return .{
            .ptr = doc,
            .root = root,
        };
    }

    pub fn init(path: []const u8) !Self {
        const doc = c.xmlReadFile(@ptrCast(path), null, c.XML_PARSE_HUGE);
        if (doc == null) return error.ParseFailed;

        const root_elem = c.xmlDocGetRootElement(doc);
        const root = if (root_elem != null) Node.init(root_elem) else null;
        return .{
            .ptr = doc,
            .root = root,
        };
    }

    pub fn deinit(self: *Self) void {
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
    ptr: [*c]c.xmlNode,
    name: []const u8,
    next_node: [*c]c.xmlNode = null,
    child_node: [*c]c.xmlNode = null,
    parent_node: [*c]c.xmlNode = null,
    node_type: NodeType,

    pub fn new(name: []const u8, parent_node: ?Node) !Node {
        const new_node = blk: {
            if (parent_node) |p| {
                const node = c.xmlNewChild(p.ptr, null, @ptrCast(name), null);
                if (node == null) return error.FailedToCreate;
                break :blk node;
            } else {
                const node = c.xmlNewNode(null, @ptrCast(name));
                if (node == null) return error.FailedToCreate;
                break :blk node;
            }
        };

        const node_type = std.meta.intToEnum(NodeType, new_node.*.type) catch .Text;

        return .{
            .parent_node = if (parent_node) |p| p.ptr else null,
            .ptr = new_node,
            .name = name,
            .node_type = node_type,
        };
    }

    pub fn attach(self: *const Node, parent_node: *const Node) void {
        _ = c.xmlAddChild(parent_node.ptr, self.ptr);
    }

    pub fn init(ptr: [*c]c.xmlNode) Node {
        assert(ptr != null);
        const obj = ptr.*;
        const node_type = std.meta.intToEnum(NodeType, obj.type) catch .Text;
        return .{
            .ptr = ptr,
            .name = std.mem.span(obj.name),
            .child_node = obj.children,
            .parent_node = obj.parent,
            .next_node = obj.next,
            .node_type = node_type,
        };
    }

    pub fn deinit(self: *Node) void {
        c.xmlFreeNode(self.ptr);
    }

    pub fn setProperty(self: *const Node, name: []const u8, value: []const u8) void {
        _ = c.xmlSetProp(self.ptr, @ptrCast(name), @ptrCast(value));
    }

    pub fn getProperty(self: *const Node, name: [:0]const u8) ![]const u8 {
        // TODO check this
        const value = c.xmlGetProp(self.ptr, @ptrCast(name.ptr));
        if (value == null) {
            return error.InvalidField;
        }
        return std.mem.span(value);
    }

    pub fn parent(self: *const Node) ?Node {
        return if (self.parent != null) Node.init(self.parent) else null;
    }

    pub fn children(self: *const Node) ?Node {
        return if (self.child_node != null) Node.init(self.child_node) else null;
    }

    pub fn next(self: *const Node) ?Node {
        return if (self.next_node != null) Node.init(self.next_node) else null;
    }
};
