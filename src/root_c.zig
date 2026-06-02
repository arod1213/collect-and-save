const Allocator = std.mem.Allocator;
const Dir = std.Io.Dir;
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;

const lib = @import("collect_and_save");
const Color = lib.Color;
pub const SaveCommand = lib.SaveCommand;
pub const FileState = lib.FileState;
const sqlite = @import("sqlite");
const xml = @import("xml");
const zli = @import("zli");
const Doc = lib.xml.types.Doc;

const termios = @import("termios.zig");

const std = @import("std");

pub const AbletonFiles = extern struct {
    files: [*]const CAbletonFile,
    len: usize,
    pub fn default() AbletonFiles {
        return .{
            .files = &[0]CAbletonFile{},
            .len = 0,
        };
    }
};

pub const CAbletonFile = extern struct {
    file_name: [*:0]const u8,
    file_path: [*:0]const u8,
    file_size: u64,
    path_type: lib.ableton.PathType,

    pub fn deinit(self: *const CAbletonFile, gpa: Allocator) void {
        // + 1 to account for null term
        const name_len = std.mem.len(self.file_name) + 1;
        const path_len = std.mem.len(self.file_path) + 1;
        gpa.free(self.file_name[0..name_len]);
        gpa.free(self.file_path[0..path_len]);
    }
};

pub export fn cns_free_files(files: AbletonFiles) void {
    if (files.len == 0) return;
    const gpa = std.heap.page_allocator;
    for (0..files.len) |idx| {
        files.files[idx].deinit(gpa);
    }
    gpa.free(files.files[0..files.len]);
}

/// list of files that are Missing / External
/// returns owned memory
pub export fn cns_collect_files(ableton_set_path: [*c]const u8) AbletonFiles {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    if (ableton_set_path == null) {
        return AbletonFiles.default();
    }
    const path = gpa.dupeZ(u8, std.mem.span(ableton_set_path)) catch return AbletonFiles.default();
    defer gpa.free(path);

    return cns_collectable_files_inner(std.heap.page_allocator, path) catch AbletonFiles.default();
}

fn cns_collectable_files_inner(gpa: Allocator, path: []const u8) !AbletonFiles {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const arena_gpa = arena.allocator();

    var t = std.Io.Threaded.init(arena_gpa, .{});
    defer t.deinit();
    const io = t.io();

    var session_dir = try lib.collect.getSessionDir(io, path);
    defer session_dir.close(io);

    const tmp_name = "./tmp_ableton_collect_and_save.xml";
    _ = try lib.commands.writeGzipToTmp(io, arena_gpa, tmp_name, path);
    defer Dir.cwd().deleteFile(io, tmp_name) catch {};

    xml.parserSetup();
    defer xml.parserDeinit();

    var doc = try Doc.init(tmp_name);
    if (doc.root == null) return error.NoRoot;
    defer doc.deinit();

    const ableton_version = try lib.commands.getAbletonVersion(arena_gpa, &doc);

    const files = blk: switch (ableton_version) {
        .nine, .ten => {
            const K = lib.ableton.Ableton10;
            break :blk try lib.fetchFiles(K, arena_gpa, doc.root.?);
        },
        .eleven, .twelve => {
            const K = lib.ableton.Ableton11;
            break :blk try lib.fetchFiles(K, arena_gpa, doc.root.?);
        },
    };
    var list_files = try std.ArrayList(CAbletonFile).initCapacity(gpa, files.len);
    defer list_files.deinit(gpa);
    for (files) |file| {
        if (!lib.ableton.shouldCollect(
            io,
            arena_gpa,
            session_dir,
            file.path_type,
            file.file_path,
        )) continue;

        try list_files.append(gpa, .{
            .file_name = try gpa.dupeZ(u8, file.file_name),
            .file_path = try gpa.dupeZ(u8, file.file_path),
            .file_size = file.file_size,
            .path_type = file.path_type,
        });
    }
    const slice = try list_files.toOwnedSlice(gpa);
    return .{
        .files = @ptrCast(slice),
        .len = slice.len,
    };
}

pub export fn cns_save_file(file: CAbletonFile, dry_run: bool) CollectRes {
    const gpa = std.heap.c_allocator;
    var t = std.Io.Threaded.init(gpa, .{});
    defer t.deinit();
    const io = t.io();

    var out_buffer: [4096]u8 = undefined;
    var discarding = std.Io.Writer.Discarding.init(&out_buffer);

    var in_buffer: [4096]u8 = undefined;
    var reader = std.Io.Reader.fixed(&in_buffer);

    var session_dir = lib.collect.getSessionDir(io, std.mem.span(file.file_path)) catch return .BAD_FILE;
    defer session_dir.close(io);

    const config = lib.CollectFileConfig{
        .reader = &reader,
        .writer = &discarding.writer,
        .session_dir = session_dir,
        .db = null,
        .cmd = if (dry_run) .check else .save,
    };
    const ableton_file = lib.AbletonFile{
        .file_path = std.mem.span(file.file_path),
        .file_name = std.mem.span(file.file_name),
        .file_size = file.file_size,
        .path_type = file.path_type,
    };

    lib.collectFile(io, gpa, ableton_file, &config) catch return .FAIL_COLLECT;
    return .OK;
}

pub export fn cns_is_backup(filepath: [*c]const u8) bool {
    if (filepath == null) {
        return true;
    }
    const gpa = std.heap.c_allocator;
    const path = gpa.dupeZ(u8, std.mem.span(filepath)) catch return false;
    defer gpa.free(path);
    return lib.checks.isBackup(path);
}

pub const CollectRes = enum(u8) {
    OK,
    BAD_FILE,
    FAIL_COLLECT,
    IS_BACKUP,
};
pub const CollectSetRes = extern struct {
    err: CollectRes,
    count: usize = 0,
};

pub export fn cns_collect_set(filepath: [*c]const u8, cmd: lib.SaveCommand) CollectSetRes {
    if (filepath == null) {
        return .{ .err = .OK, .count = 0 };
    }

    const gpa = std.heap.c_allocator;
    var t = std.Io.Threaded.init(gpa, .{});
    defer t.deinit();
    const io = t.io();

    const path = gpa.dupeZ(u8, std.mem.span(filepath)) catch return .{
        .err = .BAD_FILE,
        .count = 0,
    };
    defer gpa.free(path);
    return cns_collect_set_inner(io, gpa, path, cmd) catch return .{
        .err = .FAIL_COLLECT,
        .count = 0,
    };
}

fn cns_collect_set_inner(io: std.Io, gpa: Allocator, path: []const u8, cmd: lib.SaveCommand) !CollectSetRes {
    var session_dir = try lib.collect.getSessionDir(io, path);
    defer session_dir.close(io);

    var stdout = std.Io.File.stdout();
    defer stdout.close(io);
    var out_buffer: [4096]u8 = undefined;
    var writer = stdout.writer(io, &out_buffer);

    var stdin = std.Io.File.stdin();
    defer stdin.close(io);
    var in_buffer: [4096]u8 = undefined;
    var reader = stdin.reader(io, &in_buffer);

    const config = lib.CollectFileConfig{
        .reader = &reader.interface,
        .writer = &writer.interface,
        .session_dir = session_dir,
        .db = null,
        .cmd = cmd,
    };
    const count = try lib.collectSet(io, gpa, &config, path);
    return .{ .err = .OK, .count = count };
}
