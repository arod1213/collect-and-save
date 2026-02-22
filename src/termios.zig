const std = @import("std");
const Allocator = std.mem.Allocator;
const print = std.debug.print;
const lib = @import("collect_and_save");
const Color = lib.Color;
const builtin = @import("builtin");

pub fn setup(handle: std.posix.fd_t) !std.posix.termios {
    const original = try std.posix.tcgetattr(handle);
    var settings = original;
    settings.lflag.ICANON = false;
    settings.lflag.ECHO = false;
    settings.cc[@intFromEnum(std.posix.V.MIN)] = 1;
    try std.posix.tcsetattr(handle, .NOW, settings);
    settings.cc[@intFromEnum(std.posix.V.TIME)] = 0;
    return original;
}

pub fn enableWrite(handle: std.posix.fd_t) !void {
    var settings = try std.posix.tcgetattr(handle);
    settings.lflag.ICANON = true;
    settings.lflag.ECHO = true;
    std.posix.tcsetattr(handle, .NOW, settings) catch {};
}

pub fn restore(handle: std.posix.fd_t, original: std.posix.termios) void {
    std.posix.tcsetattr(handle, .NOW, original) catch {};
}
