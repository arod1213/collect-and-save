const std = @import("std");
const Allocator = std.mem.Allocator;
const collect = @import("collect.zig");

pub const PathType = enum(u3) {
    NA = 0,
    External = 1,
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

    pub fn format(self: FileInfo, w: *std.Io.Writer) !void {
        _ = try w.print("{s}\n", .{std.fs.path.basename(self.Path)});
        _ = try w.print("\t@: {s}\n", .{self.Path});
        _ = try w.print("\ttype: {any}\n", .{self.RelativePathType});
        _ = try w.print("\tsize: {d}\n\n", .{self.OriginalFileSize});
    }

    // TODO: make this more robust
    pub fn shouldCollect(self: *const FileInfo, _: Allocator, _: std.fs.Dir) bool {
        switch (self.RelativePathType) {
            .External => {},
            else => return false,
        }

        const file_types = [_][]const u8{
            // audio types
            ".wav",
            ".aif",
            ".mp3",
            ".m4a",
            ".mp4",
            ".flac",
            ".ogg",
            // preset types
            ".amxd",
            ".adg",
        };
        for (file_types) |ft| {
            if (std.mem.endsWith(u8, self.RelativePath, ft)) return true;
        }
        return false;
    }
};
