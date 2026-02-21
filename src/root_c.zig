const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Dir = std.Io.Dir;

const collect = @import("./collect.zig");
pub const gzip = @import("gzip.zig");
pub const checks = @import("./checks.zig");
const xml = @import("xml");
const Node = xml.Node;

const ableton = @import("ableton.zig");
const PathType = ableton.PathType;

pub const FileRef = ableton.FileRef;

fn openDoc(alloc: Allocator, io: std.Io, filepath: []const u8) !xml.Doc {
    const cwd = Dir.cwd();
    var file = cwd.openFile(io, filepath, .{}) catch |e| {
        std.log.err("could not find file {s}", .{filepath});
        return e;
    };
    defer file.close(io);

    const tmp_name = "./tmp_ableton_collect_and_save.xml";
    var tmp_file = cwd.createFile(io, tmp_name, .{ .truncate = true }) catch |e| {
        std.log.err("failed to create tmp file {any}", .{e});
        return e;
    };
    defer {
        tmp_file.close(io);
        cwd.deleteFile(io, tmp_name) catch {};
    }

    var write_buffer: [4096]u8 = undefined;
    var writer = tmp_file.writer(io, &write_buffer);
    switch (builtin.target.os.tag) {
        .macos => try gzip.writeChunk(io, alloc, &file, &writer.interface),
        else => try gzip.writeXml(io, &file, &writer.interface),
    }

    return try xml.Doc.init(tmp_name);
}

// return [] of FileRef
fn processFileRefs(comptime T: type, io: std.Io, alloc: Allocator, head: Node, session_dir: Dir) ![]FileRef {
    var map = try xml.getUniqueNodes(T, alloc, head, "FileRef", T.key);
    defer map.deinit();

    var list = try std.ArrayList(FileRef).initCapacity(alloc, 10);
    defer list.deinit(alloc);

    // var count: usize = 0;
    for (map.values()) |f| {
        const sample_path = f.filepath(alloc);
        if (!ableton.shouldCollect(io, alloc, session_dir, f.path_type(), sample_path)) continue;
        const file_ref = f.intoFileRef(alloc);
        try list.append(alloc, file_ref);
        // count += 1;
    }
    return try list.toOwnedSlice(alloc);
}

fn resolveFileHelper(io: std.Io, alloc: Allocator, session_dir: Dir, filepath: []const u8) !void {
    const new_dir = try collect.collectFolder(filepath);

    try session_dir.createDirPath(io, new_dir);

    const filename = Dir.path.basename(filepath);
    const new_path = try Dir.path.join(alloc, &[_][]const u8{ new_dir, filename });
    defer alloc.free(new_path);

    if (Dir.path.isAbsolute(filepath)) {
        const source_dirname = Dir.path.dirname(filepath) orelse "/";
        var source_dir = try Dir.openDirAbsolute(io, source_dirname, .{});
        defer source_dir.close(io);

        try source_dir.copyFile(filename, session_dir, new_path, io, .{});
        return;
    } else {
        try Dir.cwd().copyFile(filepath, session_dir, new_path, io, .{});
    }
}

export fn resolveFile(session_path: [*c]const u8, filepath: [*c]const u8) bool {
    if (filepath == null or session_path == null) {
        return false;
    }

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var threaded = std.Io.Threaded.init(alloc, .{});
    const io = threaded.io();

    var session_dir = collect.getSessionDir(io, std.mem.span(session_path)) catch |e| {
        std.log.err("failed to open session dir: {any}", .{e});
        return false;
    };
    defer session_dir.close(io);

    _ = resolveFileHelper(io, alloc, session_dir, std.mem.span(filepath)) catch return false;
    return true;
}

pub const Files = extern struct {
    files: [*c]FileRef,
    len: usize,
    pub fn fallback() Files {
        return .{
            .files = null,
            .len = 0,
        };
    }
};

export fn getExternalFiles(session_path: [*c]const u8, version: ableton.AbletonVersion) Files {
    if (session_path == null) {
        return Files.fallback();
    }

    // avoid arena as data must cross the boundary
    const alloc = std.heap.page_allocator;

    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var doc = openDoc(alloc, io, std.mem.span(session_path)) catch return Files.fallback();
    defer doc.deinit();
    if (doc.root == null) {
        return Files.fallback();
    }

    const filepath = std.mem.span(session_path);
    var session_dir = collect.getSessionDir(io, filepath) catch |e| {
        std.log.err("failed to open session dir: {any}", .{e});
        return Files.fallback();
    };
    defer session_dir.close(io);

    switch (version) {
        .nine, .ten => {
            const K = ableton.Ableton10;
            const ref: []FileRef = processFileRefs(K, io, alloc, doc.root.?, session_dir) catch return Files.fallback();
            return .{ .files = ref.ptr, .len = ref.len };
        },
        .eleven, .twelve => {
            const K = ableton.Ableton11;
            const ref: []FileRef = processFileRefs(K, io, alloc, doc.root.?, session_dir) catch return Files.fallback();
            return .{ .files = ref.ptr, .len = ref.len };
        },
    }
}

export fn freeFiles(files: Files) void {
    if (files.files != null) {
        const ptr: []FileRef = files.files[0..files.len];
        std.heap.page_allocator.free(ptr);
    }
}

// return ableton.AbletonVersion or 0 on error
const VersionTag = @typeInfo(ableton.AbletonVersion).@"enum".tag_type;
export fn sessionInfo(session_path: [*c]const u8) VersionTag {
    if (session_path == null) {
        return 0;
    }

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var threaded = std.Io.Threaded.init(alloc, .{});
    const io = threaded.io();

    var doc = openDoc(alloc, io, std.mem.span(session_path)) catch return 0;
    defer doc.deinit();

    const ableton_version = blk: {
        const ableton_info = xml.parse.nodeToT(ableton.Header, alloc, doc.root.?) catch {
            std.log.err("Unsupported Ableton Version", .{});
            return 0;
        };
        break :blk ableton_info.version() orelse {
            std.log.err("Unsupported Ableton Version {s}", .{ableton_info.MinorVersion});
            return 0;
        };
    };
    return @intFromEnum(ableton_version);
}

export fn isCollectable(session_path: [*c]const u8, f: FileRef) bool {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var threaded = std.Io.Threaded.init(alloc, .{});
    const io = threaded.io();

    if (f.filepath == null or session_path == null) {
        return false;
    }
    const filepath = std.mem.span(f.filepath);

    const session_dir = collect.getSessionDir(io, std.mem.span(session_path)) catch {
        std.log.err("failed to find session directory", .{});
        return false;
    };

    if (!ableton.shouldCollect(io, alloc, session_dir, f.path_type, filepath)) {
        std.log.info("not a collectable ableton file", .{});
        return false;
    }
    return checks.fileExists(io, filepath);
}
