const std = @import("std");
const Condition = std.Thread.Condition;
const Mutex = std.Thread.Mutex;

/// A one shot channel that utilizes the following mechanism to achieve what a channel does
/// - A queue (e.g. a ring buffer) of values
/// - A mutex for synchronizing access to the queue
/// - A condition variable for signaling when a value is available
/// For now this is a single producer, single consumer channel
pub fn SingleShotTube(comptime T: type) type {
    return struct {
        const Self = @This();

        buffer: T = undefined,
        condition: Condition = Condition{},
        mutex: Mutex = Mutex{},

        // COMMENT TO BE DELETED AFTER IMPLEMENTED:
        // Here we will perform the following:
        // - Acquire the mutex lock
        // - Write value to buffer
        // - Release the mutex lock
        pub fn send(self: *Self, value: T) !void {
            {
                self.mutex.lock();
                defer self.mutex.unlock();
                self.buffer = value;
            }
            self.condition.signal();
        }

        // COMMENT TO BE DELETED AFTER IMPLEMENTED:
        // Here we will perform the following:
        // - Acquire the mutex lock
        // - defer a mutex unlock
        // -  call wait on the condition
        // - Read the value from the buffer
        pub fn recv(self: *Self) !T {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.condition.wait(&self.mutex);
            return self.buffer;
        }
    };
}

fn consumer(m: *Mutex, c: *Condition, _: *bool, threadNumber: i32) void {
    m.lock();
    defer m.unlock();
    // while (!predicate.*) {
    //     c.wait(m);
    // }
    std.debug.print("Thread {d} obtained lock\n", .{threadNumber});
    c.wait(m);
    // m.unlock();
    std.debug.print("Signal received from thread {d}\n", .{threadNumber});
    std.debug.print("Consumer {d} sleeping for 2 seconds\n", .{threadNumber});
    std.time.sleep(std.time.ns_per_s * 2);
}

fn producer(m: *Mutex, c: *Condition, predicate: *bool) void {
    {
        m.lock();
        defer m.unlock();
        predicate.* = true;
    }
    std.debug.print("Sleeping producer for 2 seconds\n", .{});
    std.time.sleep(std.time.ns_per_s * 2);
    // c.signal();
    c.broadcast();
}

test "channel test" {
    var singleShotTube = SingleShotTube([]const u8){};
    const threadRecv = try std.Thread.spawn(.{}, receiver_fn_mod, .{ 10, &singleShotTube });
    const threadProd = try std.Thread.spawn(.{}, producer_fn, .{ []const u8, 10, &singleShotTube });
    threadRecv.join();
    threadProd.join();
}

fn producer_fn(comptime T: type, comptime cap: usize, singleShotTube: *SingleShotTube(T)) void {
    std.debug.assert(cap > 0);
    var producer_limit: usize = 10;
    while (producer_limit > 0) {
        if (T == u8) {
            try singleShotTube.send(@intCast(producer_limit));
        } else if (T == []const u8) {
            try singleShotTube.send("hello world");
        }
        producer_limit -= 1;
        std.time.sleep(std.time.ns_per_s * 2);
    }
}

fn receiver_fn(comptime T: type, comptime cap: usize, singleShotTube: *SingleShotTube(T, cap)) void {
    std.debug.assert(cap > 0);

    var receiver_limit: usize = 10;
    while (receiver_limit > 0) {
        const val = try singleShotTube.recv();
        if (@TypeOf(val) == u8) {
            std.debug.print("Received {d}\n", .{val});
        } else {
            std.debug.print("Received something that I cannot print\n", .{});
        }
        receiver_limit -= 1;
    }
}

fn receiver_fn_mod(comptime cap: usize, tube: anytype) void {
    std.debug.assert(cap > 0);
    var receiver_limit: usize = 10;
    while (receiver_limit > 0) {
        const val = tube.recv() catch unreachable;
        if (@TypeOf(val) == u8) {
            std.debug.print("Received {d}\n", .{val});
        } else {
            std.debug.print("Received something that I cannot print\n", .{});
        }
        receiver_limit -= 1;
    }
}

test "tube test" {
    const spawn = std.Thread.spawn;
    var m = Mutex{};
    var c = Condition{};
    var predicate = false;

    const producerThread = try spawn(.{}, producer, .{ &m, &c, &predicate });
    const waitThreadOne = try spawn(.{}, consumer, .{ &m, &c, &predicate, 1 });
    const waitThreadTwo = try spawn(.{}, consumer, .{ &m, &c, &predicate, 2 });
    producerThread.join();
    waitThreadOne.join();
    waitThreadTwo.join();

    std.debug.assert(predicate);

    const singleShotTube = SingleShotTube(u8, 10){};
    _ = singleShotTube;
}
