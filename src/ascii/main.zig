const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const types = @import("./types.zig");
pub const Color = types.Color;
pub const Style = types.Style;

pub fn clearScreen(w: *std.Io.Writer) !void {
    try w.print("\x1b[2J\x1b[H", .{});
    try w.flush();
}

pub fn readLine(r: *std.Io.Reader) ![]const u8 {
    if (try r.takeDelimiter('\n')) |text| {
        return text;
    }
    return error.NothingRead;
}
//
// pub fn prompt(w: *std.Io.Writer, text: []const u8) !void {
//     _ = try w.write(text);
//     try w.flush();
// }
pub fn prompt(w: *std.Io.Writer, text: []const u8) !void {
    try w.print("\n  {s}{s} {s}\n", .{
        Style.bold.code(),
        text,
        Style.reset.code(),
    });
    try w.flush();
}

pub fn enumOptions(comptime T: type, r: *std.Io.Reader, w: *std.Io.Writer) !T {
    const info = @typeInfo(T);
    assert(info == .@"enum");
    const fields = info.@"enum".fields;
    const count = fields.len;

    var i: usize = 0;
    var iter: usize = 0;
    while (true) : (iter += 1) {
        if (iter != 0) try w.print("\x1b[{d}A", .{count});

        inline for (fields, 0..) |field, selected| {
            if (i == selected) {
                try w.print("\r\x1b[2K{s}{s}  > {s}{s}\n", .{
                    Color.cyan.code(),
                    Style.bold.code(),
                    field.name,
                    Color.reset.code(),
                });
            } else {
                try w.print("\r\x1b[2K{s}    {s}{s}\n", .{
                    Style.dimmed.code(),
                    field.name,
                    Color.reset.code(),
                });
            }
        }
        try w.flush();

        var buf: [3]u8 = undefined;

        const bytes_read = try r.readSliceShort(buf[0..1]);
        if (bytes_read == 0) return error.EOF;
        if (buf[0] == 10) {
            inline for (fields, 0..) |field, idx| {
                if (idx == i) {
                    return @field(T, field.name);
                }
            }
            return error.NothingSelected;
        }

        _ = try r.readSliceShort(buf[1..buf.len]);
        const input = buf[0..buf.len];

        if (std.mem.eql(u8, &.{ 27, 91, 65 }, input)) {
            if (i > 0) i -|= 1 else {}
        } else if (std.mem.eql(u8, &.{ 27, 91, 66 }, input)) {
            const increment = i +| 1;
            if (increment < count) i = increment else {}
        }
    }
}
