const std = @import("std");

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

    pub fn shouldCollect(self: *const FileInfo) bool {
        if (std.fs.path.isAbsolute(self.RelativePath)) return false;

        const builtin_dirs = [_][]const u8{ "Samples/", "Presets/", "Backups/" };
        for (builtin_dirs) |dir| {
            if (std.mem.startsWith(u8, self.RelativePath, dir)) return false;
        }

        return switch (self.RelativePathType) {
            .AbletonCoreAudio,
            .AbletonPluginPreset,
            // .ExternalPluginPreset,
            .NA,
            => false,
            else => true,
        };
    }
};
