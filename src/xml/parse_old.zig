const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const print = std.debug.print;
const c = @cImport({
    @cInclude("libxml/parser.h");
    @cInclude("libxml/tree.h");
});

const types = @import("./types.zig");
pub const Doc = types.Doc;
pub const Node = types.Node;

// const Info = struct {
//     field_type: type,
//     name: []const u8,
// };
// pub const ValueType = union(enum) {
//     attribute: Info,
//     child: Info,
//     pub fn parse(self: ValueType, comptime T: type, node: Node) !T {
//         switch (self) {
//             .attribute => |attr| {
//                 const value_str = try node.getProperty(@ptrCast(attr.name));
//                 return try valToT(attr.field_type, value_str);
//             },
//             .child => |x| {
//                 var child = node.children();
//                 while (child) |ch| : (child = ch.next()) {
//                     switch (ch.node_type) {
//                         .Element => {},
//                         else => continue,
//                     }
//                     return x;
//                     // TODO: how the fuck do i parse this
//                 }
//             },
//         }
//     }
// };

// TODO: IMPORTANT
// loop over fields
// if field type is non struct - parse as property
// else parse as child
pub fn Attribute(comptime T: type) type {
    return struct {
        value: T,
        pub const is_xml_attr = true;
    };
}

fn getChild(parent: Node, field_name: []const u8) ?Node {
    var child = parent.children();
    while (child) |ch| : (child = ch.next()) {
        switch (ch.node_type) {
            .Element => {},
            else => continue,
        }
        std.log.info("looking at node {s}", .{ch.name});
        if (std.mem.eql(u8, field_name, ch.name)) {
            return ch;
        }
    }
    return null;
}
fn getProperty(comptime T: type, node: Node, property_name: []const u8) !T {
    assert(@typeInfo(T) != .@"struct");

    const val_str = try node.getProperty(@ptrCast(property_name));
    return try valToT(T, val_str);
}

pub fn getParam(comptime T: type, alloc: Allocator, node: Node, field_name: ?[]const u8) !T {
    const info = @typeInfo(T);

    switch (info) {
        .@"struct" => |s| {
            var target: T = undefined;
            _ = &target;

            var map = std.StringHashMap(bool).init(alloc);
            defer map.deinit();

            inline for (s.fields) |field| {
                const value = blk: {
                    // ONLY PARSE VALUE INSIDE
                    if (@hasDecl(field.type, "is_xml_attr")) {
                        const attr_type = @FieldType(field.type, "value");
                        const value = try getProperty(attr_type, node, field.name);
                        const attribute = Attribute(attr_type){ .value = value };
                        break :blk attribute;
                    } else {
                        const child_node = getChild(node, field.name) orelse return error.MissingStructField;
                        const value = try getParam(field.type, alloc, child_node, field.name);
                        break :blk value;
                    }
                };

                @field(target, field.name) = value;
                try map.put(field.name, true);
            }

            inline for (info.@"struct".fields) |field| {
                _ = map.get(field.name) orelse {
                    std.log.err("missing {s}", .{field.name});
                    return error.MissingField;
                };
            }
            return target;
        },
        .array => |arr| {
            const K = arr.child;
            var list: [arr.len]K = undefined;
            const ch_name = switch (@typeInfo(K)) {
                .@"struct" => null,
                else => field_name,
            };
            var child: ?Node = node.children();
            var pos: usize = 0;
            while (child) |ch| : (child = ch.next()) {
                list[pos] = try getParam(K, alloc, ch, ch_name);
                pos += 1;
            }
            if (pos != arr.len) {
                return error.InvalidFieldCount;
            }
            return list;
        },
        .pointer => |ptr| {
            const K = ptr.child;
            var list = try std.ArrayList(K).initCapacity(alloc, 15);
            errdefer list.deinit(alloc);

            const ch_info = @typeInfo(K);
            const ch_name = switch (ch_info) {
                .@"struct" => null,
                else => field_name,
            };

            var child: ?Node = node.children();
            while (child) |ch| : (child = ch.next()) {
                const val = try getParam(K, alloc, ch, ch_name);
                try list.append(alloc, val);
            }

            return try list.toOwnedSlice(alloc);
        },

        else => {
            if (field_name) |name| {
                const value = try node.getProperty(@ptrCast(name));
                return try valToT(T, value);
            } else {
                return error.NoFieldName;
            }
        },
    }
}

fn valToT(comptime T: type, val: []const u8) !T {
    const info = @typeInfo(T);

    return switch (info) {
        .int => try std.fmt.parseInt(T, val, 10),
        .float => try std.fmt.parseFloat(T, val),
        .optional => |opt| if (val.len == 0) return null else try valToT(
            opt.child,
            val,
        ),
        .@"enum" => {
            const tag_info = @typeInfo(info.@"enum".tag_type);
            switch (tag_info) {
                .int, .float => {
                    const digit = std.fmt.parseInt(info.@"enum".tag_type, val, 10) catch {
                        // fallback to parse by string name
                        return std.meta.stringToEnum(T, val) orelse error.InvalidEnumTag;
                    };
                    return try std.meta.intToEnum(T, digit);
                },
                else => unreachable, // unsupported for now
            }
            const digit = try std.fmt.parseInt(info.@"enum".tag_type, val, 10);
            return try std.meta.intToEnum(T, digit);
        },
        .pointer => |x| switch (x.child) {
            u8 => val,
            else => unreachable, // unsupported for now
        },
        else => unreachable,
    };
}
