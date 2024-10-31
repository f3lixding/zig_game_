const std = @import("std");
const AtomicIndex = std.atomic.Value(WriteableIndex);

const Self = @This();

marco: undefined,
polo: undefined,
writeable_index: AtomicIndex,

const WriteableIndex = enum {
    Marco,
    Polo,
};

pub fn init(comptime T: type, comptime cap: usize) Self {
    return .{
        .marco = [cap]T,
        .polo = [cap]T,
        .writeable_index = AtomicIndex.init(.Marco),
    };
}

pub fn getBuffer(self: Self) []T {
    return switch (self.writeable_index.load(.SeqCst)) {
        .Marco => &self.marco,
        .Polo => &self.polo,
    };
}
