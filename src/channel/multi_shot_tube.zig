const std = @import("std");
const Condition = std.Thread.Condition;
const Mutex = std.Thread.Mutex;
const Atomic = std.atomic;

// This would requires a ring buffer
// The head and tail variables are used to keep track of the buffer
// Head signifies the next index to be read all the way to the tail
// Tail signifies the last index of unread buffer
// As of now this struct is the equivalent of mpsc (multiple producer, single consumer)
//
// The recv api's behavior is blocking (it will wait until there is something to be read)
// On write, the following would happen:
// - Derive the next tail index
// - Check if the buffer is full. If it is full we return an error.
// - Check if the tail index can be updated with `cmpxchgWeak` and update it if it can.
// - If not, this means someone else has gotten to writing first, and we should go back to deriving the next tail and try again
// - Write to the tail index of the buffer
//
// On read, the following would happen:
// - Read from the head index to the tail index
// - Update head index to tail index
pub fn MultiShotTube(comptime T: type, comptime cap: usize) type {
    std.debug.assert(cap > 0);

    // This internal struct gets bit casted into head (which is a u128)
    // The tag is to differentiate the ring buffer's full and empty state
    // Because tag might overflow, we would use @addWithOverflow to increment it
    const TaggedIndex = packed struct {
        index: u64 = 0,
        tag: u64 = 0,
    };

    return struct {
        const Self = @This();

        buffer: [cap]T = undefined,
        condition: Condition = Condition{},
        mutex: Mutex = Mutex{},
        head: Atomic.Value(u128) = Atomic.Value(u128).init(0),
        tail: Atomic.Value(u128) = blk: {
            const value: TaggedIndex = .{
                .index = 0,
                .tag = 1,
            };
            break :blk @bitCast(value);
        },

        pub fn send(self: *Self, value: T) BufferError!void {
            while (true) {
                const curHeadIndex = self.head.load(.seq_cst);
                const curTailIndex = self.tail.load(.seq_cst);
                if (curHeadIndex == curTailIndex) {
                    return BufferError.BufferFull;
                }
                const curHead: TaggedIndex = @bitCast(curHeadIndex);
                const curTail: TaggedIndex = @bitCast(curTailIndex);
                const newTail: TaggedIndex = .{
                    .index = (curTail.index + 1) % cap,
                    .tag = curHead.tag,
                };
                self.mutex.lock();
                defer self.mutex.unlock();
                if (self.tail.cmpxchgStrong(@bitCast(curTail), @bitCast(newTail), .seq_cst, .monotonic)) |v| {
                    _ = v;
                    std.debug.print("compare failed\n", .{});
                } else {
                    std.debug.print("compare successful, sending value {any} to index {d}\n", .{ value, curTail.index });
                    self.buffer[curTail.index] = value;
                    self.condition.signal();
                    return;
                }
            }
        }

        pub fn recv(self: *Self, comptime size: usize, dest: *[size]T) usize {
            std.debug.assert(size <= cap);
            self.mutex.lock();
            defer self.mutex.unlock();
            self.condition.wait(&self.mutex);
            const head: TaggedIndex = @bitCast(self.head.load(.seq_cst));
            const curTail: TaggedIndex = @as(TaggedIndex, @bitCast(self.tail.load(.seq_cst)));
            const tail = curTail.index;
            if (head.index < tail) {
                std.mem.copyForwards(T, dest, self.buffer[head.index..tail]);
            } else {
                std.mem.copyForwards(T, dest, self.buffer[head.index..]);
                std.mem.copyForwards(T, dest[(cap - head.index)..], self.buffer[0..tail]);
            }
            // Example:
            // [0, 1, 2, 3, 4, 5]
            //     ^        ^
            //     tail     head
            // 1 + 6 - 4 = 3
            const incomingSize = if (tail >= head.index)
                (tail - head.index)
            else
                (tail + cap - head.index);

            // Update head;
            // we can go ahead and do this because there is only one single thread doing the consuming
            const newTaggedIndex = TaggedIndex{ .index = (head.index + incomingSize) % cap, .tag = @addWithOverflow(curTail.tag, 1)[0] };
            self.head.store(@bitCast(newTaggedIndex), .seq_cst);
            return incomingSize;
        }
    };
}

pub const BufferError = error{
    BufferFull,
};

// Test functions
fn recver(comptime T: type, tube: anytype, ansCollected: *std.ArrayList(T)) !void {
    var dest: [10]T = undefined;
    mainloop: while (true) {
        const volumeRecvd = tube.recv(10, &dest);
        std.debug.print("volumeRecvd: {d}\n", .{volumeRecvd});
        for (dest[0..volumeRecvd]) |v| {
            std.debug.print("Recvd: {d}\n", .{v});
            try ansCollected.append(v);
            if (v == 99) {
                break :mainloop;
            }
        }
    }
}

fn producer(comptime T: type, tube: anytype, limit: usize, numToSend: T, timeToSleep: u32) !void {
    var curLimit = limit;
    while (curLimit > 0) {
        try tube.send(numToSend);
        std.time.sleep(std.time.ns_per_s * timeToSleep);
        curLimit -= 1;
    }
    // this terminates the test and should conclude all threads
    try tube.send(101);
}

test "single producer" {
    var tube = MultiShotTube(u8, 10){};
    var ansCollected = std.ArrayList(u8).init(std.testing.allocator);
    defer ansCollected.deinit();

    const numsToSend = [_]struct { u8, usize }{
        .{ 1, 10 },
    };
    var r = std.Thread.spawn(.{}, recver, .{ u8, &tube, &ansCollected }) catch unreachable;
    var p = std.Thread.spawn(.{}, producer, .{ u8, &tube, 10, numsToSend[0].@"0", 1 }) catch unreachable;
    p.join();
    r.join();

    var tally: [102]u8 = [_]u8{0} ** 102;
    for (ansCollected.items) |v| {
        tally[@as(usize, v)] += 1;
    }
    for (numsToSend) |numToSend| {
        const num: u8 = numToSend.@"0";
        const limit: usize = numToSend.@"1";
        const resFromTally = tally[@as(usize, num)];
        std.debug.assert(resFromTally == limit);
    }
    std.debug.assert(@as(usize, tally[101]) == numsToSend.len);
}

test "multiple producer" {
    var tube = MultiShotTube(u8, 10){};
    var ansCollected = std.ArrayList(u8).init(std.testing.allocator);
    defer ansCollected.deinit();

    const numsToSend = [_]struct { u8, usize }{
        .{ 1, 10 },
        .{ 2, 10 },
        .{ 3, 10 },
    };
    var producerThreads = [_]std.Thread{undefined} ** numsToSend.len;
    var r = std.Thread.spawn(.{}, recver, .{ u8, &tube, &ansCollected }) catch unreachable;
    for (numsToSend, 0..) |numToSend, i| {
        const num: u8 = numToSend.@"0";
        const limit: usize = numToSend.@"1";
        const p = std.Thread.spawn(.{}, producer, .{ u8, &tube, limit, num, 1 }) catch unreachable;
        producerThreads[i] = p;
    }
    for (producerThreads) |p| {
        p.join();
    }
    try tube.send(99);
    r.join();

    var tally: [102]u8 = [_]u8{0} ** 102;
    for (ansCollected.items) |v| {
        tally[@as(usize, v)] += 1;
    }
    for (numsToSend) |numToSend| {
        const num: u8 = numToSend.@"0";
        const limit: usize = numToSend.@"1";
        const resFromTally = tally[@as(usize, num)];
        std.debug.print("num: {d}, limit: {d}, resFromTally: {d}\n", .{ num, limit, resFromTally });
        std.debug.assert(resFromTally == limit);
    }
    std.debug.assert(@as(usize, tally[101]) == numsToSend.len);
}
