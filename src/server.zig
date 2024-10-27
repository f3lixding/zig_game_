const std = @import("std");
const net = std.net;
const spawn = std.Thread.spawn;
const SpawnConfig = std.Thread.SpawnConfig;

pub const HttpServer = struct {
    addr: net.Address,

    pub fn init() !HttpServer {
        const address = "127.0.0.1";
        const port = 3002;
        std.debug.print("Creating a server listening on {s}:{d}\n", .{ address, port });
        const addr = try net.Address.parseIp4(address, port);
        return .{ .addr = addr };
    }

    // Start the server
    // This will return the thread spawned with the server running
    // It is the responsibility of the caller to join the thread
    pub fn produceServer(self: *HttpServer) !net.Server {
        const server = try self.addr.listen(.{});
        return server;
    }

    pub fn deinit(_: *HttpServer) void {
        // TODO: free resources
    }
};

pub fn runServer(server: *net.Server) !void {
    while (true) {
        std.debug.print("Waiting for connection...\n", .{});
        var connection = server.accept() catch |err| {
            std.debug.print("Failed to establish connection: {}\n", .{err});
            continue;
        };
        defer connection.stream.close();

        var read_buffer: [1024]u8 = undefined;
        var http_server = std.http.Server.init(connection, &read_buffer);

        var request = http_server.receiveHead() catch |err| {
            std.debug.print("Failed to receive request: {any}\n", .{err});
            continue;
        };
        std.debug.print("Handling request for {s}\n", .{request.head.target});
        const reader = try request.reader();
        _ = reader;

        try request.respond("Hello http!\n", .{});
    }
}
