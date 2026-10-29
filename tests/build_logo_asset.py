"""Compile the supplied BMP to tiny combinational color masks, never edit it.

The HDL fragment is printed for apply_patch, or compared byte-for-byte with
the checked-in fragment. Generated test raster/manifest are reproducible
asset build products, not independently designed or AI-redrawn artwork.
"""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'doc/TF卡图片/logo_640x480_24bit_不翻转.bmp'
HDL = ROOT / 'src/user_source/hdl_source/video_osd_overlay.v'
OUT = ROOT / 'doc/logo_overlay'
PALETTE = ((255, 255, 255), (28, 45, 78), (237, 28, 36))
WIDTH, HEIGHT = 48, 31
BEGIN, END = '// LOGO_BITMAP_BEGIN', '// LOGO_BITMAP_END'


def compile_asset():
    with Image.open(SOURCE) as original:
        assert original.size == (640, 480) and original.mode == 'RGB'
        bbox = ImageChops.difference(original, Image.new('RGB', original.size, 'white')).getbbox()
        assert bbox == (13, 63, 288, 241), f'Unexpected supplied logo: {bbox}'
        # BOX integration preserves area/shape while reducing the supplied
        # raster. Nearest palette removes fringe colors, not logo geometry.
        small = original.crop(bbox).resize((WIDTH, HEIGHT), Image.Resampling.BOX)
        colors = [min(range(3), key=lambda k: sum((p[i] - PALETTE[k][i]) ** 2 for i in range(3)))
                  for p in small.get_flattened_data()]
    lines = [BEGIN]
    for color, name in ((2, 'red'), (1, 'blue')):
        lines += [f'function [47:0] logo_{name}_row;', '    input [4:0] row;',
                  '    begin', '        case(row)']
        for y in range(HEIGHT):
            mask = sum(1 << (WIDTH - 1 - x) for x in range(WIDTH) if colors[y * WIDTH + x] == color)
            lines.append(f"            5'd{y}: logo_{name}_row=48'h{mask:012X};")
        lines += [f"            default: logo_{name}_row=48'd0;", '        endcase', '    end', 'endfunction']
    lines += [END]
    return bbox, colors, '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--emit-rtl', action='store_true')
    parser.add_argument('--generate-test-assets', action='store_true')
    args = parser.parse_args()
    bbox, colors, fragment = compile_asset()
    if args.emit_rtl:
        print(fragment)
        return
    source_text = HDL.read_text(encoding='utf-8')
    actual = source_text[source_text.index(BEGIN):source_text.index(END) + len(END)]
    assert actual == fragment, 'Logo masks in HDL do not match the supplied BMP'
    assert 'function [7:0] logo_char' not in source_text, 'Old ANLOGIC text renderer remains'
    if args.generate_test_assets:
        OUT.mkdir(parents=True, exist_ok=True)
        logo = Image.new('RGB', (WIDTH, HEIGHT))
        logo.putdata([PALETTE[k] for k in colors])
        logo.save(OUT / 'logo_compiled.png')
        # Constant independent RGB oracle for ModelSim; build product only.
        (ROOT / 'tests/logo_expected.hex').write_text(
            ''.join('%02X%02X%02X\n' % PALETTE[k] for k in colors), encoding='ascii')
        manifest = dict(source=SOURCE.relative_to(ROOT).as_posix(), source_sha256=hashlib.sha256(SOURCE.read_bytes()).hexdigest().upper(),
                        source_bbox=list(bbox), bitmap_size=[WIDTH, HEIGHT], bitmap_origin=[22, 16],
                        white_badge=[18, 14, 74, 50], removed_old_panel=[18, 14, 174, 50],
                        palette=['%02X%02X%02X' % c for c in PALETTE],
                        orientation='PIL logical top-to-bottom, no mirror or flip', pixels_per_color=[colors.count(k) for k in range(3)],
                        encoding='two 48-bit combinational row masks; no external ROM file at runtime')
        (OUT / 'logo_asset.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print('ALL LOGO ASSET TESTS PASSED: original BMP unchanged, 48x31 upright proportional crop, two exact combinational color masks')


if __name__ == '__main__':
    main()
