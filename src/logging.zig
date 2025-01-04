const std = @import("std");

pub const std_options = .{
    .log_level = .debug,
    .log_fn = customLog,
};

fn customLog(
    comptime lvl: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    // Ignore all non-error logging from sources other than
    // .my_project, .nice_library and the default
    const scope_prefix = "(" ++ switch (scope) {
        .my_project, .nice_library, std.log.default_log_scope => @tagName(scope),
        else => if (@intFromEnum(lvl) <= @intFromEnum(std.log.Level.err))
            @tagName(scope)
        else
            return,
    } ++ "): ";

    const prefix = "[" ++ comptime lvl.asText() ++ "] " ++ scope_prefix;

    // Print the message to stderr, silently ignoring any errors
    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.print(prefix ++ format ++ "\n", args) catch return;

    const stdout = std.io.getStdOut().writer();
    stdout.print("hello this is a message\n", .{}) catch {};
}

test "log" {
    std.log.debug("hello this is a message", .{});
    const my_project_log = std.log.scoped(.my_project);
    my_project_log.debug("hello this is a message", .{});
    std.debug.print("This is a message\n", .{});
}
