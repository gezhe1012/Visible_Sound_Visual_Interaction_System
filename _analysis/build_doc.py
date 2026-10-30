# -*- coding: utf-8 -*-
"""组装修订版技术文档。"""
import os
import sys
import zipfile

from docx import Document
from docx.shared import Pt, Cm
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

import docx_kit as kit
import content_a
import content_b
import content_c

HERE = os.path.dirname(os.path.abspath(__file__))
IMG_DIR = os.path.join(HERE, "img")


def extract_images(src, outdir):
    os.makedirs(outdir, exist_ok=True)
    with zipfile.ZipFile(src) as z:
        for name in ("image1.png", "image2.png", "image3.png", "image4.png"):
            data = z.read("word/media/" + name)
            with open(os.path.join(outdir, name), "wb") as f:
                f.write(data)


def img(name):
    return os.path.join(IMG_DIR, name)


def setup(doc):
    sec = doc.sections[0]
    sec.page_width = Cm(21.0)
    sec.page_height = Cm(29.7)
    sec.top_margin = Cm(2.54)
    sec.bottom_margin = Cm(2.54)
    sec.left_margin = Cm(3.17)
    sec.right_margin = Cm(3.17)
    sec.header_distance = Cm(1.5)
    sec.footer_distance = Cm(1.75)

    style = doc.styles["Normal"]
    style.font.name = kit.BODY_FONT_EN
    style.font.size = Pt(12)
    rpr = style.element.get_or_add_rPr()
    rfonts = rpr.find(qn("w:rFonts"))
    if rfonts is None:
        rfonts = OxmlElement("w:rFonts")
        rpr.insert(0, rfonts)
    rfonts.set(qn("w:ascii"), kit.BODY_FONT_EN)
    rfonts.set(qn("w:hAnsi"), kit.BODY_FONT_EN)
    rfonts.set(qn("w:eastAsia"), kit.BODY_FONT_CN)
    # 关闭网格对齐，避免中文行距被文档网格强行拉伸
    ppr = style.element.get_or_add_pPr()
    snap = OxmlElement("w:snapToGrid")
    snap.set(qn("w:val"), "0")
    ppr.append(snap)

    # 页脚沿用原文档自带的 PAGE 域，不重复添加，避免出现两个页码


def clear_body(doc):
    body = doc.element.body
    for child in list(body):
        if child.tag == qn("w:sectPr"):
            continue
        body.remove(child)


def main():
    src_docx = sys.argv[1]
    out_docx = sys.argv[2]

    extract_images(src_docx, IMG_DIR)

    doc = Document(src_docx)
    clear_body(doc)
    setup(doc)

    cp = doc.core_properties
    cp.title = "看得见的声音：基于安路 FPGA 的双屏声学科普展示系统"
    cp.subject = "2026 全国大学生嵌入式芯片与系统设计竞赛 · FPGA 创新设计赛道 · 安路选题一"
    cp.keywords = "声音可视化;双屏;定点FFT;频谱瀑布;音高估计;谐波;李萨如;安路FPGA"

    content_a.build(doc, img)
    content_b.build(doc, img)
    content_c.build(doc, img)

    doc.save(out_docx)
    print("saved:", out_docx)
    print("paragraphs:", len(doc.paragraphs), "tables:", len(doc.tables))


if __name__ == "__main__":
    main()
