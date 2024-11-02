const rl = @import("raylib");
const std = @import("std");
const HttpServer = @import("server.zig").HttpServer;
const runServer = @import("server.zig").runServer;
const spawn = std.Thread.spawn;
const Game = @import("game.zig").Game;
const MultiShotTube = @import("channel/multi_shot_tube.zig").MultiShotTube;

pub fn main() anyerror!void {
    const screenWidth = 800;
    const screenHeight = 450;
    var ballPosition = rl.Vector2.init(screenWidth / 2, screenHeight / 2);
    rl.initWindow(screenWidth, screenHeight, "Just trying to learn with this shitty game");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    var httpServer = HttpServer.init() catch unreachable;
    var server = try httpServer.produceServer();
    const serverThread = try spawn(.{}, runServer, .{&server});
    _ = serverThread;

    var game = Game{
        .allocator = std.heap.page_allocator,
    };
    _ = try game.iterateAndGetState();
    _ = MultiShotTube(u8, 10){};

    // Main game loop
    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.white);

        if (rl.isKeyDown(rl.KeyboardKey.key_s)) {
            ballPosition.x -= 2;
        }
        if (rl.isKeyDown(rl.KeyboardKey.key_f)) {
            ballPosition.x += 2;
        }
        if (rl.isKeyDown(rl.KeyboardKey.key_d)) {
            ballPosition.y += 2;
        }
        if (rl.isKeyDown(rl.KeyboardKey.key_e)) {
            ballPosition.y -= 2;
        }
        rl.drawCircleV(ballPosition, 10, rl.Color.red);
    }

    // Uncomment the following line if you want the server thread to be waited for
    // serverThread.join();
}

test "some test" {}
