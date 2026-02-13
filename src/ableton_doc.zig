const std = @import("std");
const Allocator = std.mem.Allocator;
const collect = @import("collect.zig");
const xml = @import("xml");
const Dir = std.Io.Dir;

pub const PathType = enum(u3) {
    NA = 0,
    External = 1,
    Recorded = 3,
    AbletonPluginData = 5,
    Internal = 6,
    AbletonBuiltin = 7,
};

pub const AbletonVersion = enum(u8) {
    nine = 9,
    ten = 10,
    eleven = 11,
    twelve = 12,
};

pub const Header = struct {
    MajorVersion: u8,
    MinorVersion: []const u8,
    Creator: []const u8,
    // SchemaChangeCount: []const u8, // not avail in Live 9

    pub fn version(self: Header) ?AbletonVersion {
        if (std.mem.indexOf(u8, self.MinorVersion, ".")) |idx| {
            const text = self.MinorVersion[0..idx];
            const digit = std.fmt.parseInt(u8, text, 10) catch return null;
            return std.enums.fromInt(AbletonVersion, digit);
        }
        return null;
    }
};

fn Value(comptime T: type) type {
    return struct {
        Value: T,
    };
}

pub fn shouldCollect(io: std.Io, alloc: Allocator, cwd: std.Io.Dir, path_type: PathType, filepath: []const u8) bool {
    switch (path_type) {
        .External => {},
        else => return false,
    }

    const file_exists = collect.fileInDir(io, alloc, cwd, Dir.path.basename(filepath)) catch false;
    if (file_exists) {
        return false;
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
        if (std.mem.endsWith(u8, filepath, ft)) return true;
    }
    return false;
}

pub const Ableton11 = struct {
    RelativePathType: Value(PathType) = .{ .Value = .NA },
    RelativePath: Value([]const u8),
    Path: Value([]const u8),

    LivePackName: Value([]const u8),
    LivePackId: Value([]const u8),
    OriginalFileSize: Value(u64),

    pub fn filepath(self: Ableton11, _: Allocator) []const u8 {
        return self.Path.Value;
    }

    pub fn path_type(self: Ableton11) PathType {
        return self.RelativePathType.Value;
    }

    pub fn key(self: Ableton11) []const u8 {
        return self.Path.Value;
    }

    pub fn format(self: Ableton11, w: *std.Io.Writer) !void {
        const path = self.filepath();
        _ = try w.print("{s}\n", .{Dir.path.basename(path)});
        _ = try w.print("\t@: {s}\n", .{path});
        _ = try w.print("\ttype: {any}\n", .{self.RelativePathType.Value});
    }
};

pub const Ableton10 = struct {
    Name: Value([]const u8),
    RelativePath: []RelativePathElement,
    RelativePathType: Value(PathType),
    LivePackName: Value([]const u8),
    LivePackId: Value([]const u8),

    pub fn name(self: Ableton10) []const u8 {
        return self.Name.Value;
    }

    pub fn filepath(self: Ableton10, alloc: Allocator) []const u8 {
        std.mem.sort(RelativePathElement, self.RelativePath, {}, pathElementLessThan);
        var full_path: []const u8 = "";
        for (self.RelativePath) |rp| {
            full_path = Dir.path.join(alloc, &[_][]const u8{ full_path, rp.Dir }) catch continue;
        }
        return Dir.path.join(alloc, &[_][]const u8{ full_path, self.Name.Value }) catch return full_path;
    }

    pub fn path_type(self: Ableton10) PathType {
        return self.RelativePathType.Value;
    }

    pub fn key(self: Ableton10) []const u8 {
        return self.Name.Value;
    }

    pub fn format(self: Ableton10, w: *std.Io.Writer) !void {
        _ = try w.print("{s}\n", .{Dir.path.basename(self.name())});
        _ = try w.print("\t@: {s}\n", .{self.name()});
        _ = try w.print("\ttype: {any}\n", .{self.RelativePathType.Value});
        for (self.RelativePath) |elem| {
            _ = try w.print("\telem: ID: {d} in {s}\n", .{ elem.Id, elem.Dir });
        }
    }
};

pub fn pathElementLessThan(_: void, self: RelativePathElement, other: RelativePathElement) bool {
    return self.Id < other.Id;
}

const RelativePathElement = struct {
    Id: usize = 0,
    Dir: []const u8,
};
