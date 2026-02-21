const std = @import("std");
const Allocator = std.mem.Allocator;
const print = std.debug.print;
const lib = @import("collect_and_save");
const Color = lib.Color;
const builtin = @import("builtin");

pub fn setup(handle: std.posix.fd_t) !void {
    var settings = try std.posix.tcgetattr(handle);
    settings.lflag.ICANON = false;
    settings.lflag.ECHO = false;
    _ = try std.posix.tcsetattr(handle, std.posix.TCSA.NOW, settings);
}
