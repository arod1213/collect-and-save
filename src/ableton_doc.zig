const std = @import("std");
const Allocator = std.mem.Allocator;
const collect = @import("collect.zig");

// TODO: these definitions are wrong
pub const PathType = enum(u4) {
    NA = 0,
    External = 1, // this shows for some .wav files
    Recorded = 3,
    AbletonPluginData = 5,
    Internal = 6,
    AbletonBuiltin = 7,
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
    pub fn shouldCollect(self: *const FileInfo, _: Allocator, _: std.fs.Dir) bool {
        switch (self.RelativePathType) {
            .External => {},
            else => return false,
        }

        const file_types = [_][]const u8{
            ".wav",
            ".mp3",
            ".aif",
            ".flac",
            ".amxd",
            ".m4a",
            ".ogg",
            ".mp4",
            ".adg",
        };
        for (file_types) |ft| {
            if (std.mem.endsWith(u8, self.RelativePath, ft)) return true;
        }
        return false;
    }
};
