#!/usr/bin/env python3
"""
图标生成脚本 - 为Gsou VPN项目生成ICO图标
"""

from PIL import Image, ImageDraw
import os

def create_simple_clear_icon(size):
    """最简单的G - 黑底白字，大到爆"""
    # 创建图像
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # 纯黑色背景 - 方形
    draw.rectangle([0, 0, size, size], fill=(0, 0, 0, 255))

    # 计算G的尺寸 - 超级大
    margin = max(size // 8, 2)  # 很小的边距
    g_thick = max(size // 5, 4)  # 超粗线条

    # G占据几乎整个空间
    g_left = margin
    g_right = size - margin
    g_top = margin
    g_bottom = size - margin
    g_width = g_right - g_left
    g_height = g_bottom - g_top
    g_mid_x = g_left + g_width // 2
    g_mid_y = g_top + g_height // 2

    # 白色G字母，极简风格
    # 上边
    draw.rectangle([g_left, g_top, g_right, g_top + g_thick],
                   fill=(255, 255, 255, 255))

    # 左边
    draw.rectangle([g_left, g_top, g_left + g_thick, g_bottom],
                   fill=(255, 255, 255, 255))

    # 下边
    draw.rectangle([g_left, g_bottom - g_thick, g_right, g_bottom],
                   fill=(255, 255, 255, 255))

    # 中间横线（从中心到右边）
    draw.rectangle([g_mid_x, g_mid_y, g_right, g_mid_y + g_thick],
                   fill=(255, 255, 255, 255))

    # 右边竖线（只下半部分）
    draw.rectangle([g_right - g_thick, g_mid_y, g_right, g_bottom],
                   fill=(255, 255, 255, 255))

    return img

def generate_ico_file():
    """生成多尺寸ICO文件"""
    sizes = [16, 24, 32, 48, 64, 128, 256]
    images = []

    print("Generating high-clarity icons...")
    for size in sizes:
        print(f"  - Generating {size}x{size} size (optimized for clarity)")
        img = create_simple_clear_icon(size)
        images.append(img)

    # 保存为ICO文件
    output_path = os.path.join(os.path.dirname(os.path.dirname(__file__)),
                               'assets', 'gsou_icon.ico')

    print(f"Saving ICO file to: {output_path}")
    images[0].save(output_path, format='ICO', sizes=[(img.width, img.height) for img in images])

    # 同时保存单个PNG文件用于预览
    png_path = os.path.join(os.path.dirname(os.path.dirname(__file__)),
                            'assets', 'gsou_icon_256.png')
    images[-1].save(png_path, format='PNG')

    print("Icon generation completed!")
    print(f"   ICO file: {output_path}")
    print(f"   PNG preview: {png_path}")

    return output_path

if __name__ == "__main__":
    generate_ico_file()