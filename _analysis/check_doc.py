# -*- coding: utf-8 -*-
"""成稿自检：标题层级、图表编号引用、占位符、字符统计。"""
import re
import sys
from docx import Document

doc = Document(sys.argv[1])
text = []
for p in doc.paragraphs:
    text.append(p.text)
for t in doc.tables:
    for row in t.rows:
        for c in row.cells:
            text.append(c.text)
blob = "\n".join(text)

caps_tbl = re.findall(r"表 (\d+-\d+)　", blob)
caps_fig = re.findall(r"图 (\d+-\d+)　", blob)
refs_tbl = set(re.findall(r"表 (\d+-\d+)", blob))
refs_fig = set(re.findall(r"图 (\d+-\d+)", blob))
print("表题:", caps_tbl)
print("图题:", caps_fig)
print("引用表:", sorted(refs_tbl - set(caps_tbl)))
print("引用图:", sorted(refs_fig - set(caps_fig)))
print("重复表题:", [x for x in set(caps_tbl) if caps_tbl.count(x) > 1])
print("重复图题:", [x for x in set(caps_fig) if caps_fig.count(x) > 1])
for bad in ("TODO", "待填", "XXX", "插图建议", "？", "??"):
    if bad in blob:
        print("发现占位符:", bad, blob.count(bad))
print("段落:", len(doc.paragraphs), "表格:", len(doc.tables))
print("正文字符:", sum(len(p.text) for p in doc.paragraphs))
print("总字符:", len(blob))
