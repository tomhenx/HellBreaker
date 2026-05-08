"""
Assembles PixelLab character frames into Godot-compatible sprite sheets.
Layout: 8 rows (directions) x N columns (frames), 68x68px per cell.
Direction row order matches CharacterVisual.DIR_ROW:
  0=south  1=south-west  2=west  3=north-west
  4=north  5=north-east  6=east  7=south-east
"""
from PIL import Image
import os

BASE = r"P:\HellBreaker\assets\sprites\characters\player"
FRAME_W = 68
FRAME_H = 68

DIRECTIONS = [
    "south", "south-west", "west", "north-west",
    "north", "north-east", "east", "south-east",
]

def frames(folder, direction, count):
    return [
        os.path.join(BASE, "animations", folder, direction, f"frame_{i:03d}.png")
        for i in range(count)
    ]

ANIMATIONS = {
    "walk": {
        "south":      frames("animating-7066e697", "south",      8),
        "south-west": frames("animating-7066e697", "south-west", 8),
        "west":       frames("animating-7066e697", "west",       8),
        "north-west": frames("animating-7066e697", "north-west", 8),
        "north":      frames("animating-7066e697", "north",      8),
        "north-east": frames("animating-7066e697", "north-east", 8),
        "east":       frames("animating-7066e697", "east",       8),
        "south-east": frames("animating-63930f77", "south-east", 8),
    },
    "idle": {
        "south":      frames("animating-c405e813", "south",      4),
        "south-west": frames("animating-c405e813", "south-west", 4),
        "west":       frames("animating-c405e813", "west",       4),
        "north-west": frames("animating-c4da5fd5", "north-west", 4),
        "north":      frames("animating-c405e813", "north",      4),
        "north-east": frames("animating-c405e813", "north-east", 4),
        "east":       frames("animating-c405e813", "east",       4),
        "south-east": frames("animating-c405e813", "south-east", 4),
    },
    "dodge": {
        "south":      frames("animating-8516522a", "south",      6),
        "south-west": frames("animating-8516522a", "south-west", 6),
        "west":       frames("animating-8516522a", "west",       6),
        "north-west": frames("animating-8516522a", "north-west", 6),
        "north":      frames("animating-8516522a", "north",      6),
        "north-east": frames("animating-8516522a", "north-east", 6),
        "east":       frames("animating-8516522a", "east",       6),
        "south-east": frames("animating-8516522a", "south-east", 6),
    },
}

for anim_name, dir_frames in ANIMATIONS.items():
    n_frames = len(next(iter(dir_frames.values())))
    sheet = Image.new("RGBA", (FRAME_W * n_frames, FRAME_H * len(DIRECTIONS)), (0, 0, 0, 0))

    for row, direction in enumerate(DIRECTIONS):
        for col, path in enumerate(dir_frames[direction]):
            if os.path.exists(path):
                sheet.paste(Image.open(path).convert("RGBA"), (col * FRAME_W, row * FRAME_H))
            else:
                print(f"  WARNING: missing {path}")

    out = os.path.join(BASE, f"{anim_name}.png")
    sheet.save(out)
    print(f"  {anim_name}.png  ({FRAME_W * n_frames} x {FRAME_H * len(DIRECTIONS)})")

print("Done.")
