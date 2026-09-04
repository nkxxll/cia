import pyray as rl


files = [
    {"size": 11752, "name": "../treemapstudy"},
    {"size": 476384, "name": "../.zig-cache"},
    {"size": 56, "name": "../docs"},
    {"size": 8016, "name": "../zig-out"},
    {"size": 776, "name": "../.jj"},
    {"size": 1024, "name": "../.git"},
    {"size": 72, "name": "../src"},
    {"size": 498128, "name": ".."},
]

COLORS = [
    rl.Color(55, 126, 184, 255),
    rl.Color(77, 175, 74, 255),
    rl.Color(255, 127, 0, 255),
    rl.Color(152, 78, 163, 255),
    rl.Color(228, 26, 28, 255),
    rl.Color(166, 86, 40, 255),
    rl.Color(247, 129, 191, 255),
]


def format_size(size):
    value = float(size)
    for unit in ("B", "KiB", "MiB", "GiB"):
        if value < 1024 or unit == "GiB":
            return f"{value:.0f} {unit}" if unit == "B" else f"{value:.1f} {unit}"
        value /= 1024


def split_regions(bounds, first_size, pivot_size, second_size, third_size):
    total = first_size + pivot_size + second_size + third_size

    if bounds.width >= bounds.height:
        # L1 and L3 are side columns; P sits above L2 in the middle column.
        first_width = bounds.width * first_size / total
        middle_width = bounds.width * (pivot_size + second_size) / total
        pivot_height = bounds.height * pivot_size / (pivot_size + second_size)

        first = rl.Rectangle(bounds.x, bounds.y, first_width, bounds.height)
        pivot = rl.Rectangle(
            bounds.x + first_width,
            bounds.y,
            middle_width,
            pivot_height,
        )
        second = rl.Rectangle(
            bounds.x + first_width,
            bounds.y + pivot_height,
            middle_width,
            bounds.height - pivot_height,
        )
        third = rl.Rectangle(
            bounds.x + first_width + middle_width,
            bounds.y,
            bounds.width - first_width - middle_width,
            bounds.height,
        )
    else:
        # Transpose the same arrangement when the available area is tall.
        first_height = bounds.height * first_size / total
        middle_height = bounds.height * (pivot_size + second_size) / total
        pivot_width = bounds.width * pivot_size / (pivot_size + second_size)

        first = rl.Rectangle(bounds.x, bounds.y, bounds.width, first_height)
        pivot = rl.Rectangle(
            bounds.x,
            bounds.y + first_height,
            pivot_width,
            middle_height,
        )
        second = rl.Rectangle(
            bounds.x + pivot_width,
            bounds.y + first_height,
            bounds.width - pivot_width,
            middle_height,
        )
        third = rl.Rectangle(
            bounds.x,
            bounds.y + first_height + middle_height,
            bounds.width,
            bounds.height - first_height - middle_height,
        )

    return first, pivot, second, third


def split_two(entries, bounds):
    first_ratio = entries[0]["size"] / sum(entry["size"] for entry in entries)
    if bounds.width >= bounds.height:
        first_width = bounds.width * first_ratio
        return [
            (entries[0], rl.Rectangle(bounds.x, bounds.y, first_width, bounds.height)),
            (
                entries[1],
                rl.Rectangle(
                    bounds.x + first_width,
                    bounds.y,
                    bounds.width - first_width,
                    bounds.height,
                ),
            ),
        ]

    first_height = bounds.height * first_ratio
    return [
        (entries[0], rl.Rectangle(bounds.x, bounds.y, bounds.width, first_height)),
        (
            entries[1],
            rl.Rectangle(
                bounds.x,
                bounds.y + first_height,
                bounds.width,
                bounds.height - first_height,
            ),
        ),
    ]


def valid_splits(count):
    if count <= 2:
        return [count]
    # Omitting count - 1 prevents L3 from containing exactly one item.
    return [*range(1, count - 1), count]


def layout_treemap(entries, bounds):
    entries = [entry for entry in entries if entry["size"] > 0]
    rectangles = []

    def partition(group, area):
        if not group:
            return
        if len(group) == 1:
            rectangles.append((group[0], area))
            return
        if len(group) == 2:
            rectangles.extend(split_two(group, area))
            return

        pivot_index = max(range(len(group)), key=lambda index: group[index]["size"])
        pivot = group[pivot_index]
        first_group = group[:pivot_index]
        following = group[pivot_index + 1 :]
        first_size = sum(entry["size"] for entry in first_group)

        best = None
        for split_at in valid_splits(len(following)):
            second_group = following[:split_at]
            third_group = following[split_at:]
            second_size = sum(entry["size"] for entry in second_group)
            third_size = sum(entry["size"] for entry in third_group)
            regions = split_regions(
                area,
                first_size,
                pivot["size"],
                second_size,
                third_size,
            )
            pivot_region = regions[1]
            aspect_ratio = max(
                pivot_region.width / pivot_region.height,
                pivot_region.height / pivot_region.width,
            )
            if best is None or aspect_ratio < best[0]:
                best = (aspect_ratio, second_group, third_group, regions)

        _, second_group, third_group, regions = best
        first_region, pivot_region, second_region, third_region = regions
        rectangles.append((pivot, pivot_region))
        partition(first_group, first_region)
        partition(second_group, second_region)
        partition(third_group, third_region)

    partition(entries, bounds)
    return rectangles


def fit_text(text, font_size, max_width):
    if rl.measure_text(text, font_size) <= max_width:
        return text

    while text and rl.measure_text(f"{text}...", font_size) > max_width:
        text = text[:-1]
    return f"{text}..." if text else ""


def draw_treemap(entries, bounds):
    mouse = rl.get_mouse_position()
    hovered = None

    for index, (entry, rectangle) in enumerate(layout_treemap(entries, bounds)):
        tile = rl.Rectangle(
            rectangle.x + 2,
            rectangle.y + 2,
            max(0, rectangle.width - 4),
            max(0, rectangle.height - 4),
        )
        rl.draw_rectangle_rec(tile, COLORS[index % len(COLORS)])

        if rl.check_collision_point_rec(mouse, tile):
            hovered = (entry, tile)
            rl.draw_rectangle_lines_ex(tile, 3, rl.WHITE)

        if tile.width >= 70 and tile.height >= 35:
            label = fit_text(entry["name"], 18, tile.width - 16)
            rl.draw_text(label, int(tile.x + 8), int(tile.y + 7), 18, rl.WHITE)
            if tile.height >= 58:
                rl.draw_text(
                    format_size(entry["size"]),
                    int(tile.x + 8),
                    int(tile.y + 30),
                    16,
                    rl.Color(235, 240, 245, 255),
                )

    if hovered:
        entry, _ = hovered
        text = f"{entry['name']}  {format_size(entry['size'])}"
        width = rl.measure_text(text, 18) + 20
        x = min(int(mouse.x + 14), rl.get_screen_width() - width - 8)
        y = min(int(mouse.y + 14), rl.get_screen_height() - 38)
        rl.draw_rectangle(x, y, width, 30, rl.Color(20, 24, 31, 240))
        rl.draw_text(text, x + 10, y + 6, 18, rl.WHITE)


def main():
    root = files[-1]
    entries = files[:-1]

    rl.set_config_flags(rl.FLAG_WINDOW_RESIZABLE)
    rl.init_window(1280, 720, "Treemap Study")
    rl.set_window_min_size(480, 320)
    rl.set_target_fps(60)

    try:
        while not rl.window_should_close():
            width = rl.get_screen_width()
            height = rl.get_screen_height()
            bounds = rl.Rectangle(20, 84, width - 40, height - 104)

            rl.begin_drawing()
            rl.clear_background(rl.Color(24, 29, 38, 255))
            rl.draw_text(str(root["name"]), 20, 18, 30, rl.RAYWHITE)
            summary = f"{len(entries)} entries  |  {format_size(root['size'])}"
            rl.draw_text(summary, 20, 54, 17, rl.GRAY)
            draw_treemap(entries, bounds)
            rl.end_drawing()
    finally:
        rl.close_window()


if __name__ == "__main__":
    main()
