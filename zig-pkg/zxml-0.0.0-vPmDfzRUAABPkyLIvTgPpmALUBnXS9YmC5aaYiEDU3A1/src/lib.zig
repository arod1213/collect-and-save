pub const c = @cImport({
    @cInclude("libxml/parser.h");
    @cInclude("libxml/tree.h");
});
