const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const c = @cImport({
    @cInclude("libxml/parser.h");
    @cInclude("libxml/tree.h");
});

pub fn readDoc(path: []const u8) !void {
    const doc = c.xmlReadFile(@ptrCast(path), null, 0);
    if (doc == null) return error.ParseFailed;
    defer c.xmlFreeDoc(doc);

    const root = c.xmlDocGetRootElement(doc);

    const stdout = std.fs.File.stdout();
    var buff: [4096]u8 = undefined;
    var writer = stdout.writer(&buff);

    try walkNode(root, &writer.interface);
}

pub const PathType = enum(u4) {
    NA = 0,
    ExternalPluginPreset = 1,
    Recorded = 3,
    AbletonPluginPreset = 5,
    AbletonRackPreset = 6,
    AbletonCoreAudio = 7,
};

pub const FileInfo = struct {
    RelativePathType: PathType = .NA,
    RelativePath: []const u8,
    Path: []const u8,
    // Type: usize,
    LivePackName: []const u8,
    LivePackId: []const u8,
    OriginalFileSize: u64,

    // TODO: when field name is wrong garbage gets put there

    pub fn format(self: FileInfo, w: *std.Io.Writer) !void {
        try w.print("Rel: {s}\nPath {s}\nRelType {any}\nFileSize {d}\n\n", .{ self.RelativePath, self.Path, self.RelativePathType, self.OriginalFileSize });
    }
};

// info: RelativePathType: 1
// info: RelativePath: ../../../../../Library/Caches/Ableton/Presets/AudioUnits/FabFilter/Pro-L 2/Default.aupreset
// info: Path: /Users/aidan/Library/Caches/Ableton/Presets/AudioUnits/FabFilter/Pro-L 2/Default.aupreset
// info: Type: 2
// info: LivePackName:
// info: LivePackId:
// info: OriginalFileSize: 0
// info: OriginalCrc: 0
// info: RelativePathType: 1
// info: RelativePath: ../../../../../Library/Caches/Ableton/Presets/AudioUnits/FabFilter/Pro-L 2/Default.aupreset
// info: Path: /Users/aidan/Library/Caches/Ableton/Presets/AudioUnits/FabFilter/Pro-L 2/Default.aupreset
// info: Type: 2
// info: LivePackName:
// info: LivePackId:
// info: OriginalFileSize: 0
// info: OriginalCrc: 0

fn receiveVal(comptime T: type, val: []const u8) !T {
    const info = @typeInfo(T);
    return switch (info) {
        .int => try std.fmt.parseInt(T, val, 10),
        .float => try std.fmt.parseFloat(T, val),
        .@"enum" => blk: {
            const digit = try std.fmt.parseInt(info.@"enum".tag_type, val, 10);
            break :blk try std.meta.intToEnum(T, digit);
        },
        .pointer => val, // Add other pointer types
        else => unreachable,
    };
}

fn parseNodeValues(comptime T: type, node: *c.xmlNode) !T {
    const info = @typeInfo(T);
    assert(info == .@"struct");

    var target: T = undefined;
    var child = node.children;
    while (child) |ch| : (child = ch.*.next) {
        if (child == null) break;

        const value = c.xmlGetProp(ch, "Value");
        if (value != null) {
            const value_str = std.mem.span(value);
            inline for (info.@"struct".fields) |field| {
                const ch_name = std.mem.span(ch.*.name);
                if (std.ascii.eqlIgnoreCase(field.name, ch_name)) {
                    const variable = receiveVal(field.type, value_str) catch blk: {
                        if (field.defaultValue()) |def| {
                            break :blk def;
                        }
                        return error.MissingField;
                    };
                    @field(target, field.name) = variable;
                }
            }
        }
    }
    return target;
}

fn printPaths(node: *c.xmlNode, w: *std.Io.Writer) !void {
    if (!std.mem.eql(u8, std.mem.span(node.name), "FileRef")) return;
    const info = try parseNodeValues(FileInfo, node);
    try w.print("{f}", .{info});

    // var child = node.children;
    // while (child) |ch| : (child = ch.*.next) {
    //     if (child == null) break;
    //
    //     // if (ch.*.type == c.XML_ELEMENT_NODE) {
    //     //     std.log.info("  child: {s}", .{ch.*.name});
    //     // }
    //     const value = c.xmlGetProp(ch, "Value");
    //     if (value != null) {
    //         // defer c.xmlFreeCh(value);
    //         std.log.info("{s}: {s}", .{ ch.*.name, value });
    //     }
    // }
}

fn walkNode(node: ?*c.xmlNode, w: *std.Io.Writer) !void {
    var current = node;

    while (current) |n| : (current = n.next) {
        try printPaths(n, w);
        try walkNode(n.children, w);
    }
}

// <SampleRef>
//         <FileRef>
//                 <RelativePathType Value="1" />
//                 <RelativePath Value="../../../../../Documents/Sample Libraries/M-Phazes Drums and Samples/TAKE A BREAK BY WU10 (DRUM BREAKS)/0NE SHOTS AND EXTRAS/CRACKLE2.wav" />
//                 <Path Value="/Users/aidan/Documents/Sample Libraries/M-Phazes Drums and Samples/TAKE A BREAK BY WU10 (DRUM BREAKS)/0NE SHOTS AND EXTRAS/CRACKLE2.wav" />
//                 <Type Value="2" />
//                 <LivePackName Value="" />
//                 <LivePackId Value="" />
//                 <OriginalFileSize Value="2352584" />
//                 <OriginalCrc Value="6887" />
//         </FileRef>
//         <LastModDate Value="1603822758" />
//         <SourceContext>
//                 <SourceContext Id="0">
//                         <OriginalFileRef>
//                                 <FileRef Id="10">
//                                         <RelativePathType Value="1" />
//                                         <RelativePath Value="../../../../../Documents/Sample Libraries/M-Phazes Drums and Samples/TAKE A BREAK BY WU10 (DRUM BREAKS)/0NE SHOTS AND EXTRAS/CRACKLE2.wav" />
//                                         <Path Value="/Users/aidan/Documents/Sample Libraries/M-Phazes Drums and Samples/TAKE A BREAK BY WU10 (DRUM BREAKS)/0NE SHOTS AND EXTRAS/CRACKLE2.wav" />
//                                         <Type Value="2" />
//                                         <LivePackName Value="" />
//                                         <LivePackId Value="" />
//                                         <OriginalFileSize Value="2352584" />
//                                         <OriginalCrc Value="6887" />
//                                 </FileRef>
//                         </OriginalFileRef>
//                         <BrowserContentPath Value="query:Find#FileId_315072" />
//                 </SourceContext>
//         </SourceContext>
//         <SampleUsageHint Value="0" />
//         <DefaultDuration Value="588000" />
//         <DefaultSampleRate Value="44100" />
// </SampleRef>
