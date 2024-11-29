// This file copies what has been implemented in tigerbeetle for IO
// The main points of learning here are the following:
// - Execute IO related logic for a set number of nanoseconds
// - Handle retry for IO (this is where use of kevent is needed)
const std = @import("std");
const kevent = std.posix.kevent;

pub const IOError = error{EventQueueFull};

// We shall have an IO struct that has a simplified version of what tigerbeetle's IO does:
// - An api that schedules stuff to be written to a file of choice (this implies that we would need to hold onto the buffer)
// - An api that spends a specified amount of nanoseconds on performing IO (this would be tb's run_for_ns)
pub fn IO(comptime storageSize: usize) type {
    return struct {
        const Self = @This();

        fd: std.posix.fd_t,

        kq: std.posix.fd_t,

        // For now we will just use a simple array
        incoming: [storageSize][]const u8 = std.mem.zeroes([storageSize][]const u8),

        // This points to the next index to write into the incoming buffer
        cur_idx: usize = 0,

        // This function is to be called from the same thread as the main thread
        pub fn write(self: *Self, data: []const u8) !void {
            if (self.cur_idx >= storageSize) return IOError.EventQueueFull;
            self.incoming[self.cur_idx] = data;
            self.cur_idx += 1;
        }

        // This is also to be called from main thread
        // This is doable because for write and runForNs are to be called from the same thread
        // It does two things here:
        // - Takes everything from the incoming buffer and resets the cur_idx to zero
        // - Writes buffer to destination using std.posix.pwrite
        // - For pwrite calls that cannot be completed right away, we enqueue it again onto incoming
        pub fn run_for_ns(self: *Self, ns: u64) !void {
            var should_keep_running = true;
            const time_now = std.time.nanoTimestamp();
            while (should_keep_running) {
                var event_queue: [256]std.posix.Kevent = undefined;
                const writes = for (self.incoming[0..self.cur_idx], 0..) |_, i| {
                    event_queue[i] = std.posix.Kevent{
                        .ident = @intCast(self.fd),
                        .filter = std.posix.system.EVFILT_WRITE,
                        .flags = std.posix.system.EV_ADD | std.posix.system.EV_ENABLE | std.posix.system.EV_ONESHOT,
                        .fflags = 0,
                        .data = 0,
                        .udata = i, // We don't want to lose track of the slice info so we should just use the index here
                    };
                    if (i + 1 == self.cur_idx) {
                        break self.cur_idx;
                    }
                } else blk: {
                    break :blk self.cur_idx;
                };
                self.cur_idx = 0;
                var ts = std.mem.zeroes(std.posix.timespec);
                // This should be a subset of ns. Otherwise we will spend the entire allotted time waiting.
                ts.tv_nsec = @intCast(ns / 10);

                const event_num = try kevent(self.kq, event_queue[0..writes], event_queue[0..256], &ts);
                std.debug.assert(event_num < self.incoming.len);
                for (event_queue[0..event_num]) |event| {
                    const idx = event.udata;
                    std.debug.assert(idx < self.incoming.len);
                    // TODO: make offset account for the bytes already written
                    const res = std.posix.pwrite(self.fd, self.incoming[idx], 0) catch |err| switch (err) {
                        std.posix.PWriteError.WouldBlock => {
                            self.incoming[self.cur_idx] = self.incoming[idx];
                            self.cur_idx += 1;
                            continue;
                        },
                        std.posix.PWriteError.Unseekable => {
                            std.debug.print("Unseekable, dicarding {s}\n", .{self.incoming[idx]});
                            continue;
                        },
                        else => {
                            std.debug.print("Encountered error while writing {s}: {s}\n", .{ self.incoming[idx], @errorName(err) });
                            continue;
                        },
                    };
                    if (res < self.incoming[idx].len) {
                        self.incoming[self.cur_idx] = self.incoming[idx][res..];
                        self.cur_idx += 1;
                    }
                }
                const time = std.time.nanoTimestamp();
                should_keep_running = time - time_now < ns;
            }
        }
    };
}

test "basic write test" {
    var io = IO(10){ .fd = std.posix.STDOUT_FILENO, .kq = std.posix.kqueue() catch unreachable };
    io.write("hello") catch unreachable;
    io.run_for_ns(20) catch unreachable;

    const fd2 = try std.posix.openZ("test.txt", .{
        .ACCMODE = .RDWR,
        .NONBLOCK = true,
        .CREAT = true,
    }, 0);
    defer std.posix.close(fd2);
    var io2 = IO(100){ .fd = fd2, .kq = std.posix.kqueue() catch unreachable };
    try io2.write("hello");
    io2.run_for_ns(20) catch unreachable;
}
