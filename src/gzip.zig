const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn unzipXml(alloc: Allocator, file: *std.fs.File) ![]const u8 {
    var text = try std.ArrayList(u8).initCapacity(alloc, 10000);
    defer text.deinit(alloc);

    var file_buffer: [4096]u8 = undefined;
    var reader = file.reader(&file_buffer);

    var zip_buf: [std.compress.flate.max_window_len]u8 = undefined;
    var decompressor = std.compress.flate.Decompress.init(&reader.interface, .gzip, &zip_buf);

    var read_buffer: [4096]u8 = undefined;
    while (true) {
        const bytes = decompressor.reader.readSliceShort(&read_buffer) catch |err| {
            if (err == error.EndOfStream) break else return err;
        };
        if (bytes == 0) break;

        try text.appendSlice(alloc, read_buffer[0..bytes]);
    }

    return try text.toOwnedSlice(alloc);
}

pub fn writeXml(file: *std.fs.File, w: *std.Io.Writer) !void {
    var file_buffer: [4096]u8 = undefined;
    var reader = file.reader(&file_buffer);

    var zip_buf: [std.compress.flate.max_window_len]u8 = undefined;
    var decompressor = std.compress.flate.Decompress.init(&reader.interface, .gzip, &zip_buf);

    var read_buffer: [4096]u8 = undefined;
    while (true) {
        @memset(&read_buffer, 0);
        const bytes = decompressor.reader.readSliceShort(&read_buffer) catch |err| {
            if (err == error.EndOfStream) break else return err;
        };
        if (bytes == 0) break;

        _ = try w.write(read_buffer[0..bytes]);
    }
    try w.flush();
}

pub fn writeChunk(alloc: Allocator, file: *std.fs.File, w: *std.Io.Writer) !void {
    var text = try std.ArrayList(u8).initCapacity(alloc, 10000);
    defer text.deinit(alloc);

    var file_buffer: [4096]u8 = undefined;
    var reader = file.reader(&file_buffer);

    var zip_buf: [std.compress.flate.max_window_len]u8 = undefined;
    var decompressor = std.compress.flate.Decompress.init(&reader.interface, .gzip, &zip_buf);

    var read_buffer: [4096]u8 = undefined;
    while (true) {
        const bytes = decompressor.reader.readSliceShort(&read_buffer) catch |err| {
            if (err == error.EndOfStream) break else return err;
        };
        if (bytes == 0) break;

        try text.appendSlice(alloc, read_buffer[0..bytes]);
    }

    const all = try text.toOwnedSlice(alloc);
    _ = try w.write(all);
    try w.flush();
}
