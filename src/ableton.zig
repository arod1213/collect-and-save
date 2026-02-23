const std = @import("std");
const Allocator = std.mem.Allocator;
const collect = @import("collect.zig");
const xml = @import("xml");

pub const PathType = enum(u3) {
    NA = 0,
    External = 1,
    Internal = 3,
    AbletonPluginData = 5,
    UserLibrary = 6,
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
            return std.meta.intToEnum(AbletonVersion, digit) catch return null;
        }
        return null;
    }
};

// generic across ableton versions
pub const AbletonFile = struct {
    file_name: []const u8,
    file_path: []const u8,
    file_size: u64,
    path_type: PathType,

    pub fn format(self: AbletonFile, w: *std.Io.Writer) !void {
        _ = try w.print("{s}\n", .{self.file_path});
        _ = try w.print("\t@: {s}\n", .{self.file_name});
        _ = try w.print("\ttype: {any}\n", .{self.path_type});
    }
};

fn Value(comptime T: type) type {
    return struct {
        Value: T,
    };
}

pub fn shouldCollect(alloc: Allocator, cwd: std.fs.Dir, path_type: PathType, filepath: []const u8) bool {
    switch (path_type) {
        .External, .UserLibrary => {},
        else => return false,
    }

    const file_exists = collect.fileInDir(alloc, cwd, std.fs.path.basename(filepath)) catch false;
    if (file_exists) {
        return false;
    }

    const ext = std.fs.path.extension(filepath);
    if (ext.len < 2) return false;

    const stem = ext[1..];

    if (std.meta.stringToEnum(collect.FileExt, stem)) {
        return true;
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

    pub fn asAbletonFile(self: Ableton11, _: Allocator) AbletonFile {
        return .{
            .file_name = std.fs.path.basename(self.Path.Value),
            .file_path = self.Path.Value,
            .file_size = self.OriginalFileSize.Value,
            .path_type = self.RelativePathType.Value,
        };
    }

    pub fn filepath(self: Ableton11, _: Allocator) []const u8 {
        return self.Path.Value;
    }

    pub fn pathType(self: Ableton11) PathType {
        return self.RelativePathType.Value;
    }

    pub fn key(self: Ableton11) []const u8 {
        return self.Path.Value;
    }

    pub fn format(self: Ableton11, w: *std.Io.Writer) !void {
        const path = self.Path.Value;
        _ = try w.print("{s}\n", .{std.fs.path.basename(path)});
        _ = try w.print("\t@: {s}\n", .{path});
        _ = try w.print("\ttype: {any}\n", .{self.RelativePathType.Value});
    }
};

const SearchHint = struct {
    FileSize: Value(u64),
};

pub const Ableton10 = struct {
    Name: Value([]const u8),
    RelativePath: []RelativePathElement,
    RelativePathType: Value(PathType),
    LivePackName: Value([]const u8),
    LivePackId: Value([]const u8),
    SearchHint: SearchHint,

    pub fn asAbletonFile(self: Ableton10, alloc: Allocator) AbletonFile {
        return .{
            .file_name = self.Name.Value,
            .file_path = self.filepath(alloc),
            .file_size = self.SearchHint.FileSize.Value,
            .path_type = self.RelativePathType.Value,
        };
    }

    pub fn key(self: Ableton10) []const u8 {
        return self.Name.Value;
    }

    fn filepath(self: Ableton10, alloc: Allocator) []const u8 {
        std.mem.sort(RelativePathElement, self.RelativePath, {}, pathElementLessThan);
        var full_path: []const u8 = "";
        for (self.RelativePath) |rp| {
            full_path = std.fs.path.join(alloc, &[_][]const u8{ full_path, rp.Dir }) catch continue;
        }
        return std.fs.path.join(alloc, &[_][]const u8{ full_path, self.Name.Value }) catch return full_path;
    }

    fn pathType(self: Ableton10) PathType {
        return self.RelativePathType.Value;
    }

    pub fn format(self: Ableton10, w: *std.Io.Writer) !void {
        _ = try w.print("{s}\n", .{std.fs.path.basename(self.name())});
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
