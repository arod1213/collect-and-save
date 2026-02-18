const std = @import("std");
const Allocator = std.mem.Allocator;
const Dir = std.fs.Dir;
const Entry = Dir.Entry;

fn openDir(folderpath: []const u8) !Dir {
    const options = Dir.OpenOptions{ .iterate = true };
    return if (std.fs.path.isAbsolute(folderpath))
        try std.fs.openDirAbsolute(folderpath, options)
    else
        try std.fs.cwd().openDir(folderpath, options);
}

fn filterAbleton(entry: Entry) bool {
    switch (entry.kind) {
        .file => {
            const ext = std.fs.path.extension(entry.name);
            if (!std.mem.eql(u8, ext, ".als")) {
                return false;
            }
            return true;
        },
        else => return false,
    }
}

pub fn retrievePaths(alloc: Allocator, folderpath: []const u8, filter: fn (Entry) bool) ![]const u8 {
    var dir = try openDir(folderpath);
    defer dir.close();

    var list = try std.ArrayList([]const u8).initCapacity(alloc, 50);
    errdefer list.deinit(alloc);

    try retrievePaths(alloc, folderpath, filter, &list);
    return try list.toOwnedSlice(alloc);
}

fn retrieveRecurse(alloc: Allocator, folderpath: []const u8, filter: fn (Entry) bool, list: *std.ArrayList([]const u8)) !void {
    var dir = try openDir(folderpath);
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        switch (entry.kind) {
            .directory => {
                const new_path = try std.fs.path.join(alloc, &[_][]const u8{ folderpath, entry.name });
                defer alloc.free(new_path);
                retrieveRecurse(alloc, new_path, filter, list) catch continue;
                continue;
            },
            .file => {
                if (filter(entry)) {
                    const new_path = try std.fs.path.join(alloc, &[_][]const u8{ folderpath, entry.name });
                    try list.append(alloc, new_path);
                }
            },
            else => {},
        }
    }
}
