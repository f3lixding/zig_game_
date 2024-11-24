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

        pub fn writeBufferWhileLocked(self: *Self, processor: fn ([]T) void) void {
            const writeBundle: struct { buf: *[cap]T, lock: *std.Thread.Mutex } = blk: {
                switch (self.writeable_idx.load(.seq_cst)) {
                    .Marco => {
                        self.writeable_idx.store(.Polo, .seq_cst);
                        break :blk .{ .buf = &self.marco, .lock = &self.marco_mtx };
                    },
                    .Polo => {
                        self.writeable_idx.store(.Marco, .seq_cst);
                        break :blk .{ .buf = &self.polo, .lock = &self.polo_mtx };
                    },
                }
            };
            const buf = writeBundle.buf;
            var bufMtx = writeBundle.lock;
            bufMtx.lock();
            defer bufMtx.unlock();
            processor(buf);
        }
    };
}

test "pointer cast" {
    const anonFn = struct {
        fn acceptAnyOpaque(ptr: *anyopaque) void {
            const presumeU8: *u8 = @ptrCast(@alignCast(ptr));
            std.debug.print("{d}\n", .{presumeU8.*});
        }
    }.acceptAnyOpaque;
    var val: u8 = 1;
    anonFn(&val);
}

test "format print" {
    const allocator = std.testing.allocator;
    const res = try std.fmt.allocPrint(allocator, "this is a number {d}\n", .{1});
    defer allocator.free(res);
    std.debug.print("{s}\n", .{res});
}

test "same thread usage" {
    const allocator = std.testing.allocator;
    allocator.alloc(1);
    var db = DoubleBuffer(u8, 1){};
    db.writeBuffer(&[_]u8{1});
    var buf = db.getBuffer();
    {
        buf.lock.lock();
        defer buf.lock.unlock();
        try std.testing.expect(buf.buf[0] == 1);
    }

    db.writeBufferWhileLocked(processorFn);
    {
        const buf2 = db.getBuffer();
        std.debug.print("buf2: {any}\n", .{buf2.buf});
        try std.testing.expect(buf2.buf[0] == 1);
    }
}

fn processorFn(buf: []u8) void {
    buf[0] += 1;
    std.time.sleep(std.time.ns_per_s * 1);
}

test "multi thread usage" {
    var db = DoubleBuffer(u8, 1){};
    const threadUI = try std.Thread.spawn(.{}, uiThread, .{ 1, &db });
    const threadBackground = try std.Thread.spawn(.{}, backgroundThread, .{ 1, &db });
    threadUI.join();
    threadBackground.join();
}

// test functions
fn uiThread(comptime cap: usize, db: *DoubleBuffer(u8, cap)) void {
    var numRead: u8 = 0;
    while (numRead < 10) {
        var buf = db.getBuffer();
        buf.lock.lock();
        defer buf.lock.unlock();
        std.debug.print("Received value: {d}\n", .{buf.buf[0]});
        numRead += 1;
    }
}

fn backgroundThread(comptime cap: usize, db: *DoubleBuffer(u8, cap)) void {
    var numSent: u8 = 0;
    while (numSent < 10) {
        db.writeBufferWhileLocked(processorFn);
        numSent += 1;
    }
}
