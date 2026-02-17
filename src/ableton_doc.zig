const std = @import("std");
const Allocator = std.mem.Allocator;
const collect = @import("collect.zig");

// TODO: these definitions are wrong
pub const PathType = enum(u4) {
    NA = 0,
    ExternalPluginPreset = 1, // this shows for some .wav files
    Recorded = 3,
    AbletonPluginPreset = 5,
    AbletonRackPreset = 6,
    AbletonCoreAudio = 7,
};

pub const FileInfo = struct {
    RelativePathType: PathType = .NA,
    RelativePath: []const u8,
    Path: []const u8,

    // Type: usize,

    LivePackName: []const u8,
    LivePackId: []const u8,
    OriginalFileSize: u64,

    // TODO: when field name is wrong garbage gets put there
    pub fn format(self: FileInfo, w: *std.Io.Writer) !void {
        try w.print("Rel: {s}\nPath {s}\nRelType {any}\nFileSize {d}\n\n", .{ self.RelativePath, self.Path, self.RelativePathType, self.OriginalFileSize });
    }

    // TODO: make this more robust
    pub fn shouldCollect(self: *const FileInfo, alloc: Allocator, cwd: std.fs.Dir) bool {
        if (std.fs.path.isAbsolute(self.RelativePath)) return false;

        switch (self.RelativePathType) {
            .Recorded => return false,
            else => {},
        }

        const file_exists = collect.fileInDir(alloc, cwd, std.fs.path.basename(self.RelativePath)) catch false;
        if (file_exists) {
            return false;
        }

        const builtin_dirs = [_][]const u8{ "Samples/", "Presets/", "Backups/" }; // ./ included for inside the file
        for (builtin_dirs) |dir| {
            if (std.mem.startsWith(u8, self.RelativePath, dir)) return false;
        }

        const is_relative = std.mem.startsWith(u8, self.RelativePath, "../");

        const file_types = [_][]const u8{ ".wav", ".mp3", ".aif", ".flac", ".amxd", ".m4a", ".ogg", ".mp4" };
        for (file_types) |ft| {
            if (std.mem.endsWith(u8, self.RelativePath, ft) and is_relative) return true;
        }
        return false;
    }
};
