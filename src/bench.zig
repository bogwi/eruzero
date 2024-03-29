const std = @import("std");
const eruZero = @import("eruzero.zig").eruZero;
const stdout = std.io.getStdOut().writer();
const assert = std.debug.assert;
const eql = std.mem.eql;

const HELP =
    \\eruZero benchmark HELP menu
    \\
    \\command prompt example: 
    \\      zig build bench -- [option]
    \\
    \\info:
    \\      options are optional
    \\      default test runs on 1_000_000 of operations
    \\
    \\Options:
    \\      [ops], unsigned integer, 
    \\      the number of operations you are interested to benchmark to run
    \\
    \\      [-h], string,
    \\      display this menu
    \\ 
;
fn testLoop(comptime map_: anytype, N: usize, keys: anytype, allocator: std.mem.Allocator) !void {
    // Get a random generator for re-shuffling the keys
    var prng = std.rand.DefaultPrng.init(@abs(std.time.timestamp()));
    const random = prng.random();

    // ------------------ READ HEAVY -----------------//
    // ---- read 98, insert 1, remove 1, update 0 --- //

    // Initiate the map
    var map = map_[0].init(allocator);

    // Initial input for the test because we start with read.
    for (keys.items[0..98]) |key| {
        try map.put(key, key);
    }

    // Start the timer
    var time: u128 = 0;
    var aggregate: u128 = 0;
    var timer = try std.time.Timer.start();
    var start = timer.lap();

    // Cycle of 100 operations each
    for (0..N / 100) |i| {

        // Read the slice of 98 keys
        for (keys.items[i .. i + 98]) |key| {
            assert(map.get(key) == key);
        }

        // Insert 1 new
        try map.put(keys.items[i + 98], keys.items[i + 98]);

        // Remove 1
        assert(map.remove(keys.items[i]));
    }
    var end = timer.read();
    time += end - start;
    aggregate += time;

    // Print stats //
    // Test' individual stats
    try writeStamps("RH", N, time);

    // Clear the map
    assert(map.count() == 98);
    map.clearAndFree();

    // ------------------ EXCHANGE -------------------//
    // -- read 10, insert 40, remove 40, update 10 -- //

    // Re-shuffle the keys
    random.shuffle(@TypeOf(keys.items[0]), keys.items);

    // Initial input for the test, 10 keys, because we start with read
    for (keys.items[0..10]) |key| {
        try map.put(key, key);
    }

    // Clear the time, re-start the timer
    time = 0;
    timer = try std.time.Timer.start();
    start = timer.lap();

    // Cycle of 100 operations each
    var k: usize = 0; // helper coefficient to get the keys rotating
    for (0..N / 100) |i| {

        // Read 10
        for (keys.items[i + k .. i + k + 10]) |key| {
            assert(map.get(key) == key);
        }

        // Insert 40 new
        for (keys.items[i + k + 10 .. i + k + 50]) |key| {
            try map.put(key, key);
        }

        // Remove 40
        for (keys.items[i + k .. i + k + 40]) |key| {
            assert(map.remove(key));
        }

        // Update 10
        for (keys.items[i + k + 40 .. i + k + 50]) |key| {
            try map.put(key, key);
        }

        k += 39;
    }
    end = timer.read();
    time += end - start;
    aggregate += time;

    // Print stats //
    // Test' individual stats
    try writeStamps("EX", N, time);

    // Clear the map
    assert(map.count() == 10);
    map.clearAndFree();

    // --------------- EXCHANGE HEAVY --------------//
    // -- read 1, insert 98, remove 98, update 1 -- //

    // Re-shuffle the keys
    random.shuffle(@TypeOf(keys.items[0]), keys.items);

    // Initial input for the test, 10 keys, because we start with read
    for (keys.items[0..1]) |key| {
        try map.put(key, key);
    }

    // Clear the time, re-start the timer
    time = 0;
    timer = try std.time.Timer.start();
    start = timer.lap();

    // Cycle of 198 operations each
    k = 0; // helper coefficient to get the keys rotating
    for (0..N / 198) |i| {

        // Read 1
        for (keys.items[i + k .. i + k + 1]) |key| {
            assert(map.get(key) == key);
        }

        // Insert 98 new
        for (keys.items[i + k + 1 .. i + k + 99]) |key| {
            try map.put(key, key);
        }

        // Remove 98
        for (keys.items[i + k .. i + k + 98]) |key| {
            assert(map.remove(key));
        }

        // Update 1
        for (keys.items[i + k + 98 .. i + k + 99]) |key| {
            try map.put(key, key);
        }

        k += 97;
    }
    end = timer.read();
    time += end - start;
    aggregate += time;

    // Print stats //
    // Test' individual stats
    try writeStamps("EXH", N, time);

    // Clear the map
    assert(map.count() == 1);
    map.clearAndFree();

    // ---------------- RAPID GROW -----------------//
    // -- read 5, insert 80, remove 5, update 10 -- //

    // Re-shuffle the keys
    random.shuffle(@TypeOf(keys.items[0]), keys.items);

    // Accelerate by adjusting the map's initial capacity
    try map.ensureTotalCapacity(@intCast(N));

    // Initial input for the test, 5 keys, because we start with read
    for (keys.items[0..5]) |key| {
        try map.put(key, key);
    }

    // Clear the time, re-start the timer
    time = 0;
    timer = try std.time.Timer.start();
    start = timer.lap();

    // Cycle of 100 operations each
    k = 0; // helper coefficient to get the keys rotating
    for (0..N / 100) |i| {

        // Read 5
        for (keys.items[i + k .. i + k + 5]) |key| {
            assert(map.get(key) == key);
        }

        // Insert 80 new
        for (keys.items[i + k + 5 .. i + k + 85]) |key| {
            try map.put(key, key);
        }

        // Remove 5
        for (keys.items[i + k .. i + k + 5]) |key| {
            assert(map.remove(key));
        }

        // Update 10
        for (keys.items[i + k + 5 .. i + k + 15]) |key| {
            try map.put(key, key);
        }

        k += 79;
    }
    end = timer.read();
    time += end - start;
    aggregate += time;

    // Print stats //
    // Test' individual stats
    try writeStamps("RG", N, time);

    // Aggregate stats
    try writeStamps("aggregate", N * 4, aggregate);
    try stdout.print("\n", .{});

    // Release the map
    map.deinit();
    // -------------------TEST END----------------------//

}
fn benchmark(N: usize) !void {
    const T = u64;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) {
        @panic("memory leak ...");
    };
    const allocator = gpa.allocator();

    // Get a random seed and set the random numbers generator
    const dna = blk: {
        var xy: u64 = undefined;
        try std.os.getrandom(std.mem.asBytes(&xy));
        break :blk xy;
    };
    const pumpkin_seed = @as(u64, @abs(dna));
    var prng = std.rand.DefaultPrng.init(pumpkin_seed);
    const random = prng.random();

    // Get an array of random keys of the size N, same for every map
    var keys = std.ArrayList(T).init(allocator);
    defer keys.deinit();
    for (0..N) |_| {
        const key = random.intRangeAtMost(T, std.math.maxInt(u32), std.math.maxInt(T) - 1);
        keys.append(key) catch unreachable;
    }
    random.shuffle(T, keys.items);

    // A wrapper around std.AutoArrayHashMap to ensure API compatibility
    const AutoArrayHashMap = struct {
        map: std.AutoArrayHashMap(T, T),

        const Self = @This();

        pub fn init(alloc: std.mem.Allocator) Self {
            return Self{ .map = std.AutoArrayHashMap(T, T).init(alloc) };
        }
        pub fn deinit(self: *Self) void {
            self.map.deinit();
        }
        pub fn put(self: *Self, key: T, val: T) !void {
            return try self.map.put(key, val);
        }
        pub fn get(self: Self, key: T) ?T {
            return self.map.get(key);
        }
        pub fn remove(self: *Self, key: T) bool {
            return self.map.swapRemove(key);
        }
        pub fn ensureTotalCapacity(self: *Self, N_: usize) !void {
            try self.map.ensureTotalCapacity(N_);
        }
        pub fn clearAndFree(self: *Self) void {
            self.map.clearAndFree();
        }
        pub fn count(self: Self) u64 {
            return self.map.count();
        }
    };

    // Hash tables to test
    const MAPS = comptime .{
        .{ eruZero(T, T), "eruZero" },
        .{ AutoArrayHashMap, "ArrayHashMap" },
        .{ std.AutoHashMap(T, T), "HashMap" },
    };

    // Cosmetic function, number formatting
    var buffer: [16]u8 = undefined;
    const len = pretty(N, &buffer, allocator);

    // Print benchmark header
    try stdout.print("\n{s: >38}|", .{"HASHMAP BENCHMARK"});
    try stdout.print("\n{s: >24} ops:each test|\n", .{buffer[0..len]});
    try stdout.print("\n|{s: <13}|{s: >11}|{s: >11}|", .{ "name", "Tp Mops:sec", "Rt :sec" });
    try stdout.print("\n {s:=>37}", .{""});

    // // inline testing
    inline for (MAPS) |map_| {
        try stdout.print("\n|{s: <37}|", .{map_[1]});
        try testLoop(map_, N, keys, allocator);
    }

    // no-inline testing
    // try stdout.print("\n|{s: <37}|", .{MAPS[0][1]});
    // try testLoop(MAPS[0], N, keys, allocator);
    // try stdout.print("\n|{s: <37}|", .{MAPS[1][1]});
    // try testLoop(MAPS[1], N, keys, allocator);
    // try stdout.print("\n|{s: <37}|", .{MAPS[2][1]});
    // try testLoop(MAPS[2], N, keys, allocator);
}

fn pretty(N: usize, buffer: []u8, alloc: std.mem.Allocator) usize {
    var stack = std.ArrayList(u8).init(alloc);
    defer stack.deinit();

    var N_ = N;
    var counter: u8 = 0;

    while (N_ > 0) : (counter += 1) {
        const rem: u8 = @intCast(N_ % 10);
        if (counter == 3) {
            stack.append(0x5F) catch unreachable;
            counter = 0;
        }
        stack.append(rem + 48) catch unreachable;
        N_ = @divFloor(N_, 10);
    }

    var j: usize = 0;
    var k: usize = stack.items.len;

    while (k > 0) : (j += 1) {
        k -= 1;
        buffer[j] = stack.items[k];
    }

    return stack.items.len;
}

fn toSeconds(t: u128) f64 {
    return @as(f64, @floatFromInt(t)) / 1_000_000_000;
}

fn throughput(N: usize, time: u128) f64 {
    return @as(f64, @floatFromInt(N)) / toSeconds(time) / 1_000_000;
}

fn writeStamps(test_name: []const u8, N: usize, time: u128) !void {
    const throughput_ = throughput(N, time);
    const runtime = toSeconds(time);

    try stdout.print("\n|{s: <13}|{d: >11.2}|{d: >11.6}|", .{ test_name, throughput_, runtime });
}

pub fn main() !void {
    // get args
    var buffer: [1024]u8 = undefined;
    var fixed = std.heap.FixedBufferAllocator.init(buffer[0..]);
    const args = try std.process.argsAlloc(fixed.allocator());
    defer std.process.argsFree(fixed.allocator(), args);

    // default number of operations
    var N: usize = 1_000_000;

    var i: usize = 1;
    if (args.len > 3) {
        std.debug.print(HELP ++ "\n", .{});
        return;
    }

    while (i < args.len) : (i += 1) {
        var integer: bool = true;

        for (args[i]) |char| {
            if (char < 48 or char > 57 and char != 95) integer = false;
        }

        if (integer) {
            // TODO give warning if N > 1B, y - n ?

            N = try std.fmt.parseUnsigned(usize, args[i], 10);
            break;
        } else if (std.mem.eql(u8, args[i], "-h")) {
            std.debug.print(HELP ++ "\n", .{});
            return;
        } else {
            std.debug.print(HELP ++ "\n", .{});
            return;
        }
    }

    try benchmark(N);
}
