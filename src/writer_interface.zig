// Just trying out the stuff in https://www.openmymind.net/Zig-Interfaces/
const std = @import("std");

// This is straight forward.
// It asks the implementation to fill in the writerAllFn and ptr
// The common function in the interface then takes the function and passes it the ptr
// However, the downside of doing so is that the implementer can't directly call the underlying function (i.e. the one that was passed into the interface)
// This is because the wrapper function in the interface expects an *anyopaque to be the argument of the function that is passed in.
// (otherwise you would have a version of the interface for each possible type, which defeates the purpose of an interface)
// In order to use the impl of this interface, we would need to have a routine that knows the following:
// - The concrete type of the *anyopaque that had implemeted the inteface
// - How to convert the *anyopaque to the concrete type (this is just done with ptr and align cast)
pub const CrudeWriter = struct {
    ptr: *anyopaque,
    writeAllFn: *const fn (ptr: *anyopaque, buf: []const u8) anyerror!void,

    pub fn writeAll(self: *CrudeWriter, data: []const u8) !void {
        return self.writeAllFn(self.ptr, data);
    }
};

pub const File = struct {
    fd: std.posix.fd_t,

    // For example, File can't just call writeAll directly (e.g. file.writeAll("hello"))
    // It has to go through the interface as such:
    // file.crudeWriter().writeAll("hello")
    pub fn writeAll(self: *anyopaque, data: []const u8) !void {
        // TODO: fill this out
        const file: *File = @ptrCast(@alignCast(self));
        _ = try std.posix.write(file.fd, data);
    }

    pub fn crudeWriter(self: *File) CrudeWriter {
        return .{
            .ptr = self,
            .writeAllFn = &writeAll,
        };
    }
};

// This init function serves the following purposes:
// - Use reflection during compile time to inspect the pointer passed in to infer the type
// - Using the type information, we construct a function during compitle time to create function that takes the *anyopaque and turns it into the concrete type
pub const RefinedWriter = struct {
    ptr: *anyopaque,
    writeAllFn: *const fn (ptr: *anyopaque, data: []const u8) anyerror!void,

    // Note that this argument is anytype
    // This is because the logic here (besides return) is all done at compile time
    // We need to inspect the type passed in and create a function that knows what type to cast the *anyopaque to
    pub fn init(ptr: anytype) RefinedWriter {
        const T = @TypeOf(ptr);
        const ptr_info = @typeInfo(T);

        const gen = struct {
            fn writeAll(pointer: *anyopaque, buf: []const u8) anyerror!void {
                const self: T = @ptrCast(@alignCast(pointer));
                return ptr_info.Pointer.child.writeAll(self, buf);
            }
        }.writeAll;

        return .{
            .ptr = ptr,
            .writeAllFn = gen,
        };
    }

    pub fn writeAll(self: *RefinedWriter, data: []const u8) !void {
        return self.writeAllFn(self.ptr, data);
    }
};

pub const RefinedFile = struct {
    fd: std.posix.fd_t,

    pub fn writeAll(self: *RefinedFile, data: []const u8) !void {
        _ = try std.posix.write(self.fd, data);
    }

    pub fn refinedWriter(self: *RefinedFile) RefinedWriter {
        return RefinedWriter.init(self);
    }
};

pub fn GenericWriter(comptime T: type) type {
    return struct {
        ptr: *T,
        writeAllFn: *const fn (ptr: *T, data: []const u8) anyerror!void,

        pub fn writeAll(self: *GenericWriter(T), data: []const u8) !void {
            return self.writeAllFn(self.ptr, data);
        }
    };
}

pub const GenericFile = struct {
    fd: std.posix.fd_t,

    pub fn writeAll(self: *GenericFile, data: []const u8) !void {
        _ = try std.posix.write(self.fd, data);
    }

    pub fn getGenericWriter(self: *GenericFile) GenericWriter(GenericFile) {
        return .{ .ptr = self, .writeAllFn = &writeAll };
    }
};

test "crude writer" {
    var file = File{ .fd = std.posix.STDOUT_FILENO };
    var writer = file.crudeWriter();
    try writer.writeAll("Writing from an interface\n");
    // but there is no way to call writeAll direclty
    // You'll have to do something like this
    try File.writeAll(@ptrCast(&file), "Writing directly\n");
}

test "refined writer" {
    var file = RefinedFile{ .fd = std.posix.STDOUT_FILENO };
    // writing via an interface
    var writer = file.refinedWriter();
    try writer.writeAll("Writing from an interface\n");
    // writing direclty
    try file.writeAll("Writing directly\n");
}

test "generic writer" {
    var file = GenericFile{ .fd = std.posix.STDOUT_FILENO };
    // writing via an interface
    var writer = file.getGenericWriter();
    try writer.writeAll("Writing from an interface\n");
    // writing direclty
    try file.writeAll("Writing directly\n");
}
