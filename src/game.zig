const std = @import("std");

pub const Game = struct {
    session_name: []const u8 = "Fewargame",
    allocator: std.mem.Allocator,
    game_state: GameState([]const u8) = GameState([]const u8){
        .rwlock = std.Thread.RwLock{},
        .underlyingData = &[_]u8{ 'a', 'b', 'c' },
    },

    pub fn init(self: *Game) !void {
        _ = self;
    }

    pub fn deinit(self: *Game) void {
        _ = self;
        // TODO: implement deinit location
    }

    pub fn iterateAndGetState(self: *Game) !GameState([]const u8) {
        std.debug.print("Game inner state from readState has an addr of {x}\n", .{&self.game_state.readState()});
        std.debug.print("Game inner state from itself has an addr of {x}\n", .{&self.game_state.underlyingData});
        return self.game_state;
    }

    pub fn printName(self: Game) void {
        std.debug.print("Hello, {s}!\n", .{self.session_name});
    }
};

// TODO: add more relevant state here as the game logic develops
pub fn GameState(comptime T: type) type {
    return struct {
        const Self = @This();

        rwlock: std.Thread.RwLock,
        underlyingData: T = undefined,

        pub fn init() GameState {
            return .{
                .rwlock = std.Thread.RwLock{},
            };
        }

        // If we don't want to copy the data, we will need to return a pointer to the underlying data
        // but we would also need to return the read guard as well
        pub fn readState(self: *Self) T {
            self.rwlock.lockShared();
            defer self.rwlock.unlockShared();
            return self.underlyingData;
        }
    };
}

test "game init test" {
    // TODO: add tests for init (for when you have more logic for init)
}
