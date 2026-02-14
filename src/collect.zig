const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn shouldBeCollected(file_path: []const u8) bool {
    if (std.mem.containsAtLeast(u8, file_path, 1, "Application Support/Ableton")) return false;

    if (isStandardPreset(file_path)) return false;
    return !isFileCollected(file_path);
}

fn isStandardPreset(file_path: []const u8) bool {
    if (std.mem.containsAtLeast(u8, file_path, 1, "Ableton/Presets")) {
        return true;
    }
    const file_name = std.fs.path.basename(file_path);
    // TODO: extend for vst and clap support
    return std.mem.eql(u8, "Default.aupreset", file_name);
}

fn isFileCollected(path: []const u8) bool {
    return !std.mem.startsWith(u8, path, "../.");
}
