"""Turns the raw screenshots (tests/tools/capture_shots.gd) into the website's images.

    python website/tools/make_images.py <folder of raw PNGs>

Landscape scenes become 1600 px and 800 px wide JPEGs; phone screens 720 px
and 360 px wide. Everything lands in website/assets/img/.
"""
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "assets" / "img"
SCENES = {"box", "settlement", "village", "people", "dusk", "winter", "storm"}


def save(image: Image.Image, width: int, path: Path) -> None:
    height = round(image.height * width / image.width)
    image.resize((width, height), Image.LANCZOS).convert("RGB").save(path, "JPEG", quality=84, optimize=True, progressive=True)
    print(f"{path.name}: {width}x{height}, {path.stat().st_size // 1024} KB")


def main() -> None:
    source = Path(sys.argv[1] if len(sys.argv) > 1 else "C:/tmp/wiab_shots/img")
    OUT.mkdir(parents=True, exist_ok=True)
    for png in sorted(source.glob("*.png")):
        image = Image.open(png)
        name = png.stem
        if name in SCENES:
            save(image, 1600, OUT / f"{name}.jpg")
            save(image, 800, OUT / f"{name}-sm.jpg")
        elif name.startswith("phone_"):
            save(image, 720, OUT / f"{name}.jpg")
            save(image, 360, OUT / f"{name}-sm.jpg")


if __name__ == "__main__":
    main()
