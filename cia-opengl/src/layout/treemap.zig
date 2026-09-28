const std = @import("std");

pub const Rect = struct {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
};

pub const Tile = struct {
    entry_index: usize,
    rect: Rect,
};

const Item = struct {
    entry_index: usize,
    weight: f64,
};

const Regions = struct {
    first: Rect,
    pivot: Rect,
    second: Rect,
    third: Rect,
};

/// Lays out ordered numeric weights or ordered records with a numeric
/// `weight` or `size` field. The caller owns the returned slice.
pub fn layout(allocator: std.mem.Allocator, entries: anytype, bounds: Rect) ![]Tile {
    var items: std.ArrayList(Item) = .empty;
    defer items.deinit(allocator);

    for (entries, 0..) |entry, index| {
        const weight = entryWeight(entry);
        if (weight > 0) {
            try items.append(allocator, .{ .entry_index = index, .weight = weight });
        }
    }

    var tiles: std.ArrayList(Tile) = .empty;
    errdefer tiles.deinit(allocator);
    try partition(allocator, &tiles, items.items, bounds);
    return tiles.toOwnedSlice(allocator);
}

fn entryWeight(entry: anytype) f64 {
    const T = @TypeOf(entry);
    return switch (@typeInfo(T)) {
        .int, .comptime_int => @floatFromInt(entry),
        .float, .comptime_float => @floatCast(entry),
        .@"struct" => if (@hasField(T, "weight"))
            numberToFloat(@field(entry, "weight"))
        else if (@hasField(T, "size"))
            numberToFloat(@field(entry, "size"))
        else
            @compileError("treemap entries must have a numeric weight or size field"),
        else => @compileError("treemap layout expects numeric weights or weighted entries"),
    };
}

fn numberToFloat(value: anytype) f64 {
    return switch (@typeInfo(@TypeOf(value))) {
        .int, .comptime_int => @floatFromInt(value),
        .float, .comptime_float => @floatCast(value),
        else => @compileError("treemap weights must be numeric"),
    };
}

fn partition(allocator: std.mem.Allocator, tiles: *std.ArrayList(Tile), items: []const Item, bounds: Rect) !void {
    switch (items.len) {
        0 => return,
        1 => {
            try tiles.append(allocator, .{ .entry_index = items[0].entry_index, .rect = bounds });
            return;
        },
        2 => {
            try splitTwo(allocator, tiles, items, bounds);
            return;
        },
        else => {},
    }

    var pivot_index: usize = 0;
    for (items[1..], 1..) |item, index| {
        if (item.weight > items[pivot_index].weight) pivot_index = index;
    }

    const first = items[0..pivot_index];
    const following = items[pivot_index + 1 ..];
    const first_weight = totalWeight(first);
    const pivot_weight = items[pivot_index].weight;

    var best_split: usize = undefined;
    var best_regions: Regions = undefined;
    var best_score: ?f64 = null;

    var split_at: usize = if (following.len <= 2) following.len else 1;
    while (true) {
        const second_weight = totalWeight(following[0..split_at]);
        const third_weight = totalWeight(following[split_at..]);
        const regions = splitRegions(bounds, first_weight, pivot_weight, second_weight, third_weight);
        const score = aspectRatio(regions.pivot);

        if (best_score == null or score < best_score.?) {
            best_score = score;
            best_split = split_at;
            best_regions = regions;
        }

        if (following.len <= 2 or split_at == following.len) break;
        split_at += 1;
        if (split_at == following.len - 1) split_at = following.len;
    }

    try tiles.append(allocator, .{ .entry_index = items[pivot_index].entry_index, .rect = best_regions.pivot });
    try partition(allocator, tiles, first, best_regions.first);
    try partition(allocator, tiles, following[0..best_split], best_regions.second);
    try partition(allocator, tiles, following[best_split..], best_regions.third);
}

fn splitTwo(allocator: std.mem.Allocator, tiles: *std.ArrayList(Tile), items: []const Item, bounds: Rect) !void {
    const first_ratio = items[0].weight / (items[0].weight + items[1].weight);

    if (bounds.width >= bounds.height) {
        const first_width = bounds.width * first_ratio;
        try tiles.append(allocator, .{
            .entry_index = items[0].entry_index,
            .rect = .{ .x = bounds.x, .y = bounds.y, .width = first_width, .height = bounds.height },
        });
        try tiles.append(allocator, .{
            .entry_index = items[1].entry_index,
            .rect = .{ .x = bounds.x + first_width, .y = bounds.y, .width = bounds.width - first_width, .height = bounds.height },
        });
    } else {
        const first_height = bounds.height * first_ratio;
        try tiles.append(allocator, .{
            .entry_index = items[0].entry_index,
            .rect = .{ .x = bounds.x, .y = bounds.y, .width = bounds.width, .height = first_height },
        });
        try tiles.append(allocator, .{
            .entry_index = items[1].entry_index,
            .rect = .{ .x = bounds.x, .y = bounds.y + first_height, .width = bounds.width, .height = bounds.height - first_height },
        });
    }
}

fn splitRegions(bounds: Rect, first_weight: f64, pivot_weight: f64, second_weight: f64, third_weight: f64) Regions {
    const total = first_weight + pivot_weight + second_weight + third_weight;

    if (bounds.width >= bounds.height) {
        const first_width = bounds.width * first_weight / total;
        const middle_width = bounds.width * (pivot_weight + second_weight) / total;
        const pivot_height = bounds.height * pivot_weight / (pivot_weight + second_weight);
        return .{
            .first = .{ .x = bounds.x, .y = bounds.y, .width = first_width, .height = bounds.height },
            .pivot = .{ .x = bounds.x + first_width, .y = bounds.y, .width = middle_width, .height = pivot_height },
            .second = .{ .x = bounds.x + first_width, .y = bounds.y + pivot_height, .width = middle_width, .height = bounds.height - pivot_height },
            .third = .{ .x = bounds.x + first_width + middle_width, .y = bounds.y, .width = bounds.width - first_width - middle_width, .height = bounds.height },
        };
    }

    const first_height = bounds.height * first_weight / total;
    const middle_height = bounds.height * (pivot_weight + second_weight) / total;
    const pivot_width = bounds.width * pivot_weight / (pivot_weight + second_weight);
    return .{
        .first = .{ .x = bounds.x, .y = bounds.y, .width = bounds.width, .height = first_height },
        .pivot = .{ .x = bounds.x, .y = bounds.y + first_height, .width = pivot_width, .height = middle_height },
        .second = .{ .x = bounds.x + pivot_width, .y = bounds.y + first_height, .width = bounds.width - pivot_width, .height = middle_height },
        .third = .{ .x = bounds.x, .y = bounds.y + first_height + middle_height, .width = bounds.width, .height = bounds.height - first_height - middle_height },
    };
}

fn totalWeight(items: []const Item) f64 {
    var total: f64 = 0;
    for (items) |item| total += item.weight;
    return total;
}

fn aspectRatio(rect: Rect) f64 {
    if (rect.width <= 0 or rect.height <= 0) return std.math.inf(f64);
    return @max(rect.width / rect.height, rect.height / rect.width);
}

fn expectApprox(expected: f64, actual: f64) !void {
    try std.testing.expectApproxEqAbs(expected, actual, 1e-9);
}

fn findTile(tiles: []const Tile, entry_index: usize) *const Tile {
    for (tiles) |*tile| {
        if (tile.entry_index == entry_index) return tile;
    }
    unreachable;
}

test "empty and non-positive weights produce no tiles" {
    const bounds = Rect{ .x = 5, .y = 7, .width = 100, .height = 60 };
    const empty = try layout(std.testing.allocator, &[_]f64{}, bounds);
    defer std.testing.allocator.free(empty);
    try std.testing.expectEqual(0, empty.len);

    const zero = try layout(std.testing.allocator, &[_]f64{ 0, -2, 0 }, bounds);
    defer std.testing.allocator.free(zero);
    try std.testing.expectEqual(0, zero.len);
}

test "one item fills bounds and zero weights retain original identity" {
    const bounds = Rect{ .x = 5, .y = 7, .width = 100, .height = 60 };
    const tiles = try layout(std.testing.allocator, &[_]f64{ 0, 4, 0 }, bounds);
    defer std.testing.allocator.free(tiles);
    try std.testing.expectEqual(1, tiles.len);
    try std.testing.expectEqual(1, tiles[0].entry_index);
    try std.testing.expectEqual(bounds, tiles[0].rect);
}

test "two items split in input order along the longer dimension" {
    const wide = try layout(std.testing.allocator, &[_]f64{ 1, 3 }, .{ .x = 2, .y = 4, .width = 80, .height = 20 });
    defer std.testing.allocator.free(wide);
    try std.testing.expectEqual(0, wide[0].entry_index);
    try expectApprox(20, wide[0].rect.width);
    try expectApprox(22, wide[1].rect.x);
    try expectApprox(60, wide[1].rect.width);

    const tall = try layout(std.testing.allocator, &[_]f64{ 1, 3 }, .{ .x = 2, .y = 4, .width = 20, .height = 80 });
    defer std.testing.allocator.free(tall);
    try expectApprox(20, tall[0].rect.height);
    try expectApprox(24, tall[1].rect.y);
    try expectApprox(60, tall[1].rect.height);
}

test "wide and tall pivot layouts are transposes" {
    const weights = [_]f64{ 6, 3, 1 };
    const wide = try layout(std.testing.allocator, &weights, .{ .x = 0, .y = 0, .width = 120, .height = 60 });
    defer std.testing.allocator.free(wide);
    try std.testing.expectEqual(0, wide[0].entry_index);
    try expectApprox(120, wide[0].rect.width);
    try expectApprox(36, wide[0].rect.height);
    try expectApprox(90, findTile(wide, 1).rect.width);
    try expectApprox(30, findTile(wide, 2).rect.width);

    const tall = try layout(std.testing.allocator, &weights, .{ .x = 0, .y = 0, .width = 60, .height = 120 });
    defer std.testing.allocator.free(tall);
    try expectApprox(36, tall[0].rect.width);
    try expectApprox(120, tall[0].rect.height);
    try expectApprox(90, findTile(tall, 1).rect.height);
    try expectApprox(30, findTile(tall, 2).rect.height);
}

test "entries preserve ordered identity and first maximum is pivot" {
    const Entry = struct { name: []const u8, size: u64 };
    const entries = [_]Entry{
        .{ .name = "a", .size = 9 },
        .{ .name = "ignored", .size = 0 },
        .{ .name = "b", .size = 9 },
        .{ .name = "c", .size = 1 },
    };
    const tiles = try layout(std.testing.allocator, &entries, .{ .x = 0, .y = 0, .width = 100, .height = 50 });
    defer std.testing.allocator.free(tiles);
    try std.testing.expectEqual(3, tiles.len);
    try std.testing.expectEqual(0, tiles[0].entry_index);
    try std.testing.expect(findTile(tiles, 2).entry_index == 2);
    try std.testing.expect(findTile(tiles, 3).entry_index == 3);
}

test "split candidates never leave a one-item third group" {
    // For these weights, the forbidden split after the second following item
    // would make the pivot square. The best valid split takes all three.
    const tiles = try layout(std.testing.allocator, &[_]f64{ 6, 5, 10, 1, 9, 9 }, .{
        .x = 0,
        .y = 0,
        .width = 100,
        .height = 100,
    });
    defer std.testing.allocator.free(tiles);

    try std.testing.expectEqual(2, tiles[0].entry_index);
    try expectApprox(27.5, tiles[0].rect.x);
    try expectApprox(72.5, tiles[0].rect.width);
    try expectApprox(1000.0 / 29.0, tiles[0].rect.height);
}

test "tiles are proportional, contained, disjoint, and cover bounds" {
    const weights = [_]f64{ 10, 8, 12, 30, 7, 9, 6 };
    const bounds = Rect{ .x = 13, .y = 17, .width = 311, .height = 173 };
    const tiles = try layout(std.testing.allocator, &weights, bounds);
    defer std.testing.allocator.free(tiles);
    try std.testing.expectEqual(weights.len, tiles.len);

    const total_weight: f64 = 82;
    const total_area = bounds.width * bounds.height;
    var covered: f64 = 0;
    for (tiles, 0..) |tile, i| {
        try std.testing.expect(tile.rect.x >= bounds.x - 1e-9);
        try std.testing.expect(tile.rect.y >= bounds.y - 1e-9);
        try std.testing.expect(tile.rect.x + tile.rect.width <= bounds.x + bounds.width + 1e-9);
        try std.testing.expect(tile.rect.y + tile.rect.height <= bounds.y + bounds.height + 1e-9);

        const area = tile.rect.width * tile.rect.height;
        covered += area;
        try std.testing.expectApproxEqAbs(total_area * weights[tile.entry_index] / total_weight, area, 1e-8);
        for (tiles[i + 1 ..]) |other| {
            const overlap_width = @max(0, @min(tile.rect.x + tile.rect.width, other.rect.x + other.rect.width) - @max(tile.rect.x, other.rect.x));
            const overlap_height = @max(0, @min(tile.rect.y + tile.rect.height, other.rect.y + other.rect.height) - @max(tile.rect.y, other.rect.y));
            try std.testing.expectApproxEqAbs(0, overlap_width * overlap_height, 1e-9);
        }
    }
    try std.testing.expectApproxEqAbs(total_area, covered, 1e-8);
}

test "zero bounds return finite zero-area rectangles" {
    const tiles = try layout(std.testing.allocator, &[_]f64{ 5, 3, 2, 1 }, .{ .x = 4, .y = 6, .width = 0, .height = 0 });
    defer std.testing.allocator.free(tiles);
    try std.testing.expectEqual(4, tiles.len);
    for (tiles) |tile| {
        try std.testing.expect(std.math.isFinite(tile.rect.x));
        try std.testing.expect(std.math.isFinite(tile.rect.y));
        try std.testing.expectEqual(0, tile.rect.width);
        try std.testing.expectEqual(0, tile.rect.height);
    }
}
