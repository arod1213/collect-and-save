const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const print = std.debug.print;
const c = @cImport({
    @cInclude("libxml/parser.h");
    @cInclude("libxml/tree.h");
});

pub fn mainDoc(path: []const u8) !void {
    var doc = try Doc.init(path);
    defer doc.deinit();

    if (doc.root == null or doc.root.?.child_node == null) return error.NoRoot;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const samples = try findNamedNodes(alloc, doc.root.?, "FileRef");
    std.log.info("found {d} samples", .{samples.len});
}

fn findNamedNodes(alloc: Allocator, head: Node, name: []const u8) ![]Node {
    var list = try std.ArrayList(Node).initCapacity(alloc, 5);
    defer list.deinit(alloc);

    var start: ?Node = head;
    while (start) |next| : (start = next.next()) {
        try saveNamedNodes(alloc, &list, next, name);
        // std.log.info("name {s}", .{next.name});
        // if (std.mem.eql(u8, next.name, name)) {
        //     try list.append(alloc, next);
        // }
    }

    return try list.toOwnedSlice(alloc);
}

fn saveNamedNodes(alloc: Allocator, list: *std.ArrayList(Node), head: Node, name: []const u8) !void {
    var start: ?Node = head;
    while (start) |next| : (start = next.next()) {
        std.log.info("name {s}", .{next.name});
        if (std.mem.eql(u8, next.name, name)) {
            try list.append(alloc, next);
        }
        if (next.children()) |child| {
            try saveNamedNodes(alloc, list, child, name);
        }
    }
}

fn findNextNode(head: Node, name: []const u8) ?Node {
    var start: ?Node = head;
    while (start) |next| : (start = next.next()) {
        if (std.mem.eql(u8, next, name)) {
            return next;
        }
    }
    return null;

    //     while (current) |n| : (current = n.next) {
    //         try printPaths(n, w);
    //         try walkNode(n.children, w);
    //     }
}

fn parseNodeToT(comptime T: type, node: *const Node) !T {
    const info = @typeInfo(T);
    assert(info == .@"struct");

    var target: T = undefined;
    var child = node.children();
    while (child) |ch| : (child = ch.next()) {
        const value = ch.getProperty("Value") catch continue;
        inline for (info.@"struct".fields) |field| {
            if (std.ascii.eqlIgnoreCase(field.name, ch.name)) {
                const variable = valToT(field.type, value) catch blk: {
                    if (field.defaultValue()) |def| {
                        break :blk def;
                    }
                    return error.MissingField;
                };
                @field(target, field.name) = variable;
            }
        }
    }
    return target;
}

pub const Doc = struct {
    ptr: *c.xmlDoc,
    root: ?Node,

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

fn cPtrToNull(comptime T: type, x: [*c]T) ?T {
    if (x == null) {
        return null;
    }
    return x.*;
}

pub const Node = struct {
    ptr: c.xmlNode,
    name: []const u8,
    next_node: ?c.xmlNode,
    child_node: ?c.xmlNode,
    parent_node: ?c.xmlNode,

    pub fn init(ptr: c.xmlNode) Node {
        return .{
            .ptr = ptr,
            .name = std.mem.span(ptr.name),
            .child_node = cPtrToNull(c.xmlNode, ptr.children),
            .parent_node = cPtrToNull(c.xmlNode, ptr.parent),
            .next_node = cPtrToNull(c.xmlNode, ptr.next),
        };
    }

    pub fn getProperty(self: *const Node, name: [*c]c.xmlChar) ![]const u8 {
        const value = c.xmlGetProp(self.ptr, name);
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

fn valToT(comptime T: type, val: []const u8) !T {
    const info = @typeInfo(T);
    return switch (info) {
        .int => try std.fmt.parseInt(T, val, 10),
        .float => try std.fmt.parseFloat(T, val),
        .@"enum" => blk: {
            const tag_info = @typeInfo(info.@"enum".tag_type);
            switch (tag_info) {
                .int, .float => {
                    const digit = std.fmt.parseInt(info.@"enum".tag_type, val, 10) catch {
                        // fallback to parse by string name
                        break :blk try std.meta.stringToEnum(T, val);
                    };
                    break :blk try std.meta.intToEnum(T, digit);
                },
                else => unreachable, // unsupported for now
            }
            const digit = try std.fmt.parseInt(info.@"enum".tag_type, val, 10);
            break :blk try std.meta.intToEnum(T, digit);
        },
        .pointer => |x| switch (x.child) {
            u8 => val,
            else => unreachable, // unsupported for now
        },
        else => unreachable,
    };
}

// fn printPaths(node: *c.xmlNode, w: *std.Io.Writer) !void {
//     if (!std.mem.eql(u8, std.mem.span(node.name), "FileRef")) return;
//     const info = try parseNodeValues(FileInfo, node);
//     try w.print("{f}", .{info});
//
//     // var child = node.children;
//     // while (child) |ch| : (child = ch.*.next) {
//     //     if (child == null) break;
//     //
//     //     // if (ch.*.type == c.XML_ELEMENT_NODE) {
//     //     //     std.log.info("  child: {s}", .{ch.*.name});
//     //     // }
//     //     const value = c.xmlGetProp(ch, "Value");
//     //     if (value != null) {
//     //         // defer c.xmlFreeCh(value);
//     //         std.log.info("{s}: {s}", .{ ch.*.name, value });
//     //     }
//     // }
// }

// fn walkNode(node: ?*c.xmlNode, w: *std.Io.Writer) !void {
//     var current = node;
//
//     while (current) |n| : (current = n.next) {
//         try printPaths(n, w);
//         try walkNode(n.children, w);
//     }
// }

// <SampleRef>
//         <FileRef>
//                 <RelativePathType Value="1" />
//                 <RelativePath Value="../../../../../Documents/Sample Libraries/M-Phazes Drums and Samples/TAKE A BREAK BY WU10 (DRUM BREAKS)/0NE SHOTS AND EXTRAS/CRACKLE2.wav" />
//                 <Path Value="/Users/aidan/Documents/Sample Libraries/M-Phazes Drums and Samples/TAKE A BREAK BY WU10 (DRUM BREAKS)/0NE SHOTS AND EXTRAS/CRACKLE2.wav" />
//                 <Type Value="2" />
//                 <LivePackName Value="" />
//                 <LivePackId Value="" />
//                 <OriginalFileSize Value="2352584" />
//                 <OriginalCrc Value="6887" />
//         </FileRef>
//         <LastModDate Value="1603822758" />
//         <SourceContext>
//                 <SourceContext Id="0">
//                         <OriginalFileRef>
//                                 <FileRef Id="10">
//                                         <RelativePathType Value="1" />
//                                         <RelativePath Value="../../../../../Documents/Sample Libraries/M-Phazes Drums and Samples/TAKE A BREAK BY WU10 (DRUM BREAKS)/0NE SHOTS AND EXTRAS/CRACKLE2.wav" />
//                                         <Path Value="/Users/aidan/Documents/Sample Libraries/M-Phazes Drums and Samples/TAKE A BREAK BY WU10 (DRUM BREAKS)/0NE SHOTS AND EXTRAS/CRACKLE2.wav" />
//                                         <Type Value="2" />
//                                         <LivePackName Value="" />
//                                         <LivePackId Value="" />
//                                         <OriginalFileSize Value="2352584" />
//                                         <OriginalCrc Value="6887" />
//                                 </FileRef>
//                         </OriginalFileRef>
//                         <BrowserContentPath Value="query:Find#FileId_315072" />
//                 </SourceContext>
//         </SourceContext>
//         <SampleUsageHint Value="0" />
//         <DefaultDuration Value="588000" />
//         <DefaultSampleRate Value="44100" />
// </SampleRef>
