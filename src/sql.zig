const sqlite = @import("sqlite");
const std = @import("std");
const collect = @import("./collect.zig");
const Allocator = std.mem.Allocator;

pub fn setup(name: []const u8) !sqlite.Conn {
    var conn = try sqlite.Conn.init(name);
    const sql = "CREATE TABLE if not EXISTS files (file_name TEXT NOT NULL, file_path TEXT NOT NULL, size INTEGER NOT NULL)";
    try conn.exec(sql, sqlite.emptyCallback);
    return conn;
}

pub fn scan_dir(alloc: Allocator, conn: *sqlite.Conn, dir_path: []const u8) !void {
    var dir = if (std.fs.path.isAbsolute(dir_path))
        try std.fs.openDirAbsolute(dir_path, .{ .iterate = true })
    else
        try std.fs.cwd().openDir(dir_path, .{ .iterate = true });

    var iter = try dir.walk(alloc);
    try conn.beginTransaction();
    errdefer conn.closeTransaction(false) catch {};

    const sql = "INSERT INTO files (file_name, file_path, size) VALUES (?, ?, ?)";
    const stmt = try sqlite.Statement.init(conn, sql);
    defer stmt.close() catch {};
    while (try iter.next()) |entry| {
        switch (entry.kind) {
            .file => {
                if (!collect.validExtension(entry.basename)) continue;
            },
            else => continue,
        }
        var file = entry.dir.openFile(entry.path, .{}) catch continue;
        defer file.close();
        const stat = try file.stat();

        defer stmt.reset() catch {};

        try stmt.bindParam(1, entry.basename);
        try stmt.bindParam(2, entry.path);
        try stmt.bindParam(3, stat.size);
        _ = try stmt.exec();
    }
    try conn.closeTransaction(true);
}
