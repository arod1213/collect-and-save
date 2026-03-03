const sqlite = @import("sqlite");
const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn setup(name: []const u8) !*sqlite.Conn {
    var conn = try sqlite.Conn.init(name);
    const sql = "CREATE TABLE if not EXISTS files (file_name TEXT NOT NULL file_path TEXT NOT NULL size INTEGER NOT NULL)";
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

    const sql = "INSERT INTO files (file_name, size) VALUES (?, ?)";
    const stmt = try sqlite.Statement.init(conn, sql);
    while (try iter.next()) |entry| {
        var file = try entry.dir.openFile(entry.path);
        defer file.close();
        const stat = try file.stat();

        defer stmt.reset();
        try stmt.bindParam(0, entry.basename);
        try stmt.bindParam(1, stat.size);
        try stmt.exec();
    }
    try conn.closeTransaction(true);
}
