import sys, os, zipfile, re
from docx import Document
from docx.table import Table
from docx.text.paragraph import Paragraph

src = sys.argv[1]
out = sys.argv[2]

doc = Document(src)

def iter_block_items(parent):
    from docx.oxml.ns import qn
    body = parent.element.body
    for child in body.iterchildren():
        if child.tag == qn('w:p'):
            yield Paragraph(child, parent)
        elif child.tag == qn('w:tbl'):
            yield Table(child, parent)
        elif child.tag == qn('w:sectPr'):
            pass

lines = []
idx = 0
for block in iter_block_items(doc):
    if isinstance(block, Paragraph):
        txt = block.text
        style = block.style.name if block.style is not None else ''
        has_img = 'graphic' in block._p.xml
        tag = '[IMG]' if has_img else ''
        lines.append(f"P{idx:04d} <{style}>{tag} {txt}")
    else:
        lines.append(f"T{idx:04d} TABLE rows={len(block.rows)} cols={len(block.columns)}")
        for ri, row in enumerate(block.rows):
            cells = [c.text.replace('\n', ' / ') for c in row.cells]
            lines.append("   R%02d | %s" % (ri, " || ".join(cells)))
    idx += 1

with open(out, 'w', encoding='utf-8') as f:
    f.write("\n".join(lines))

with zipfile.ZipFile(src) as z:
    names = z.namelist()
print("paragraphs/tables:", idx, "total blocks")
print("media:", len([n for n in names if n.startswith('word/media')]))
print("size chars:", sum(len(l) for l in lines))
