import io
import pypdf

def merge_pdfs(*pdf_bytes_list: bytes) -> bytes:
    """Merge multiple PDF byte strings into one."""
    writer = pypdf.PdfWriter()
    for pdf_bytes in pdf_bytes_list:
        reader = pypdf.PdfReader(io.BytesIO(pdf_bytes))
        for page in reader.pages:
            writer.add_page(page)
    out = io.BytesIO()
    writer.write(out)
    out.seek(0)
    return out.read()
