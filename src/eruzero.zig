// MIT License
// Copyright(c) 2023 bogwi https://github.com/bogwi

const std = @import("std");
const activeTag = std.meta.activeTag;
const eql = std.meta.eql;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

/// **eruZero**.
///
/// An idiosyncratic implementation of hashmap
/// using ZIG's std.ArrayList as underlying storage.
///
/// The map does not manage the memory allocation.
/// The map takes any eligible type for hashing (any accept `.Float` and untagged `.Union` will do)
/// without you crafting custom hashing and comparison functions.
/// The map will continue inserting new items
/// as long as std.ArrayList does not fail to allocate new space.
pub fn eruZero(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();

        const SIZE = [41]usize{ 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072, 262144, 524288, 1048576, 2097152, 4194304, 8388608, 16777216, 33554432, 67108864, 134217728, 268435456, 536870912, 1073741824, 2147483648, 4294967296, 8589934592, 17179869184, 34359738368, 68719476736, 137438953472, 274877906944, 549755813888, 1099511627776, 2199023255552, 4398046511104, 8796093022208 };

        /// The inserted `Item` is a tagged `.Union` of three fields:
        /// *alive* holds the entry pair of key and value.
        /// *del* and *empty* are metadata records.
        /// Only one field is active at a time.
        const Item = union(enum(u2)) {
            alive: Entry,
            del: void,
            empty: void,
        };
        const Entry = struct { key: K, value: V };

        /// OutOfSize error will happen if and only if the size max, as 2^44,
        /// is not sufficient to hold the requested number of entries.
        ///
        /// OutOfMemory error is triggered by an allocator if it is unable to
        /// allocate new space to hold the requested number of entries.
        const SizeError = error{
            OutOfSize,
            OutOfMemory,
        };

        /// Routine managing struct.
        pub const Dashboard = struct {
            const DB = @This();
            const Table = std.ArrayList(Item);

            table: Table,
            limit: u8 = 0,
            n: u64 = 0,
            alloc: Allocator,
            deleted: u64 = 0,

            fn hash(key: anytype, comptime strategy: @TypeOf(.enum_literal)) u64 {
                var hasher = std.hash.Wyhash.init(0);
                std.hash.autoHashStrat(&hasher, key, strategy);
                return hasher.final();
            }
            fn comp(db: DB, key: K) u64 {
                _ = db;
                return hash(key, .Deep);
            }
            fn N(db: DB) usize {
                return db.table.items.len;
            }
            fn sizeOk(db: DB) bool {
                return db.n < db.N() / 10 * 8;
            }
            fn adjustSelf(db: *DB, self: *Self) !void {
                if (!db.sizeOk()) {
                    try db.resize(self);
                } else if (db.deleted > db.N()) {
                    db.limit -|= 1;
                    try db.resize(self);
                }
            }
            fn resize(db: *DB, self: *Self) SizeError!void {
                db.limit += 1;

                if (db.limit > SIZE[SIZE.len - 1]) return SizeError.OutOfSize;

                var array = Dashboard.Table.init(db.alloc);
                try array.resize(SIZE[db.limit]);
                const empty = Item{ .empty = {} };
                @memset(array.items, empty);

                var new = Self{
                    .dashboard = .{
                        .table = array,
                        .alloc = db.alloc,
                        .limit = db.limit,
                    },
                };
                defer new.deinit();

                for (db.table.items) |item| {
                    const tag = activeTag(item);
                    if (tag == .alive)
                        assert(new.putAssumeCapacity(item.alive.key, item.alive.value));
                }
                std.mem.swap(Self, self, &new);
            }
        };

        dashboard: Dashboard,

        /// Returns a copy of this map, using the same allocator.
        pub fn clone(self: *Self) SizeError!Self {
            return .{ .dashboard = .{ .table = try self.dashboard.table.clone(), .limit = self.dashboard.limit, .n = self.dashboard.n, .alloc = self.dashboard.alloc, .deleted = self.dashboard.deleted } };
        }

        /// Initiates the map.
        pub fn init(alloc: Allocator) Self {
            return .{
                .dashboard = .{
                    .table = blk: {
                        var array = Dashboard.Table.init(alloc);
                        array.resize(SIZE[0]) catch unreachable;
                        const empty = Item{ .empty = {} };
                        @memset(array.items, empty);
                        break :blk array;
                    },
                    .alloc = alloc,
                },
            };
        }

        /// Releases the backing storage and invalidate all entries.
        pub fn deinit(self: *Self) void {
            self.dashboard.table.deinit();
            self.* = undefined;
        }

        /// Renders the map to its initial state, erasing all the items.
        pub fn clearAndFree(self: *Self) void {
            self.dashboard.n = 0;
            self.dashboard.limit = 0;
            self.dashboard.table.shrinkRetainingCapacity(SIZE[0]);
            const empty = Item{ .empty = {} };
            @memset(self.dashboard.table.items, empty);
        }

        /// Renders every slot in the map to empty.
        /// No changes to the map's underlying size.
        /// Think of it as if using an erase gum across the entire map.
        pub fn clearRetainingCapacity(self: *Self) void {
            self.dashboard.n = 0;
            const empty = Item{ .empty = {} };
            @memset(self.dashboard.table.items, empty);
        }

        /// Adjusts the map's size to boost input speed. Guarantees, that
        /// no allocation will occur up to the specified size.
        /// It is a good practice to make this call right after the map's initiation,
        /// assuming the desired size is known beforehand.
        /// However, this method can be called at any time.
        /// Silently returns, if the map's current size
        /// is already best to fit the specified size.
        pub fn ensureTotalCapacity(self: *Self, size: usize) SizeError!void {
            var log: f32 = std.math.log2(@as(f32, @floatFromInt(size)));
            log = @round(log);

            const best_limit = @as(u8, @intFromFloat(log)) -| 3;
            if (best_limit <= self.dashboard.limit) return;

            self.dashboard.limit = best_limit;
            try self.dashboard.resize(self);
        }

        /// Scales down the map's underlying memory to
        /// the minimum size necessary to hold the number of items
        /// the map contains the current moment. Useful after dramatic removal
        /// when the caller has deleted more than 90% of all the items
        /// and has no plans of restoring it immediately.
        /// It is designed for special situations like large drop-downs from 100Mils, or
        /// where the memory is at a premium and needs tight management.
        /// When the map already has the best size for the number of items it contains,
        /// the method returns with no work done.
        pub fn reduceMemoryImprint(self: *Self) SizeError!void {
            const quota = self.dashboard.N() / 10 * 4;
            if (self.count() >= quota) return;

            var log: f32 = std.math.log2(@as(f32, @floatFromInt(self.count())));
            log = @round(log);
            // var best_limit: u8 = if (log > 3) @intFromFloat(log - 3) else 0;
            const best_limit: u8 = @as(u8, @intFromFloat(log)) -| 3;
            if (self.dashboard.limit == best_limit + 1) return;

            self.dashboard.limit = best_limit;
            try self.dashboard.resize(self);
        }

        /// Number of entries in the map
        pub fn count(self: Self) u64 {
            return self.dashboard.n;
        }

        /// The *total* number of entries the map might hold.
        /// By the policy, the user claims 80% of that size before new allocation kicks in;
        /// see `capacityClaimed()`. If you want to maximize the map, use
        /// `putAssumeCapacity()`.
        pub fn capacity(self: Self) u64 {
            return self.dashboard.N();
        }
        /// Number of entries the map might hold
        /// before allocation kicks in.
        pub fn capacityClaimed(self: Self) u64 {
            return self.dashboard.N() / 10 * 8;
        }

        /// Number of *new* entries the map might hold
        /// before allocation kicks-in.
        pub fn available(self: Self) u64 {
            return self.capacityClaimed() - self.count();
        }

        /// Inserts the key-value pair into the map.
        /// Replaces existing value if the same key has been found!
        pub fn put(self: *Self, key: K, value: V) SizeError!void {
            try self.dashboard.adjustSelf(self);
            assert(self.putAssumeCapacity(key, value));
        }

        /// Inserts the key-value pair into the map,
        /// returning back a pointer to the *new* value.
        /// Replaces existing value if the same key has been found!
        pub fn putGetPtr(self: *Self, key: K, value: V) SizeError!*V {
            try self.dashboard.adjustSelf(self);

            const gop = self.getOrPutAssumeCapacity(key);
            gop.value_ptr.* = value;
            return gop.value_ptr;
        }

        /// Inserts the key-value pair into the map
        /// *only if* no entry associated with the key has been found.
        /// Guarantees no update will happen.
        /// This method is an inverse of `update()`.
        pub fn putNoClobber(self: *Self, key: K, value: V) SizeError!void {
            try self.dashboard.adjustSelf(self);

            const gop = self.getOrPutAssumeCapacity(key);
            if (gop.found_existing) return;
            gop.value_ptr.* = value;
            return;
        }

        /// Inserts key-value pair into the map and returns true,
        /// asserting the map has enough space to hold one more item,
        /// and no allocation is needed.
        /// Replaces existing value if the same key has been found!
        ///
        /// Returns *false* if the user has maximized the map, silently preventing
        /// any insertions or updates.
        /// This method will never crash under your back.
        /// Using it till *false* gives you a quick way to fill the map up to
        /// the last available socket if it is your goal. See `capacityAssumed()`
        /// method.
        ///
        /// For updates when the map is full, use `update()`.
        pub fn putAssumeCapacity(self: *Self, key: K, value: V) bool {
            if (self.count() == self.dashboard.N()) return false;

            const gop = self.getOrPutAssumeCapacity(key);
            gop.value_ptr.* = value;
            return true;
        }

        /// Updates the value of the entry associated with the key,
        /// returning an existing entry. If no such entry is found,
        /// returns null. Clobbers the data. Does not change the map's size.
        /// Think of it as an update on existing with a return of the previous.
        ///
        /// If you only need to update the entry, use `update()`.
        pub fn fetchPut(self: *Self, key: K, value: V) SizeError!?Entry {
            try self.dashboard.adjustSelf(self);
            const itemPtr = self.getItemPtr(key);

            // catch possible null
            if (itemPtr) |item| {
                const result = item.alive;
                item.* = Item{ .alive = Entry{ .key = key, .value = value } };
                return result;
            }
            return null;
        }

        /// Updates the value of the entry associated with the key
        /// and returns *true*. If no such entry is found, it returns *false*.
        /// The method is safe to call whenever the update is needed.
        /// The method is an inverse of `putNoClobber()`.
        ///
        /// If you need to return the previous entry after the update, use `fetchPut()`.
        pub fn update(self: *Self, key: K, value: V) bool {
            const valuePtr = self.getPtr(key);

            // catch possible null
            if (valuePtr) |value_| {
                value_.* = value;
                return true;
            }
            return false;
        }

        /// Adapted from Zig's std HashMap
        /// to ensure API compatibility. It is marked as non-public.
        const GetOrPutResult = struct {
            key_ptr: *K,
            value_ptr: *V,
            found_existing: bool,
            index: u64,
        };

        /// Searches for the entry associated with the key, and
        /// returns a struct containing four fields:
        /// > `key_ptr: *K,
        /// value_ptr: *V,
        /// found_existing: bool,
        /// index: usize`
        ///
        /// If `found_existing` is *true*, meaning there is an
        /// entry associated with the given key, `key_ptr` will point to the key,
        /// `value_ptr` will point to the value.
        /// If *false*, the method will put the given key into the map,
        /// and `key_ptr` will be pointing to it,
        /// however the `value_ptr` will be pointing to an *undefined* value.
        /// The user should initialize the value.
        pub fn getOrPut(self: *Self, key: K) SizeError!GetOrPutResult {
            try self.dashboard.adjustSelf(self);
            const result = self.getOrPutAssumeCapacity(key);
            return result;
        }

        /// This method is adapted from Zig's std HashMap
        /// to ensure API compatibility. It is marked as non-public.
        fn getOrPutAssumeCapacity(self: *Self, key: K) GetOrPutResult {
            const h = self.dashboard.comp(key);
            const N_ = @as(u64, self.dashboard.N() - 1);
            var index = @as(u64, @truncate(h & N_));
            var tag = activeTag(self.dashboard.table.items[index]);
            var step: u64 = 0;
            var found_del = N_ + 1;

            while (tag != .empty) : (step += 1) {
                if (step > N_ + 1) {
                    break;
                }
                if (tag == .alive and eql(self.dashboard.table.items[index].alive.key, key)) {
                    var item = &self.dashboard.table.items[index];
                    return GetOrPutResult{ .key_ptr = &item.alive.key, .value_ptr = &item.alive.value, .found_existing = true, .index = index };
                } else if (found_del == N_ + 1 and tag == .del) {
                    // Record the first del's index; yet continue searching,
                    // perhaps an entry with the same key is found
                    found_del = index;
                }
                index = (index + 1) & N_;
                tag = activeTag(self.dashboard.table.items[index]);
            }

            // We prefer first encountered .del(deleted) over .empty
            if (found_del < N_ + 1) {
                index = found_del;
            }
            self.dashboard.n += 1;
            self.dashboard.table.items[index] = Item{ .alive = Entry{ .key = key, .value = undefined } };
            var item = &self.dashboard.table.items[index];
            return GetOrPutResult{ .key_ptr = &item.alive.key, .value_ptr = &item.alive.value, .found_existing = false, .index = index };
        }

        /// Returns a pointer to the Item container associated with the key
        /// or null if no such item. The method is marked as non-public.
        fn getItemPtr(self: Self, key: K) ?*Item {
            if (self.count() == 0) return null;

            const h = self.dashboard.comp(key);
            const N_ = @as(u64, self.dashboard.N() - 1);
            var index = @as(u64, @truncate(h & N_));
            var tag = activeTag(self.dashboard.table.items[index]);
            var step: u32 = 0;
            // TODO investigate.
            // For reasons unknown, when the step variable is set to u64,
            // the method does not work in ReleaseFast mode.

            while (tag != .empty) : (step += 1) {
                if (step > N_ + 1) {
                    return null;
                }
                if (tag == .alive and eql(self.dashboard.table.items[index].alive.key, key)) {
                    return &self.dashboard.table.items[index];
                }
                index = (index + 1) & N_;
                tag = activeTag(self.dashboard.table.items[index]);
            }
            return null;
        }

        /// Returns a pointer to the value associated with the key
        /// or null if no such entry is present in the map.
        pub fn getPtr(self: Self, key: K) ?*V {
            return if (self.getItemPtr(key)) |item| &item.alive.value else null;
        }

        /// Returns an entry associated with the key or null if no such entry present in the map.
        pub fn getEntry(self: Self, key: K) ?Entry {
            return if (self.getItemPtr(key)) |item| item.alive else null;
        }

        /// Returns a value associated with the key or null if no such entry present in the map.
        pub fn get(self: Self, key: K) ?V {
            return if (self.getItemPtr(key)) |item| item.alive.value else null;
        }

        /// Checks if an entry is associated with the given key in the map.
        pub fn contains(self: Self, key: K) bool {
            return if (self.get(key)) |_| true else false;
        }

        /// Removes an entry associated with the key from the map. Returns *true* upon
        /// success; *false*, if not such entry exist.
        pub fn remove(self: *Self, key: K) bool {
            const itemPtr = self.getItemPtr(key);

            // catch possible null
            if (itemPtr) |item| {
                item.* = Item{ .del = {} };
                self.dashboard.n -= 1;
                self.dashboard.deleted += 1;
                return true;
            }
            return false;
        }

        /// Removes an entry associated with the key from the map,
        /// returning it back to the user.  If no such entry exist, returns *null*.
        pub fn fetchRemove(self: *Self, key: K) ?Entry {
            const itemPtr = self.getItemPtr(key);

            // catch possible null
            if (itemPtr) |item| {
                const result = item.alive;
                item.* = Item{ .del = {} };
                self.dashboard.n -= 1;
                self.dashboard.deleted += 1;
                return result;
            }
            return null;
        }

        /// Returns map entries in the format of `{ key_ptr`, `value_ptr }`,
        /// without preserving the insertion order.
        pub fn iterator(self: *Self) Iterator {
            return .{ .map = self };
        }
        pub const Iterator = struct {
            map: *Self,
            idx: u64 = 0,

            pub fn next(it: *Iterator) ?struct { key_ptr: *K, value_ptr: *V } {
                if (it.map.count() == 0) return null;

                while (it.idx < SIZE[it.map.dashboard.limit]) : (it.idx += 1) {
                    var item = &it.map.dashboard.table.items[it.idx];
                    const tag = activeTag(item.*);
                    if (tag == .alive) {
                        it.idx += 1;
                        return .{ .key_ptr = &item.alive.key, .value_ptr = &item.alive.value };
                    }
                }
                return null;
            }
            pub fn reset(it: *Iterator) void {
                it.idx = 0;
            }
        };

        // SET OPERATIONS //

        /// Inserts all entries of the *other* into *self* with no duplicates allowed.
        /// If you need the merge result as the separate map, use`unio()`.
        pub fn merge(self: *Self, other: *Self) void {
            var other_iter = other.iterator();
            while (other_iter.next()) |entry| {
                try self.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        /// Returns a new map, a union in between *self* and the *other*,
        /// containing **all the entries of *self* and the *other*
        /// combined with no duplicates allowed.**
        ///
        /// The new map uses the same allocator as self and needs a separate deinit() call.
        pub fn unio(self: *Self, other: *Self) SizeError!Self {
            var smaller: *Self = undefined;
            var bigger: *Self = undefined;

            if (self.count() <= other.count()) {
                smaller = self;
                bigger = other;
            } else {
                smaller = other;
                bigger = self;
            }

            var smaller_iter = smaller.iterator();
            var copy = try bigger.clone();

            while (smaller_iter.next()) |entry| {
                try copy.put(entry.key_ptr.*, entry.value_ptr.*);
            }
            return copy;
        }

        /// Returns a new map, an intersection in between *self* and the
        /// *other*, containing **only those entries of *self* that also belong to the *other*.**
        ///
        /// The new map uses the same allocator as self and needs a separate deinit() call.
        pub fn intersection(self: *Self, other: *Self) SizeError!Self {
            var smaller: *Self = undefined;
            var bigger: *Self = undefined;

            if (self.count() <= other.count()) {
                smaller = self;
                bigger = other;
            } else {
                smaller = other;
                bigger = self;
            }

            var smaller_iter = smaller.iterator();
            var copy = try smaller.clone();

            while (smaller_iter.next()) |entry| {
                const key = entry.key_ptr;
                if (!bigger.contains(key.*))
                    assert(copy.remove(key.*));
            }
            return copy;
        }

        /// Returns a new map, a symmetric difference in between *self* and the *other*,
        /// containing **only those entries that belong to *self* or the *other* but not both.**
        ///
        /// The new map uses the same allocator as self and needs a separate deinit() call.
        pub fn symmetricDifference(self: *Self, other: *Self) SizeError!Self {
            var smaller: *Self = undefined;
            var bigger: *Self = undefined;

            if (self.count() <= other.count()) {
                smaller = self;
                bigger = other;
            } else {
                smaller = other;
                bigger = self;
            }

            var smaller_iter = smaller.iterator();
            var copy = try bigger.clone();

            while (smaller_iter.next()) |entry| {
                const gop = try copy.getOrPut(entry.key_ptr.*);
                if (!gop.found_existing) {
                    gop.value_ptr.* = entry.value_ptr.*;
                } else {
                    copy.dashboard.table.items[gop.index] = Item{ .del = {} };
                    copy.dashboard.n -= 1;
                    copy.dashboard.deleted += 1;
                }
            }
            return copy;
        }

        /// Returns a new map, a relative complement in between *self* and
        /// the *other*, containing **only those entries
        /// which belong to *self* but not the *other*.**
        ///
        /// The new map uses the same allocator as self and needs a separate deinit() call.
        pub fn relativeComplement(self: *Self, other: *Self) SizeError!Self {
            var self_iter = self.iterator();
            var copy = try self.clone();

            while (self_iter.next()) |entry| {
                const key = entry.key_ptr;
                if (other.contains(key.*))
                    assert(copy.remove(key.*));
            }
            return copy;
        }
    };
}

// TESTING SECTION

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const print = std.debug.print;
const allocatorT = std.testing.allocator;

test "eruZero: basics" {
    var map = eruZero(u16, u16).init(allocatorT);
    defer map.deinit();

    var i: u16 = 16;

    while (i < 32) : (i += 1) {
        try map.put(i, i);
        try expect(map.contains(i));
    }

    try expect(map.count() == 16);

    i = 48;
    while (i > 16) {
        i -= 1;
        if (i >= 32) {
            try expect(!map.update(i, i * 2));
        } else try expect(map.update(i, i * 2));
    }

    try expect(map.count() == 16);

    while (i < 64) : (i += 1) {
        try map.putNoClobber(i, i * 3);
        if (i < 32) {
            try expect(map.get(i).? == i * 2);
        } else try expect(map.get(i).? == i * 3);
    }

    try expect(map.count() == 64 - 16);

    i = 48;
    while (i < 96) : (i += 1) {
        const entry = map.getOrPut(i) catch unreachable;
        if (entry.found_existing) {
            try expect(entry.key_ptr.* == i);
            try expect(entry.value_ptr.* == i * 3);
        } else entry.value_ptr.* = i * 4;
    }

    try expect(map.count() == 32 + 48);

    var keys: [96]*u16 = undefined;

    var iter = map.iterator();
    while (iter.next()) |entry| {
        i -= 1;
        const key = entry.key_ptr;
        keys[i] = key;
    }

    //
    // ZIG 0.12.0-dev.1830+779b8e259 does not pass the last test. ZIG 0.11.0 does!
    // Multiple key.* make the key equal to zero 0.
    // Test was modified to have only one deref.
    //
    // for (keys[16..]) |key| {
    //     if (key.* < 64) {
    //         try expect(map.remove(key.*));
    //     } else try expect(map.fetchRemove(key.*).?.value == key.* * 4);
    // }

    for (keys[16..]) |key| {
        const key_deref = key.*;
        if (key_deref < 64) {
            try expect(map.remove(key_deref));
        } else {
            const value = map.fetchRemove(key_deref).?.value;
            try expect(value == key_deref * 4);
        }
    }

    try expect(map.count() == 0);
}

test "eruZero: small map - big keys" {
    var map = eruZero(u64, u64).init(allocatorT);
    defer map.deinit();
    const PRIMES = [_]u64{
        927345235741,
        927345236087,
    };
    var N: u64 = 1;
    while (N < 1001) : (N += 1) {
        try map.put(@divFloor(PRIMES[0], N * 11), PRIMES[0]);
        try map.put(@divFloor(PRIMES[1], N * 17), PRIMES[1]);
        try map.put(@divFloor(PRIMES[0], N * 11), PRIMES[0]);
        try map.put(@divFloor(PRIMES[1], N * 17), PRIMES[1]);

        try expect(map.remove(@divFloor(PRIMES[1], N * 17)));
        try expect(map.remove(@divFloor(PRIMES[0], N * 11)));
        try expect(!map.remove(@divFloor(PRIMES[1], N * 17)));
        try expect(!map.remove(@divFloor(PRIMES[0], N * 11)));
    }
}

test "eruZero: base2 removes" {
    var map = eruZero(u64, u64).init(allocatorT);
    defer map.deinit();

    var i: u64 = 0;
    while (i < 32) : (i += 1) {
        try map.put(i, i);
    }
    try expect(map.remove(16) != map.remove(16));
    try expect(map.remove(8) != map.remove(8));
    try expect(map.remove(4) != map.remove(4));
    try expect(map.remove(2) != map.remove(2));
    try expect(map.remove(1) != map.remove(1));
    try expect(map.remove(0) != map.remove(0));

    try expect(map.remove(16) == map.remove(16 + 16));
    try expect(map.remove(8) == map.remove(8 + 8));
    try expect(map.remove(4) == map.remove(4 + 4));
    try expect(map.remove(2) == map.remove(2 + 2));
    try expect(map.remove(1) == map.remove(1 + 1));
    try expect(map.remove(0) == map.remove(0 + 0));
}

test "eruZero: same % 8 inserts" {
    var map = eruZero(u32, u32).init(allocatorT);
    defer map.deinit();

    var key: u32 = 0;

    while (key < 6) : (key += 1) {
        if (key < 4) {
            try expect(map.putAssumeCapacity(key, key));
            try expect(map.putAssumeCapacity(key + 8, key));
        } else {
            try expect(!map.putAssumeCapacity(key, key));
            try expect(!map.putAssumeCapacity(key + 8, key));
        }
    }

    key -= 1;
    while (key >= 2) : (key -= 1) {
        if (key >= 4) {
            try expect(!map.remove(key));
            try expect(!map.remove(key + 8));
        } else {
            try expect(map.remove(key));
            try expect(map.remove(key + 8));
        }
    }

    key += 1;
    while (key > 0) {
        key -= 1;
        try expect(map.get(key).? == key);
        try expect(map.remove(key));
        try expect(map.get(key + 8).? == key);
        try expect(map.remove(key + 8));
    }

    while (key < 6) : (key += 1) {
        try expect(map.get(key) == null);
        try expect(map.get(key + 8) == null);
    }
}

test "eruZero: put, get and remove overlapping keys in stages" {
    var map = eruZero(usize, usize).init(allocatorT);
    defer map.deinit();

    var j: usize = 0;
    var k: usize = 16;
    // Intentionally create collisions to have situations where before
    // the insertion of the same Item might be a (deleted) entry, yet we still
    // need to go forward to override the entry while the map grows in the process.
    for (0..6) |_| {
        for (j..k * 2) |i| {
            try map.put(i, i);
            try expectEqual(i, map.get(i).?);
            try expect(if (i < k) map.remove(i & k - 1) else !map.remove(i & k - 1));
            try expectEqual(@as(?usize, null), map.get(i & k - 1));
        }
        try expect(map.count() == k);
        j = k;
        k *= 2;
    }
    for (j..k) |i| {
        try expect(map.remove(i));
        try expect(!map.contains(i));
        try expect(map.count() == k - 1 - i);
    }
}

test "put and get overlapping shuffled keys in a loop" {
    var map = eruZero(usize, usize).init(allocatorT);
    defer map.deinit();

    var prng = std.rand.DefaultPrng.init(0);
    const random = prng.random();

    var keys = std.ArrayList(usize).init(allocatorT);
    defer keys.deinit();

    var i: usize = 128;

    while (i > 0) : (i /= 2) {
        for (i..i + 128) |key| {
            keys.append(key) catch unreachable;
            try map.put(key & 64 - 1, key);
        }

        random.shuffle(usize, keys.items);
        while (keys.items.len > 0) {
            const key = keys.pop();
            if (key > 64 and key < 128 and key > 192)
                try expect(key == map.get(key & 64 - 1));
        }
    }
}

test "eruZero: more overlapping keys with shuffling" {
    var map = eruZero(u32, u32).init(allocatorT);
    defer map.deinit();

    var keys = std.ArrayList(u32).init(allocatorT);
    defer keys.deinit();

    var prng = std.rand.DefaultPrng.init(0);
    const random = prng.random();

    var N: usize = 1;
    while (N < 4) : (N += 1) {
        for (0..N * 64) |key| {
            keys.append(@intCast(key * key)) catch unreachable;
        }
        random.shuffle(u32, keys.items);
        for (keys.items) |key| {
            try map.put(key, key);
        }
        random.shuffle(u32, keys.items);
        for (keys.items) |key| {
            if (key < N * 48) {
                // we delete 3/4 of keys
                try expect(map.remove(key));
            } else {
                // yet we reinsert the remaining 1/4 again
                try map.put(key, key + key);
            }
        }
        random.shuffle(u32, keys.items);
        for (keys.items) |key| {
            if (key < N * 48) {
                // we expect 3/4 of keys to be deleted
                try expect(map.get(key) == null);
            } else {
                // we expect remaining 1/4 to be present
                try expect(map.get(key).? == key + key);
            }
        }
        keys.clearRetainingCapacity();
    }
}

test "eruZero: put and remove 250k keys in random order" {
    var map = eruZero(u64, u64).init(allocatorT);
    const N = 250_000;
    defer map.deinit();

    var prng = std.rand.DefaultPrng.init(0);
    const random = prng.random();

    var keys = std.ArrayList(u64).init(allocatorT);
    defer keys.deinit();

    for (0..N) |i| {
        keys.append(@intCast(i)) catch unreachable;
    }

    random.shuffle(u64, keys.items);
    for (keys.items) |key| {
        try map.put(key, key);
    }

    random.shuffle(u64, keys.items);
    while (keys.items.len > 0) {
        try expect(map.remove(keys.pop()));
        try expect(map.contains(keys.pop()));
    }
}

test "eruZero: fetchPut, fetchRemove, getEntry" {
    var map = eruZero(i32, i32).init(allocatorT);
    defer map.deinit();

    var key: i32 = -16;

    while (key < 16) : (key += 1) {
        try map.put(key, key);
    }

    key -= 1;
    while (key > -16) : (key -= 1) {
        try expect((try map.fetchPut(key, key * key)).?.value == key);
        try expect((try map.fetchPut(key, key * key * key)).?.value == key * key);
        try expect(map.fetchRemove(key).?.value == key * key * key);
        try expect(map.fetchRemove(key) == null);
        try expect(map.getEntry(key - 1).?.value == key - 1);
    }
}

test "eruZero: getPtr, fetchRemove, clearAndFree" {
    var map = eruZero([3]i32, i32).init(allocatorT);
    defer map.deinit();

    var key: [3]i32 = undefined;

    var i: i32 = 0;
    while (i < 50) : (i += 1) {
        key = .{ i, i * (-10), i * (-20) };
        try map.put(key, i * (-10));
        try expect(map.get(key) == map.getPtr(key).?.*);
    }
    i = 0;
    while (i < 50) : (i += 1) {
        key = .{ i, i * (-10), i * (-20) };
        if (map.getPtr(key)) |value|
            value.* = i * (-20);
        try expect(map.get(key) == map.getPtr(key).?.*);
    }

    map.clearAndFree();

    i = 0;
    while (i < 10) : (i += 1) {
        key = .{ i, i * (-10), i * (-20) };
        try map.put(key, i * (-30));
    }

    try expect(map.count() == 10);

    i += 1;
    while (i > 0) {
        i -= 1;
        key = .{ i, i * (-10), i * (-20) };
        if (map.fetchRemove(key)) |item| {
            try expectEqual(item.key, key);
            try expect(item.value == i * (-30));
        }
        try expect(map.get(key) == null);
    }

    try expect(map.count() == 0);
}

test "eruZero: putAssumeCapacity, ensureTotalCapacity, clearRetainingCapacity" {
    var map = eruZero(u32, u32).init(allocatorT);
    defer map.deinit();

    var j: u32 = 0;
    while (j < 8) : (j += 1) {
        try expect(map.putAssumeCapacity(j, j));
    }
    try expect(map.count() == 8);
    try expect(!map.putAssumeCapacity(9, 9)); // init size is always 8

    while (j < 16) : (j += 1) {
        try map.put(j, j);
    }
    try expect(map.count() == 16);

    var answer = true;
    while (answer) : (j += 1) {
        answer = map.putAssumeCapacity(j, j);
    }
    try expect(map.count() == j - 1);

    map.clearRetainingCapacity();

    answer = true;
    while (answer) : (j += 1) {
        answer = map.putAssumeCapacity(j, j);
    }
    try expect(map.count() == j / 2 - 1);

    map.clearAndFree(); // init size is always 8
    try expect(map.count() == 0);

    j = 0;
    while (j < 8) : (j += 1) {
        try expect(map.putAssumeCapacity(j, j));
    }
    try expect(map.count() == 8);
    try expect(!map.putAssumeCapacity(9, 9)); // init size is always 8

    try map.ensureTotalCapacity(77);

    j = 77;
    answer = true;
    while (answer) : (j += 1) {
        answer = map.putAssumeCapacity(j, j);
    }

    // Needs offsetting, because the map has rejected j,
    // but the while loop still ended up making j += 1;
    j -= 2;
    while (j >= 77) : (j -= 1) {
        try expect(map.remove(j));
        try expect(!map.contains(j));
    }
    try expect(map.count() == 8); // those 8 we have put after cleared to init

    j = 8;
    while (j > 0) {
        j -= 1;
        try expect(map.remove(j));
        try expect(map.get(j) == @as(?u32, null));
    }
    try expect(map.count() == 0);
}

test "eruZero: reduceMemoryImprint" {
    var map = eruZero(u16, void).init(allocatorT);
    defer map.deinit();

    var int: u16 = 0;
    const ceil: u16 = 1000;
    var init_capacity: u64 = 0;

    while (int < ceil) : (int += 1) {
        if (int == 8) init_capacity = map.capacity();
        try map.put(int, {});
    }
    try expect(map.count() == 1000);

    // reduce map's memory imprint in stages
    while (int > 8) {
        int -= 1;
        try expect(map.remove(int));
        if (int == 567 or int == 123 or int == 34 or int == 8)
            try map.reduceMemoryImprint();
    }

    try expect(map.capacity() == init_capacity);

    // put 1000 int(s) again
    int = ceil - 1;
    while (int > 0) : (int -= 1) {
        try map.put(int, {});
    }
    try expect(map.count() == 1000);

    while (int < ceil - 8) : (int += 1) {
        try expect(map.remove(int));
    }
    try expect(map.count() == 8);

    // Reduce map's memory imprint in one call.
    try map.reduceMemoryImprint();

    // reduceMemoryImprint() has no effect on the items count.
    // Now map's underlying memory is scaled down
    // to what it looks after the very first 8 insertions.
    try expect(map.count() == 8);
    try expect(map.capacity() == init_capacity);
}

test "eruZero: hashing strings" {
    var map = eruZero([]const u8, []const u8).init(allocatorT);
    defer map.deinit();

    const keys = [_][]const u8{ "0", "11", "222", "3333", "44444", "555555", "66666", "7777", "888", "99", "0" };

    for (keys) |key| {
        try map.put(key, key);
        try expect(map.remove(map.get(key).?) == true);
        try expect(map.get(key) == null);
    }
    try expect(map.count() == 0);

    // with pointers
    var map2 = eruZero(*const []const u8, *const []const u8).init(allocatorT);
    defer map2.deinit();

    for (&keys) |*key| {
        try map2.put(key, key);
        try expect(map2.remove(map2.get(key).?) == true);
        try expect(map2.get(key) == null);
    }
    try expect(map2.count() == 0);
}

test "eruZero: hashing slices of different length as keys" {
    var map = eruZero([]u8, u8).init(allocatorT);
    defer map.deinit();

    var prng = std.rand.DefaultPrng.init(0);
    const random = prng.random();

    var keys = std.ArrayList(u8).init(allocatorT);
    defer keys.deinit();

    for (0..255) |i| {
        keys.append(@intCast(i)) catch unreachable;
    }

    random.shuffle(u8, keys.items);

    for (0..255) |i| {
        try map.put(keys.items[0..i], @intCast(i));
    }
    try expect(map.count() == keys.items.len);
    for (0..255) |i| {
        try expect(map.fetchRemove(keys.items[0..i]).?.value == @as(u8, @intCast(i)));
    }
}

test "eruZero: hashing struct keys; clone" {
    const Vec = struct {
        x: u32,
        y: u32,
        z: u32,

        const Self = @This();

        pub fn init(x: u32, y: u32, z: u32) Self {
            return Self{
                .x = x,
                .y = y,
                .z = z,
            };
        }

        pub fn dot(self: Self, other: Self) u32 {
            return self.x * other.x + self.y * other.y + self.z * other.z;
        }
    };

    var original = eruZero(Vec, u32).init(allocatorT);
    var vec: Vec = undefined;

    var i: u16 = 0;
    while (i < 50) : (i += 1) {
        vec = Vec.init(i * 10, i * 20, i * 30);
        try original.put(vec, vec.dot(Vec.init(i * 10, i * 20, i * 30)));
    }

    var copy = try original.clone();
    defer copy.deinit();

    i = 0;
    while (i < 50) : (i += 1) {
        vec = Vec.init(i * 10, i * 20, i * 30);
        try expect(original.get(vec).? == copy.get(vec).?);
    }

    while (i < 100) : (i += 1) {
        vec = Vec.init(i * 10, i * 20, i * 30);
        try expect(original.get(vec) == copy.get(vec));
    }

    original.deinit();

    i = 0;
    while (i < 50) : (i += 1) {
        vec = Vec.init(i * 10, i * 20, i * 30);
        try expect(copy.get(vec).? == vec.dot(vec));
    }
    while (i < 100) : (i += 1) {
        vec = Vec.init(i * 10, i * 20, i * 30);
        try copy.put(vec, vec.dot(vec));
        try expect(copy.get(vec).? == vec.dot(vec));
    }
}

test "eruZero: hashing tagged union keys; iterator" {
    const Payload = union(enum) {
        signed: i32,
        boolean: bool,
    };

    var map = eruZero(Payload, i32).init(allocatorT);
    defer map.deinit();

    var i: i32 = 11;
    while (i < 256) : (i += 1) {
        const signed = Payload{ .signed = 0 - @mod(i, 11) };
        const boolean = Payload{ .boolean = (@mod(i, 2) == 0) };

        try map.put(signed, i);
        try map.put(boolean, i);
        try expect(map.contains(signed));
        try expect(map.contains(boolean));
    }

    try expect(map.count() == 13);

    const Result = struct {
        signed: u32,
        booleans: u32,
    };
    var result = Result{ .signed = 0, .booleans = 0 };

    var it = map.iterator();
    while (it.next()) |item| {
        const tag = activeTag(item.key_ptr.*);
        switch (tag) {
            .signed => result.signed += 1,
            .boolean => result.booleans += 1,
        }
    }
    try expect(it.next() == null);

    try expect(result.signed == 11);
    try expect(result.booleans == 2);

    i = 11;
    while (i > 0) : (i -= 1) {
        const signed = Payload{ .signed = 0 - @mod(i, 11) };
        const boolean = Payload{ .boolean = (@mod(i, 2) == 0) };

        if (map.remove(boolean)) {
            try expect(i > 9);
        } else try expect(i <= 9);

        try expect(!map.remove(boolean));
        try expect(map.remove(signed));
        try expect(!map.remove(signed));
    }

    try expect(map.count() == 0);
}

test "eruZero: vanishing vectors" {
    var map = eruZero(@Vector(4, u8), @Vector(4, u8)).init(allocatorT);
    defer map.deinit();

    var i: u8 = 0;

    while (i < 100) : (i += 1) {
        const key = @Vector(4, u8){ i % 5, (i + 1) % 5, (i + 2) % 5, (i + 3) % 5 };
        try map.put(key, key);
        const key2 = map.get(key).? + key;
        try map.put(key2, key);
        try expect(map.remove(map.fetchRemove(key2).?.value));
    }
    try expect(map.count() == 0);
}

test "eruZero: no-way floats" {
    const Key = struct {
        int: u64,
        rem: u64,
        const precision: u64 = 10000;

        pub fn init(key: f64) @This() {
            return @This(){ .int = @intFromFloat(key), .rem = @intFromFloat(precision * @mod(key, 1)) };
        }
    };
    var map = eruZero(Key, void).init(allocatorT);
    defer map.deinit();

    try map.put(Key.init(0.11112222), {});
    try map.put(Key.init(0.22223333), {});
    try map.put(Key.init(0.33334444), {});
    try map.put(Key.init(0.44445555), {});
    try map.put(Key.init(0.55556666), {});
    try map.put(Key.init(0.66667777), {});
    try map.put(Key.init(0.77778888), {});
    try map.put(Key.init(0.88889999), {});
    try map.put(Key.init(0.99990000), {});

    try expect(map.remove(Key.init(0.88882222)));
    try expect(map.remove(Key.init(0.22223333)));
    try expect(map.remove(Key.init(0.77774444)));
    try expect(map.remove(Key.init(0.33335555)));
    try expect(map.remove(Key.init(0.66666666)));
    try expect(map.remove(Key.init(0.44447777)));
    try expect(map.remove(Key.init(0.55558888)));
    try expect(map.remove(Key.init(0.99999999)));
    try expect(map.remove(Key.init(0.11110000)));

    try expect(map.count() == 0);
}

test "eruZero: unio, intersection, symmetricDifference, relativeComplement" {
    var A = eruZero(u8, void).init(allocatorT);
    defer A.deinit();
    var B = eruZero(u8, void).init(allocatorT);
    defer B.deinit();

    const NOT_HEX = "0123456789ABCDEFGHIJ";

    for (0..12) |idx| {
        try A.put(NOT_HEX[idx], {}); // "0123456789AB"
    }

    for (4..20) |idx| {
        try B.put(NOT_HEX[idx], {}); // "456789ABCDEFGHIJ"
    }

    // Unio //
    var U = try A.unio(&B); // "0123456789ABCDEFGHIJ"
    defer U.deinit();

    for (NOT_HEX) |char| {
        try expect(U.contains(char));
    }

    // Intersection //
    var I = try A.intersection(&B); // "456789AB"
    defer I.deinit();

    for (NOT_HEX, 0..) |char, idx| {
        if (idx >= 4 and idx < 12) {
            try expect(I.contains(char));
        } else try expect(!I.contains(char));
    }

    // Symmetric Difference //
    var SD = try A.symmetricDifference(&B); // "0123CDEFGHIJ"
    defer SD.deinit();

    for (NOT_HEX, 0..) |char, idx| {
        if (idx < 4 or idx >= 12) {
            try expect(SD.contains(char));
        } else try expect(!SD.contains(char));
    }

    // RelativeComplement //
    var RC = try A.relativeComplement(&B); // "0123"
    defer RC.deinit();

    for (NOT_HEX, 0..) |char, idx| {
        if (idx < 4) {
            try expect(RC.contains(char));
        } else try expect(!RC.contains(char));
    }
}
