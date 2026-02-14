//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const Allocator = std.mem.Allocator;
const collect = @import("./collect.zig");

// pub fn unzip(alloc: Allocator,file_path: []const u8, _: *std.Io.Writer) !*Resolver {
//     var file = try std.fs.cwd().openFile(file_path, .{});
//     defer file.close();
//
//     var gpa = std.heap.GeneralPurposeAllocator(.{ .verbose_log = false }){};
//     var arena = std.heap.ArenaAllocator.init(gpa.allocator());
//     defer arena.deinit();
//     const alloc = arena.allocator();
//
//     var resolver = try Resolver.init(alloc, file_path, &file);
//     return resolver;
//     try resolver.audit(alloc);
// }

pub fn resolveFile(alloc: Allocator, cwd: std.fs.Dir, file_path: []const u8) !void {
    const new_dir = "Samples/Collected";
    try cwd.makePath(new_dir);

    const file_name = std.fs.path.basename(file_path);
    // TODO: the file name used in path join must contain the everything after the as a prefix
    const new_path = try std.fs.path.join(alloc, &[_][]const u8{ new_dir, file_name });

    if (std.fs.path.isAbsolute(file_path)) {
        std.log.err("not handling absolute paths yet", .{});
        return;
    } else {
        try cwd.copyFile(file_path, cwd, new_path, .{});
    }
}

fn copyFileRaw(src_path: []const u8, dest_path: []const u8) !void {
    var src = try std.fs.openFileAbsolute(src_path, .{});
    defer src.close();

    var dst = try std.fs.createFileAbsolute(dest_path, .{ .truncate = true });
    defer dst.close();

    var buf: [64 * 1024]u8 = undefined;

    while (true) {
        const n = try src.read(buf[0..]);
        if (n == 0) break;
        try dst.writeAll(buf[0..n]);
    }
}

pub const Resolver = struct {
    session_path: []const u8,
    session: *std.fs.File,
    decompressor: std.compress.flate.Decompress,
    buffer: *[4096]u8,

    const Self = @This();
    pub fn init(alloc: Allocator, path: []const u8, file: *std.fs.File) !Self {
        const read_buffer = try alloc.create([4096]u8);

        const file_buffer = try alloc.create([4096]u8);
        var reader = file.reader(&file_buffer.*);

        const zip_buf = try alloc.create([std.compress.flate.max_window_len]u8);
        var decompressor = std.compress.flate.Decompress.init(&reader.interface, .gzip, &zip_buf.*);
        _ = &decompressor;

        return .{
            .buffer = read_buffer,
            .decompressor = decompressor,
            .session_path = path,
            .session = file,
        };
    }

    pub fn getMissingFiles(self: *Self, alloc: Allocator) ![][]const u8 {
        var missing_files = try std.ArrayList([]const u8).initCapacity(alloc, 10);
        defer missing_files.deinit(alloc);

        // const base_dir = self.baseDir() orelse return error.NotDir;

        var found_files = std.StringHashMap(void).init(alloc);
        defer found_files.deinit();

        while (true) {
            const text = self.readGzip() catch |e| {
                switch (e) {
                    error.EOF => break,
                    else => |x| return x,
                }
            };
            var iter = std.mem.splitAny(u8, text, "\n");
            const prefix = "<RelativePath Value=\"";
            while (iter.next()) |line| {
                const file_path = getFile(alloc, prefix, line) catch continue;
                if (!collect.shouldBeCollected(file_path)) {
                    continue;
                }

                const owned_path = try alloc.dupe(u8, file_path);

                const res = try found_files.getOrPut(owned_path);
                if (res.found_existing) {
                    continue;
                }
                res.value_ptr.* = {};
                try missing_files.append(alloc, owned_path);
            }
        }
        return try missing_files.toOwnedSlice(alloc);
    }

    pub fn readGzip(self: *Self) ![]const u8 {
        const bytes = self.decompressor.reader.readSliceShort(&self.buffer.*) catch return error.FailedToRead;
        if (bytes == 0) {
            return error.EOF;
        }
        return self.buffer.*[0..bytes];
    }

    fn baseDir(self: Resolver) ?[]const u8 {
        return std.fs.path.dirname(self.session_path);
    }
};

const FileInfo = struct {
    path: []const u8,
    file: std.fs.File,

    pub fn init(path: []const u8) !FileInfo {
        const file = blk: {
            if (std.fs.path.isAbsolute(path)) {
                break :blk try std.fs.openFileAbsolute(path, .{});
            } else {
                const cwd = std.fs.cwd();
                break :blk try cwd.openFile(path, .{});
            }
        };
        return .{
            .file = file,
            .path = path,
        };
    }

    pub fn deinit(self: *FileInfo) void {
        self.file.close();
    }
};

pub fn getFile(_: Allocator, prefix: []const u8, line: []const u8) ![]const u8 {
    return getValue(prefix, line) orelse return error.InvalidLine;
}

pub fn getValue(prefix: []const u8, line: []const u8) ?[]const u8 {
    const start = std.mem.indexOf(u8, line, prefix);
    const end = std.mem.indexOf(u8, line, "\" />");

    if (start == null or end == null) {
        return null;
    }

    if (start.? > end.?) {
        std.log.info("start index is after end index for {s}", .{line});
        return null;
    }

    const path_start = start.? + prefix.len;
    const path = line[path_start..end.?];
    return path;
}
