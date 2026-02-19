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

pub fn getParam(comptime T: type, alloc: Allocator, node: Node, field_name: ?[]const u8) !T {
    const info = @typeInfo(T);

    switch (info) {
        .@"struct" => |s| {
            var target: T = undefined;
            var child: ?Node = node.children();

            var map = std.StringHashMap(bool).init(alloc);
            defer map.deinit();

            inline for (s.fields) |field| {
                std.log.info("seraching for {s} {any}", .{ field.name, field.type });
                while (child) |ch| : (child = ch.next()) {
                    std.log.info("looking at {s}", .{ch.name});
                    const val = getParam(field.type, alloc, ch, field.name) catch |e| {
                        if (std.mem.eql(u8, field.name, "Value")) {
                            std.log.err("failed to parse Value because: {any}", .{e});
                        }
                        return e;
                    };
                    @field(target, field.name) = val;
                    try map.put(field.name, true);
                }
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
            var child: ?Node = node;
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

            var child: ?Node = node;
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
