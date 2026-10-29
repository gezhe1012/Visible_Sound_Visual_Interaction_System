import sys
from docx import Document
from docx.shared import Pt

doc = Document(sys.argv[1])
out = []

sec = doc.sections[0]
out.append(f"SECTION page={sec.page_width}x{sec.page_height} margins L{sec.left_margin} R{sec.right_margin} T{sec.top_margin} B{sec.bottom_margin}")
st = doc.styles['Normal']
out.append(f"Normal font={st.font.name} size={st.font.size} eastasia?")

for i, p in enumerate(doc.paragraphs):
    runs = []
    for r in p.runs[:4]:
        f = r.font
        rpr = r._element.rPr
        ea = None
        if rpr is not None and rpr.rFonts is not None:
            ea = rpr.rFonts.get('{http://schemas.openxmlformats.org/wordprocessingml/2006/main}eastAsia')
        runs.append(f"[{r.text[:12]!r} b={f.bold} sz={f.size.pt if f.size else None} nm={f.name} ea={ea} color={f.color.rgb if f.color and f.color.rgb else None}]")
    pf = p.paragraph_format
    out.append(f"P{i:03d} style={p.style.name} align={p.alignment} first={pf.first_line_indent} left={pf.left_indent} before={pf.space_before} after={pf.space_after} ls={pf.line_spacing} runs={len(p.runs)} {' '.join(runs)}")

print("\n".join(out))
