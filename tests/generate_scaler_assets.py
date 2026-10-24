"""Generate original-size 24-bit BMPs for on-board scaler verification.

No image library or PC resizing is involved. The red/green gradients and blue
checkerboard make orientation, interpolation and aspect-ratio changes visible.
"""
import argparse
import struct
from pathlib import Path


def write_bmp(path, width, height, top_down=False):
    stride = (width * 3 + 3) & ~3
    size = 54 + stride * height
    header = struct.pack('<2sIHHI', b'BM', size, 0, 0, 54)
    dib = struct.pack('<IiiHHIIiiII', 40, width,
                      -height if top_down else height, 1, 24, 0,
                      stride * height, 2835, 2835, 0, 0)
    with path.open('wb') as output:
        output.write(header + dib)
        for stored_y in range(height):
            y = stored_y if top_down else height - 1 - stored_y
            row = bytearray()
            for x in range(width):
                r = x * 255 // max(1, width - 1)
                g = y * 255 // max(1, height - 1)
                b = 220 if ((x // 24 + y // 24) & 1) else 30
                if x < 8 or y < 8 or x >= width-8 or y >= height-8:
                    r, g, b = 255, 255, 255
                row.extend((b, g, r))
            row.extend(bytes(stride - width * 3))
            output.write(row)
    print(f'{path.name}: {width}x{height}, {"top-down" if top_down else "bottom-up"}, {size} bytes')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path,
                        default=Path(__file__).resolve().parents[1] / 'doc' / 'scaler_test_images')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for name, w, h, top_down in (
            ('0_321x241_padding.bmp', 321, 241, False),
            ('1_800x600_landscape.bmp', 800, 600, False),
            ('2_360x640_portrait_topdown.bmp', 360, 640, True),
            ('3_640x480_identity.bmp', 640, 480, False)):
        write_bmp(args.output / name, w, h, top_down)


if __name__ == '__main__':
    main()
