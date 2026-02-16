//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const collect = @import("./collect.zig");
pub const gzip = @import("gzip.zig");

pub const xml = @import("xml");

const Node = xml.Node;
const Doc = xml.Doc;

const ableton = @import("ableton_doc.zig");

const FileInfo = ableton.FileInfo;
const PathType = ableton.PathType;

fn transform(x: Node) !FileInfo {
    return try xml.parseNodeToT(FileInfo, &x, "Value");
}

// TODO: ensure that new dir is relative to the ableton session
// TODO: finish this
fn getSessionDir(filepath: []const u8) !std.fs.Dir {
    if (std.fs.path.dirname(filepath)) {
        // get dirname as Dir;
        // return
    } else {
        return std.fs.cwd();
    }
}

// TODO: ensure that new dir is relative to the ableton session
fn resolveFile(alloc: Allocator, filepath: []const u8) !void {
    const new_dir = "Samples/Collected";

    const session_dir = try getSessionDir(filepath);
    try session_dir.makePath(new_dir);

    const filename = std.fs.path.basename(filepath);
    // TODO: the file name used in path join must contain the everything after the as a prefix
    const new_path = try std.fs.path.join(alloc, &[_][]const u8{ new_dir, filename });

    if (std.fs.path.isAbsolute(filepath)) {
        std.log.err("not handling absolute paths yet", .{});
        return;
    } else {
        try session_dir.copyFile(filepath, session_dir, new_path, .{});
    }
}

pub fn collectAndSave(alloc: Allocator, filepath: []const u8) !void {
    var file = try std.fs.cwd().openFile(filepath, .{});
    defer file.close();

    const xml_buffer = try gzip.unzipXml(alloc, &file);
    const doc = try xml.Doc.initFromBuffer(xml_buffer);
    if (doc.root == null) return error.NoRoot;

    const files = try xml.nodesByName(FileInfo, alloc, doc.root.?, "FileRef", transform);

    var map = std.StringArrayHashMap(FileInfo).init(alloc);
    defer map.deinit();

    // DEDUP
    for (files) |f| {
        if (!f.shouldCollect()) continue;

        const res = try map.getOrPut(f.RelativePath);
        if (res.found_existing) {
            continue;
        }
        res.value_ptr.* = f;
    }

    var count: usize = 0;
    for (map.values()) |f| {
        // TODO: copy files in here
        print("{f}\n", .{f});
        count += 1;
    }

    std.log.info("found {d} files ", .{count});
}
