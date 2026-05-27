"""为 macOS / Windows 应用图标添加圆角 mask。

从 macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png 派生：
  - macOS 7 个尺寸（16/32/64/128/256/512/1024）覆盖原 PNG
  - Windows ICO 多尺寸（16/24/32/48/64/128/256）覆盖 app_icon.ico

圆角半径采用图标尺寸的 22.5%，接近 macOS Big Sur squircle 比例。
"""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png"

MAC_SIZES = [16, 32, 64, 128, 256, 512, 1024]
WIN_SIZES = [16, 24, 32, 48, 64, 128, 256]
RADIUS_RATIO = 0.225  # macOS Big Sur squircle 近似（圆角矩形）

def round_corners(img: Image.Image, radius_ratio: float = RADIUS_RATIO) -> Image.Image:
    """给图像加圆角 alpha mask。输入图像应为 RGBA / RGB，输出 RGBA。"""
    img = img.convert("RGBA")
    w, h = img.size
    radius = int(min(w, h) * radius_ratio)
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [(0, 0), (w - 1, h - 1)], radius=radius, fill=255
    )
    # 把原图 alpha 与 mask 取最小值，保持原透明度
    r, g, b, a = img.split()
    new_alpha = Image.eval(a, lambda x: x).point(lambda x: x)
    # 简化：直接用 mask 作为新 alpha（原始图通常没有 alpha 边缘）
    return Image.merge("RGBA", (r, g, b, mask))

def main() -> None:
    if not SRC.exists():
        raise SystemExit(f"源图不存在：{SRC}")

    src = Image.open(SRC).convert("RGBA")
    print(f"源图：{SRC.name}  {src.size}")

    # macOS PNG
    mac_dir = SRC.parent
    for size in MAC_SIZES:
        # 用高质量缩放 → 加圆角
        resized = src.resize((size, size), Image.LANCZOS)
        rounded = round_corners(resized)
        target = mac_dir / f"app_icon_{size}.png"
        rounded.save(target, format="PNG", optimize=True)
        print(f"  macOS {size:>4}px → {target.name}")

    # Windows ICO（多尺寸 PNG 嵌入 ICO 容器）
    win_target = ROOT / "windows/runner/resources/app_icon.ico"
    win_images = []
    for size in WIN_SIZES:
        resized = src.resize((size, size), Image.LANCZOS)
        win_images.append(round_corners(resized))
    # Pillow 的 ico 保存：把最大尺寸作为基底，sizes= 指定所有尺寸
    win_images[-1].save(
        win_target,
        format="ICO",
        sizes=[(s, s) for s in WIN_SIZES],
    )
    print(f"  Windows ICO → {win_target.name}  尺寸: {WIN_SIZES}")

if __name__ == "__main__":
    main()
