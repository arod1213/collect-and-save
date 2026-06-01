const std = @import("std");

pub fn strToT(comptime T: type, val: []const u8) !T {
    const info = @typeInfo(T);

    return switch (info) {
        .int => try std.fmt.parseInt(T, val, 10),
        .float => try std.fmt.parseFloat(T, val),
        .optional => |opt| if (val.len == 0) return null else try strToT(
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
            else => unreachable, // UNSUPPORTED -> requires separator logic
        },
        .bool => {
            if (std.ascii.eqlIgnoreCase("true", val)) {
                return true;
            }
            if (std.ascii.eqlIgnoreCase("false", val)) {
                return false;
            }
            const digit = try std.fmt.parseInt(u2, val, 10);
            if (digit == 0) {
                return false;
            } else if (digit == 1) {
                return true;
            }
            return error.InvalidBool;
        },
        .null, .void => return val.len == 0,
        else => unreachable,
    };
}
