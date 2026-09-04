# Ordered Pivot Treemap

This document specifies how to implement the ordered pivot treemap layout used
by the treemap study.

The algorithm has two independent inputs for every item:

- Its position in the input list.
- Its positive area or weight.

The input list must never be sorted by area. The ordering determines which
items can be grouped together, while the area determines rectangle sizes and
which item is selected as the pivot.

## Input and Output

The layout function receives:

- An ordered list of items. Every item has a positive `size`.
- A containing rectangle `R = (x, y, width, height)`.

It returns one rectangle for every item. The rectangle area must be
proportional to the item's size:

$$
\frac{\operatorname{area}(R_i)}{\operatorname{area}(R)}
=
\frac{s_i}{\sum_j s_j}.
$$

The returned rectangles must cover `R` without gaps or overlaps, except for
minor floating-point error. Visual padding is applied only while drawing and
must not be part of the layout calculation.

## Partitioning an Ordered List

For each recursive call, find the item with the largest size. This item is the
pivot `P`. If multiple items have the same largest size, choose the first one.

Given the ordered list

$$
[A, B, C, D, E, F, G]
$$

with sizes

$$
[10, 8, 12, 30, 7, 9, 6],
$$

the pivot is `D`. Partition the list as follows:

$$
[\underbrace{A,B,C}_{L_1},\;\underbrace{D}_{P},\;
\underbrace{E}_{L_2},\;\underbrace{F,G}_{L_3}].
$$

`L1` is fixed. It contains every item before `P` in the original ordering.
It does not contain every item smaller than `P`.

The items after `P` are divided into contiguous groups `L2` and `L3`. Their
ordering must be preserved. If there are `m` items after `P`, let `k` be the
number placed in `L2`:

```text
L2 = following[0:k]
L3 = following[k:m]
```

`L3` may be empty but must not contain exactly one item. When following items
exist, `L2` is not empty. Therefore the valid values of `k` are:

```text
m = 0: k = 0
m = 1: k = 1
m = 2: k = 2
m >= 3: k = 1, 2, ..., m - 2, m
```

For example, with three following items `[E, F, G]`, the valid splits are:

```text
L2 = [E]       L3 = [F, G]
L2 = [E, F, G] L3 = []
```

The split `L2 = [E, F]`, `L3 = [G]` is invalid because `L3` would contain
exactly one item. A split such as `L2 = [F]`, `L3 = [E, G]` is invalid because
it changes the input ordering.

## Rectangle Geometry

Define the group sizes:

$$
a = \sum_{i \in L_1}s_i,\qquad
p = s_P,\qquad
b = \sum_{i \in L_2}s_i,\qquad
c = \sum_{i \in L_3}s_i,
$$

and

$$
T = a + p + b + c.
$$

### Wide Container

When `width >= height`, place `L1` and `L3` in full-height side columns. Place
the pivot above `L2` in the middle column:

```text
+--------+----------+--------+
|        |    P     |        |
|   L1   +----------+   L3   |
|        |    L2    |        |
+--------+----------+--------+
```

Calculate:

$$
w_1 = width\frac{a}{T},\qquad
w_m = width\frac{p+b}{T},\qquad
w_3 = width-w_1-w_m,
$$

and

$$
h_P = height\frac{p}{p+b},\qquad
h_2 = height-h_P.
$$

The child rectangles are:

```text
R1 = (x,           y,      w1, height)
RP = (x + w1,      y,      wm, hP)
R2 = (x + w1,      y + hP, wm, h2)
R3 = (x + w1 + wm, y,      w3, height)
```

### Tall Container

When `height > width`, transpose the wide arrangement. Place `L1` and `L3` in
full-width rows. Place the pivot to the left of `L2` in the middle row:

```text
+------------------+
|        L1        |
+---------+--------+
|    P    |   L2   |
+---------+--------+
|        L3        |
+------------------+
```

Calculate:

$$
h_1 = height\frac{a}{T},\qquad
h_m = height\frac{p+b}{T},\qquad
h_3 = height-h_1-h_m,
$$

and

$$
w_P = width\frac{p}{p+b},\qquad
w_2 = width-w_P.
$$

The child rectangles are:

```text
R1 = (x,      y,           width, h1)
RP = (x,      y + h1,      wP,    hm)
R2 = (x + wP, y + h1,      w2,    hm)
R3 = (x,      y + h1 + hm, width, h3)
```

Subtract previously calculated dimensions from the containing width or height
when calculating the last dimension. This avoids visible gaps caused by
floating-point rounding.

## Choosing the Best Split

Construct `RP` for every valid split between `L2` and `L3`. Score the pivot
rectangle with the symmetric aspect ratio:

$$
q(R_P) = \max\left(
\frac{width(R_P)}{height(R_P)},
\frac{height(R_P)}{width(R_P)}
\right).
$$

The score is always at least `1`. A square has score `1`. Choose the split with
the lowest score. If two candidates have equal scores, keep the first candidate
to make the result deterministic.

Only the pivot rectangle's aspect ratio is used to choose the split. Do not
optimize the average aspect ratio of all four regions.

## Recursion and Base Cases

After selecting the split and calculating `R1`, `RP`, `R2`, and `R3`:

1. Assign `RP` directly to `P`.
2. Recursively lay out `L1` inside `R1`.
3. Recursively lay out `L2` inside `R2`.
4. Recursively lay out `L3` inside `R3`.

Empty groups are skipped.

For one item, assign the complete containing rectangle to that item.

For two items, split the containing rectangle along its longer dimension in
the original item order. The split position is proportional to the two sizes.
This avoids unnecessary pivot processing and prevents poor two-item layouts.

## Pseudocode

```text
layout(items, R):
    remove items whose size is not positive

    if items is empty:
        return

    if items contains one item:
        assign R to that item
        return

    if items contains two items:
        split R along its longer dimension in input order
        return

    pivot_index = index of first item with the maximum size
    P = items[pivot_index]
    L1 = items before pivot_index
    following = items after pivot_index

    best = none

    for each valid split position k:
        L2 = following[0:k]
        L3 = following[k:end]

        calculate R1, RP, R2, and R3
        score = max(RP.width / RP.height,
                    RP.height / RP.width)

        if best is none or score < best.score:
            best = this split and its rectangles

    assign best.RP to P
    layout(L1, best.R1)
    layout(best.L2, best.R2)
    layout(best.L3, best.R3)
```

## Implementation Requirements

- Never sort the input list by size.
- Preserve relative ordering when constructing `L1`, `L2`, and `L3`.
- Choose the first largest item when sizes tie.
- Never allow `L3` to contain exactly one item.
- Use a symmetric aspect-ratio score.
- Use floating-point rectangle coordinates during layout.
- Keep visual margins and borders separate from layout geometry.
- Verify that each output area is proportional to its input size.
- Verify that all output rectangles together cover the containing rectangle.
- Handle wide and tall containing rectangles using transposed geometry.
- Skip empty recursive groups and non-positive input items.
