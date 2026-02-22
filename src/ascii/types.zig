pub const Color = enum {
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    reset,

    pub fn code(self: Color) []const u8 {
        return switch (self) {
            .red => "\x1b[31m",
            .green => "\x1b[32m",
            .yellow => "\x1b[33m",
            .blue => "\x1b[34m",
            .magenta => "\x1b[35m",
            .cyan => "\x1b[36m",
            .white => "\x1b[37m",
            .reset => "\x1b[0m",
        };
    }
};

pub const Style = enum {
    bold,
    dimmed,
    reset,
    pub fn code(self: Style) []const u8 {
        return switch (self) {
            .bold => "\x1b[1m",
            .dimmed => "\x1b[2m",
            .reset => "\x1b[0m",
        };
    }
};
