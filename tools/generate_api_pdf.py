from pathlib import Path
import sys


SOURCE = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "docs" / "required_apis.md"
OUTPUT = SOURCE.with_suffix(".pdf")


def escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def lines_from_markdown():
    output = []
    for raw in SOURCE.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line:
            output.append("")
        elif line.startswith("# "):
            output.extend([line[2:].upper(), ""])
        elif line.startswith("## "):
            output.extend(["", line[3:].upper()])
        elif line.startswith("- "):
            output.append("  • " + line[2:])
        else:
            output.append(line.replace("`", ""))
    return output


def make_pdf():
    source_lines = lines_from_markdown()
    pages = [source_lines[i : i + 42] for i in range(0, len(source_lines), 42)]
    objects = []

    def add(value):
        objects.append(value)
        return len(objects)

    catalog = add(None)
    pages_obj = add(None)
    font = add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
    page_ids = []
    content_ids = []

    for page_lines in pages:
        commands = ["BT", "/F1 10 Tf", "50 790 Td", "14 TL"]
        for line in page_lines:
            size = 15 if line.endswith("API REFERENCE") else 10
            commands.append(f"/F1 {size} Tf")
            commands.append(f"({escape(line[:115])}) Tj")
            commands.append("T*")
        commands.append("ET")
        content = "\n".join(commands).encode("latin-1", errors="replace")
        content_ids.append(add(f"<< /Length {len(content)} >>\nstream\n{content.decode('latin-1')}\nendstream"))
        page_ids.append(add(None))

    objects[catalog - 1] = f"<< /Type /Catalog /Pages {pages_obj} 0 R >>"
    objects[pages_obj - 1] = f"<< /Type /Pages /Kids [{' '.join(f'{p} 0 R' for p in page_ids)}] /Count {len(page_ids)} >>"
    for page_id, content_id in zip(page_ids, content_ids):
        objects[page_id - 1] = f"<< /Type /Page /Parent {pages_obj} 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 {font} 0 R >> >> /Contents {content_id} 0 R >>"

    pdf = bytearray(b"%PDF-1.4\n")
    offsets = [0]
    for number, obj in enumerate(objects, start=1):
        offsets.append(len(pdf))
        pdf.extend(f"{number} 0 obj\n{obj}\nendobj\n".encode("latin-1"))
    xref = len(pdf)
    pdf.extend(f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode())
    for offset in offsets[1:]:
        pdf.extend(f"{offset:010d} 00000 n \n".encode())
    pdf.extend(f"trailer\n<< /Size {len(objects) + 1} /Root {catalog} 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode())
    OUTPUT.write_bytes(pdf)


if __name__ == "__main__":
    make_pdf()
