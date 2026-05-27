"""为 macOS / Windows 应用图标添加圆角 mask。

源图：macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_source.png
（独立的「未圆角」原图，不会被脚本覆盖。如不存在则回退到 app_icon_1024.png）

派生：
  - macOS 7 个尺寸（16/32/64/128/256/512/1024）覆盖 app_icon_<size>.png
  - Windows ICO 多尺寸（16/24/32/48/64/128/256）覆盖 app_icon.ico

圆角半径采用图标尺寸的 22.5%，接近 macOS Big Sur squircle 比例。
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ICON_DIR = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
SRC = ICON_DIR / "app_icon_source.png"
SRC_FALLBACK = ICON_DIR / "app_icon_1024.png"

MAC_SIZES = [16, 32, 64, 128, 256, 512, 1024]
WIN_SIZES = [16, 24, 32, 48, 64, 128, 256]
RADIUS_RATIO = 0.225  # macOS Big Sur squircle 近似（圆角矩形）


def round_corners(img: Image.Image, radius_ratio: float = RADIUS_RATIO) -> Image.Image:
    """给图像加圆角 alpha mask。输入 RGBA，输出 RGBA。

    关键：new_alpha = original_alpha × (mask / 255)，保留原图透明区仍透明 ——
    避免「透明黑（RGB=0,A=0）」被强制 A=255 显化成实黑色边框（旧实现的 bug）。
    """
    img = img.convert("RGBA")
    w, h = img.size
    radius = int(min(w, h) * radius_ratio)
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [(0, 0), (w - 1, h - 1)], radius=radius, fill=255
    )
    r, g, b, original_alpha = img.split()
    orig_a = np.array(original_alpha, dtype=np.float32)
    mask_a = np.array(mask, dtype=np.float32) / 255.0
    new_alpha = np.clip(orig_a * mask_a, 0, 255).astype(np.uint8)
    return Image.merge("RGBA", (r, g, b, Image.fromarray(new_alpha, "L")))


def main() -> None:
    src_path = SRC if SRC.exists() else SRC_FALLBACK
    if not src_path.exists():
        raise SystemExit(f"源图不存在：{SRC} / {SRC_FALLBACK}")

    src = Image.open(src_path).convert("RGBA")
    print(f"源图：{src_path.relative_to(ROOT)}  {src.size}")

    # macOS PNG
    for size in MAC_SIZES:
        resized = src.resize((size, size), Image.LANCZOS)
        rounded = round_corners(resized)
        target = ICON_DIR / f"app_icon_{size}.png"
        rounded.save(target, format="PNG", optimize=True)
        print(f"  macOS {size:>4}px → {target.name}")

    # Windows ICO（多尺寸 PNG 嵌入 ICO 容器）
    win_target = ROOT / "windows/runner/resources/app_icon.ico"
    win_images = [round_corners(src.resize((s, s), Image.LANCZOS)) for s in WIN_SIZES]
    win_images[-1].save(
        win_target,
        format="ICO",
        sizes=[(s, s) for s in WIN_SIZES],
    )
    print(f"  Windows ICO → {win_target.name}  尺寸: {WIN_SIZES}")


if __name__ == "__main__":
    main()
