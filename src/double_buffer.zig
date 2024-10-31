const std = @import("std");
const AtomicIndex = std.atomic.Value(WriteableIndex);

const WriteableIndex = enum(u8) {
    Marco,
    Polo,
};

pub fn DoubleBuffer(comptime T: type, comptime cap: usize) type {
    const marcoMtx = std.Thread.Mutex{};
    const poloMtx = std.Thread.Mutex{};

    return struct {
        marco: [cap]T = [_]T{undefined} ** cap,
        polo: [cap]T = [_]T{undefined} ** cap,
        marco_mtx: std.Thread.Mutex = marcoMtx,
        polo_mtx: std.Thread.Mutex = poloMtx,
        writeable_idx: AtomicIndex = AtomicIndex.init(.Marco),

        const Self = @This();

        pub fn getBuffer(self: *Self) struct { buf: []const T, lock: *std.Thread.Mutex } {
            return switch (self.writeable_idx.load(.seq_cst)) {
                .Marco => .{ .buf = &self.polo, .lock = &self.polo_mtx },
                .Polo => .{ .buf = &self.marco, .lock = &self.marco_mtx },
            };
        }

        pub fn writeBuffer(self: *Self, value: []const T) void {
            var bufToWrite: []T = undefined;
            var mtx: *std.Thread.Mutex = undefined;

            switch (self.writeable_idx.load(.seq_cst)) {
                .Marco => {
                    bufToWrite = &self.marco;
                    mtx = &self.marco_mtx;
                    self.writeable_idx.store(.Polo, .seq_cst);
                },
                .Polo => {
                    bufToWrite = &self.polo;
                    mtx = &self.polo_mtx;
                    self.writeable_idx.store(.Marco, .seq_cst);
                },
            }

            {
                mtx.lock();
                defer mtx.unlock();
                std.mem.copyForwards(T, bufToWrite, value);
            }
        }
    };
}

test "same thread usage" {
    var db = DoubleBuffer(u8, 1){};
    db.writeBuffer(&[_]u8{1});
    var buf = db.getBuffer();
    buf.lock.lock();
    defer buf.lock.unlock();
    try std.testing.expect(buf.buf[0] == 1);
}
