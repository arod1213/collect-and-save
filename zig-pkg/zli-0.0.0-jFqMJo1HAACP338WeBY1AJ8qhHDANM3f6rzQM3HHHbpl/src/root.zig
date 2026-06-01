const std = @import("std");
const parse = @import("parse.zig");
const assert = std.debug.assert;
const map = @import("map.zig");
const Allocator = std.mem.Allocator;

// parse based on struct order
pub const ArgPosition = enum { head, offset };
pub fn parseOrdered(comptime T: type, args: [][*:0]u8, comptime position: ArgPosition) !T {
    const info = @typeInfo(T);
    assert(info == .@"struct");

    if (args.len < 2 and position == .head) {
        return error.NoArgs;
    }

    const start_idx = if (position == .head) 1 else 0;
    var target: T = undefined;
    inline for (info.@"struct".fields, start_idx..) |field, idx| {
        const field_value = blk: {
            if (idx >= args.len) {
                if (field.defaultValue()) |fallback| {
                    break :blk fallback;
                }
                return error.MissingField;
            } else {
                const arg = args[idx];
                break :blk parse.strToT(field.type, std.mem.span(arg)) catch {
                    if (field.defaultValue()) |fallback| {
                        break :blk fallback;
                    }
                    return error.MissingField;
                };
            }
        };
        @field(target, field.name) = field_value;
    }
    return target;
}

// parse based on struct field name
pub fn parseNamed(comptime T: type, alloc: Allocator, args: [][*:0]u8) !T {
    const info = @typeInfo(T);
    assert(info == .@"struct");

    if (args.len < 2) {
        return error.NoArgs;
    }

    var table = try map.argsToMap(alloc, args);
    defer table.deinit();

    var target: T = undefined;
    inline for (info.@"struct".fields) |field| {
        const field_value = blk: {
            if (table.get(field.name)) |arg| {
                break :blk parse.strToT(field.type, arg) catch {
                    if (field.defaultValue()) |fallback| {
                        break :blk fallback;
                    }
                    return error.MissingField;
                };
            } else {
                if (field.defaultValue()) |fallback| {
                    break :blk fallback;
                }
                return error.MissingField;
            }
        };
        @field(target, field.name) = field_value;
    }
    return target;
}
