const sqlite = @import("sqlite");
const std = @import("std");
const Allocator = std.mem.Allocator;

const lib = @import("../lib/main.zig");
const collect = lib.collect;

pub fn setup(name: []const u8) !sqlite.Conn {
    var conn = try sqlite.Conn.init(name);
    const sql = "CREATE TABLE if not EXISTS files (filename TEXT NOT NULL, full_path TEXT PRIMARY KEY NOT NULL, size INTEGER NOT NULL)";
    try conn.exec(sql, sqlite.emptyCallback);
    return conn;
}
// const sql = "INSERT INTO files (filename, full_path, size) VALUES (?, ?, ?)";

pub fn reset(conn: *sqlite.Conn) !void {
    const sql = "DELETE FROM files";
    try conn.exec(sql, sqlite.emptyCallback);
}

pub const File = struct {
    filename: []const u8,
    full_path: []const u8,
    size: u64,
};

pub fn findMatch(alloc: Allocator, conn: *sqlite.Conn, basename: []const u8, size: u64) !?File {
    const sql = "SELECT filename, full_path, size FROM files WHERE filename = @name AND size = @size LIMIT 1";
    const stmt = try sqlite.Statement.init(conn, sql);
    defer stmt.close() catch {};
    try stmt.bindParam(1, basename);
    try stmt.bindParam(2, size);
    _ = try stmt.exec();
    const tmp = stmt.readStruct(File) catch return null;
    return File{
        .filename = try alloc.dupe(u8, tmp.filename),
        .full_path = try alloc.dupe(u8, tmp.full_path),
        .size = tmp.size,
    };
}

pub fn scanDir(alloc: Allocator, conn: *sqlite.Conn, dir_path: []const u8) !void {
    var dir = if (std.fs.path.isAbsolute(dir_path))
        try std.fs.openDirAbsolute(dir_path, .{ .iterate = true })
    else
        try std.fs.cwd().openDir(dir_path, .{ .iterate = true });

    var iter = try dir.walk(alloc);
    defer iter.deinit();
    try conn.beginTransaction();
    errdefer conn.closeTransaction(false) catch {};

    var inserted: usize = 0;
    const sql = "INSERT INTO files (filename, full_path, size) VALUES (?, ?, ?) ON CONFLICT DO NOTHING";
    const stmt = try sqlite.Statement.init(conn, sql);
    defer stmt.close() catch {};
    while (try iter.next()) |entry| {
        switch (entry.kind) {
            .file => {
                if (!collect.validExtension(entry.basename)) continue;
            },
            else => continue,
        }
        var file = dir.openFile(entry.path, .{}) catch |e| {
            std.log.err("failed to open file {s}: {any}", .{ entry.path, e });
            continue;
        };
        defer file.close();
        const stat = try file.stat();

        const joined_path = try std.fs.path.resolve(alloc, &[_][]const u8{ dir_path, entry.path });
        const fullpath = try std.fs.realpathAlloc(alloc, joined_path);
        defer alloc.free(fullpath);

        defer stmt.reset() catch {};

        try stmt.bindParam(1, entry.basename);
        try stmt.bindParam(2, fullpath);
        try stmt.bindParam(3, stat.size);
        _ = try stmt.exec();
        if (conn.numChanges() > 0) {
            inserted += 1;
        }
    }
    try conn.closeTransaction(true);
    std.debug.print("success: inserted {d} new files", .{inserted});
}
