# 
from typing import Optional, List
from fastapi import FastAPI, File, UploadFile, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, Response, JSONResponse
from auth import router as auth_router
import os
import mimetypes
from typing import Tuple
from datetime import datetime
from pydantic import BaseModel
import zipfile
import re
from uuid import uuid4


class PushTokenUpsert(BaseModel):
    token: str
    platform: Optional[str] = None
    deviceId: Optional[str] = None
    appVersion: Optional[str] = None


class PushTokenDelete(BaseModel):
    token: str


class PushTestRequest(BaseModel):
    token: str
    title: str = "Test Notification"
    body: str = "Hello from DigiSanchika backend"
    data: Optional[dict] = None

app = FastAPI(
    title="DigiSanchika - Digital Document Management System",
    description="Backend API for DigiSanchika mobile app",
    version="1.0.0"
)
app.include_router(auth_router)
# Add CORS middleware right after creating the app
origins = [
    # "http://localhost",  # For web
    # "http://localhost:3000",  # For web dev
    # "http://127.0.0.1",  # Localhost
    # "http://127.0.0.1:3000",
    # "http://localhost:8000",
    # "http://10.0.2.2:8000",  # Android Emulator
    # "http://10.0.2.2",  # Android Emulator
    # "http://localhost:8000",
    # "http://192.168.100.122:8000"    # iOS Simulator
    "*"  # For testing (remove in production) - commented for security
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Create upload directory
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
UPLOAD_DIR = os.path.join(BASE_DIR, "uploads")
os.makedirs(UPLOAD_DIR, exist_ok=True)

# Converted previews cache
CONVERTED_DIR = os.path.join(BASE_DIR, "converted")
os.makedirs(CONVERTED_DIR, exist_ok=True)

# In-memory conversion status (replace with DB/queue later)
conversion_status_db = {}

# In-memory upload tracking (replace with DB later)
pending_uploads = {}

# In-memory push token storage (replace with DB in production)
push_tokens_db = {}  # token -> metadata dict

# -------- Helpers --------
def _find_file_by_id(document_id: str) -> Tuple[str, str]:
    matching_files = []
    if os.path.exists(UPLOAD_DIR):
        for filename in os.listdir(UPLOAD_DIR):
            if filename.startswith(document_id):
                matching_files.append(filename)
    if not matching_files:
        raise HTTPException(status_code=404, detail=f"Document with ID {document_id} not found")
    filename = matching_files[0]
    file_path = os.path.join(UPLOAD_DIR, filename)
    if not os.path.isfile(file_path):
        raise HTTPException(status_code=404, detail="File not found")
    return filename, file_path

def _guess_mime_type(filename: str) -> str:
    mime, _ = mimetypes.guess_type(filename)
    return mime or "application/octet-stream"

def _safe_filename(name: str) -> str:
    return "".join(c if c.isalnum() or c in "._-" else "_" for c in name)

def _extract_docx_text(file_path: str) -> str:
    try:
        with zipfile.ZipFile(file_path) as z:
            with z.open("word/document.xml") as f:
                xml = f.read().decode("utf-8", errors="ignore")
        # very simple text extraction from <w:t> tags
        texts = re.findall(r"<w:t[^>]*>(.*?)</w:t>", xml)
        return "\n".join(t for t in texts if t)
    except Exception:
        return ""

def _extract_xlsx_text(file_path: str) -> str:
    try:
        with zipfile.ZipFile(file_path) as z:
            shared_strings = []
            if "xl/sharedStrings.xml" in z.namelist():
                with z.open("xl/sharedStrings.xml") as f:
                    xml = f.read().decode("utf-8", errors="ignore")
                shared_strings = re.findall(r"<t[^>]*>(.*?)</t>", xml)

            # Use first sheet if present
            sheet_path = "xl/worksheets/sheet1.xml"
            if sheet_path not in z.namelist():
                # try any sheet
                for name in z.namelist():
                    if name.startswith("xl/worksheets/sheet") and name.endswith(".xml"):
                        sheet_path = name
                        break
            with z.open(sheet_path) as f:
                sheet_xml = f.read().decode("utf-8", errors="ignore")

        rows = []
        for row in re.findall(r"<row[^>]*>(.*?)</row>", sheet_xml, flags=re.DOTALL):
            cells = []
            for c in re.findall(r"<c[^>]*>(.*?)</c>", row, flags=re.DOTALL):
                v_match = re.search(r"<v[^>]*>(.*?)</v>", c)
                if not v_match:
                    cells.append("")
                    continue
                v = v_match.group(1)
                if 't="s"' in c:
                    try:
                        idx = int(v)
                        cells.append(shared_strings[idx] if idx < len(shared_strings) else v)
                    except Exception:
                        cells.append(v)
                else:
                    cells.append(v)
            rows.append("\t".join(cells))
        return "\n".join(rows)
    except Exception:
        return ""


def _converted_pdf_path(document_id: str) -> str:
    return os.path.join(CONVERTED_DIR, f"{document_id}.pdf")


def _converted_txt_path(document_id: str) -> str:
    return os.path.join(CONVERTED_DIR, f"{document_id}.txt")


def _set_conversion_status(document_id: str, status: str, error: Optional[str] = None):
    conversion_status_db[document_id] = {
        "status": status,
        "error": error,
        "updated_at": datetime.now().isoformat(),
    }


def _get_conversion_status(document_id: str):
    return conversion_status_db.get(document_id)




def _ensure_text_extract(document_id: str, file_path: str, ext: str) -> Optional[str]:
    txt_path = _converted_txt_path(document_id)
    if os.path.exists(txt_path):
        if ext in [".txt", ".csv"]:
            return txt_path
        # For Office files, regenerate to avoid stale/binary TXT from older logic
        try:
            os.remove(txt_path)
        except Exception:
            pass
    try:
        if ext in [".txt", ".csv"]:
            with open(file_path, "rb") as f:
                data = f.read()
            with open(txt_path, "wb") as f:
                f.write(data)
            return txt_path
        if ext == ".docx":
            text = _extract_docx_text(file_path)
            if not text:
                text = "[No text extracted from DOCX]"
            with open(txt_path, "w", encoding="utf-8") as f:
                f.write(text)
            return txt_path
        if ext == ".xlsx":
            text = _extract_xlsx_text(file_path)
            if not text:
                text = "[No text extracted from XLSX]"
            with open(txt_path, "w", encoding="utf-8") as f:
                f.write(text)
            return txt_path
    except Exception:
        return None
    return None

def _serve_file_with_range(request: Request, file_path: str, media_type: str, filename: str):
    file_size = os.path.getsize(file_path)
    range_header = request.headers.get("range")
    if not range_header:
        return FileResponse(file_path, media_type=media_type, filename=filename)

    # Expected format: bytes=start-end
    try:
        _, range_spec = range_header.split("=")
        start_str, end_str = range_spec.split("-")
        start = int(start_str) if start_str else 0
        end = int(end_str) if end_str else file_size - 1
        end = min(end, file_size - 1)
        if start > end:
            raise ValueError("Invalid range")
    except Exception:
        return FileResponse(file_path, media_type=media_type, filename=filename)

    with open(file_path, "rb") as f:
        f.seek(start)
        data = f.read(end - start + 1)

    headers = {
        "Content-Range": f"bytes {start}-{end}/{file_size}",
        "Accept-Ranges": "bytes",
        "Content-Length": str(len(data)),
        "Content-Disposition": f'inline; filename="{filename}"',
    }
    return Response(content=data, status_code=206, headers=headers, media_type=media_type)


# -------- Push Token Endpoints (FCM token registry) --------
@app.post("/push-tokens")
async def upsert_push_token(payload: PushTokenUpsert):
    token = (payload.token or "").strip()
    if not token:
        raise HTTPException(status_code=400, detail="token is required")

    push_tokens_db[token] = {
        "token": token,
        "platform": payload.platform,
        "deviceId": payload.deviceId,
        "appVersion": payload.appVersion,
        "enabled": True,
        "last_seen_at": datetime.now().isoformat(),
    }
    return {"success": True}


@app.delete("/push-tokens")
async def delete_push_token(payload: PushTokenDelete):
    token = (payload.token or "").strip()
    if not token:
        raise HTTPException(status_code=400, detail="token is required")

    if token in push_tokens_db:
        # Soft-disable (keep record for debugging)
        push_tokens_db[token]["enabled"] = False
        push_tokens_db[token]["disabled_at"] = datetime.now().isoformat()
    return {"success": True}


@app.post("/push-test")
async def push_test(payload: PushTestRequest):
    """
    Test endpoint. In a real deployment you would send via Firebase Admin SDK.
    Here we just validate the token exists and echo the payload.
    """
    token = (payload.token or "").strip()
    if not token:
        raise HTTPException(status_code=400, detail="token is required")

    meta = push_tokens_db.get(token)
    if not meta or not meta.get("enabled"):
        raise HTTPException(status_code=404, detail="token not registered")

    return {
        "success": True,
        "message": "Stubbed push-test. Integrate Firebase Admin SDK to actually send.",
        "token_meta": meta,
        "notification": {"title": payload.title, "body": payload.body},
        "data": payload.data or {},
    }

# Then define your routes below
@app.get("/")
async def root():
    return {
        "message": "Welcome to DigiSanchika API",
        "version": "1.0.0",
        "endpoints": {
            "document_upload": "/api/upload",
            "get_documents": "/api/documents",
            "document_details": "/api/documents/{id}",
            "api_docs": "/docs"
        }
    }

# Document Upload Endpoint
@app.post("/api/upload")
async def upload_document(
    file: UploadFile = File(...),
    title: str = "",
    category: str = "General",
    tags: str = ""
):
    """
    Upload a document to the system.
    
    Parameters:
    - file: The document file to upload
    - title: Custom title for the document (optional)
    - category: Document category (default: "General")
    - tags: Comma-separated tags (optional)
    """
    try:
        # Generate unique filename
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        file_extension = os.path.splitext(file.filename)[1]
        filename = f"{timestamp}_{file.filename}"
        file_path = os.path.join(UPLOAD_DIR, filename)
        
        # Save file
        contents = await file.read()
        with open(file_path, "wb") as f:
            f.write(contents)
        
        # Return document info
        return {
            "status": "success",
            "message": "Document uploaded successfully",
            "document": {
                "id": timestamp,
                "filename": filename,
                "original_name": file.filename,
                "original_filename": file.filename,
                "file_name": filename,
                "title": title if title else file.filename,
                "category": category,
                "tags": tags.split(",") if tags else [],
                "size": len(contents),
                "file_size_bytes": len(contents),
                "mime_type": _guess_mime_type(filename),
                "upload_date": datetime.now().isoformat(),
                "created_at": datetime.now().isoformat(),
                "file_path": file_path
            }
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Upload failed: {str(e)}")

# Get All Documents
@app.get("/api/documents")
async def get_documents():
    """
    Retrieve all uploaded documents.
    
    Returns a list of documents with basic information.
    """
    try:
        documents = []
        if os.path.exists(UPLOAD_DIR):
            for filename in os.listdir(UPLOAD_DIR):
                file_path = os.path.join(UPLOAD_DIR, filename)
                if os.path.isfile(file_path):
                    stat = os.stat(file_path)
                    
                    # Extract original name if possible
                    original_name = filename.split('_', 1)[1] if '_' in filename else filename
                    
                    documents.append({
                        "id": filename.split("_")[0] if "_" in filename else "unknown",
                        "filename": filename,
                        "original_name": original_name,
                        "original_filename": original_name,
                        "file_name": filename,
                        "size": stat.st_size,
                        "file_size_bytes": stat.st_size,
                        "size_mb": round(stat.st_size / (1024 * 1024), 2) if stat.st_size > 0 else 0,
                        "upload_date": datetime.fromtimestamp(stat.st_ctime).isoformat(),
                        "created_at": datetime.fromtimestamp(stat.st_ctime).isoformat(),
                        "mime_type": _guess_mime_type(filename),
                        "file_type": os.path.splitext(filename)[1].lower().replace('.', '') or 'unknown'
                    })
        
        return {
            "status": "success",
            "count": len(documents),
            "documents": documents
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch documents: {str(e)}")

# Alias without /api (mobile app currently calls /documents)
@app.get("/documents")
async def get_documents_alias():
    return await get_documents()

# Get Document Details
@app.get("/api/documents/{document_id}")
async def get_document(document_id: str):
    """
    Get details of a specific document by ID.
    
    Parameters:
    - document_id: The ID of the document (timestamp prefix)
    """
    try:
        # Find file with matching ID prefix
        matching_files = []
        if os.path.exists(UPLOAD_DIR):
            for filename in os.listdir(UPLOAD_DIR):
                if filename.startswith(document_id):
                    file_path = os.path.join(UPLOAD_DIR, filename)
                    if os.path.isfile(file_path):
                        stat = os.stat(file_path)
                        matching_files.append({
                            "id": document_id,
                            "filename": filename,
                            "original_name": filename.split('_', 1)[1] if '_' in filename else filename,
                            "original_filename": filename.split('_', 1)[1] if '_' in filename else filename,
                            "file_name": filename,
                            "size": stat.st_size,
                            "file_size_bytes": stat.st_size,
                            "upload_date": datetime.fromtimestamp(stat.st_ctime).isoformat(),
                            "created_at": datetime.fromtimestamp(stat.st_ctime).isoformat(),
                            "last_modified": datetime.fromtimestamp(stat.st_mtime).isoformat(),
                            "file_path": file_path,
                            "mime_type": _guess_mime_type(filename),
                            "file_type": os.path.splitext(filename)[1].lower().replace('.', '') or 'unknown'
                        })
        
        if not matching_files:
            raise HTTPException(status_code=404, detail=f"Document with ID {document_id} not found")
        
        return {
            "status": "success",
            "document": matching_files[0]
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching document: {str(e)}")

# Alias without /api (mobile app currently calls /documents/{id})
@app.get("/documents/{document_id}")
async def get_document_alias(document_id: str):
    return await get_document(document_id)

# Download Document
@app.get("/api/download/{document_id}")
async def download_document(document_id: str):
    """
    Download a document by ID.
    
    Parameters:
    - document_id: The ID of the document to download
    """
    try:
        # Find the file
        matching_files = []
        if os.path.exists(UPLOAD_DIR):
            for filename in os.listdir(UPLOAD_DIR):
                if filename.startswith(document_id):
                    matching_files.append(filename)
        
        if not matching_files:
            raise HTTPException(status_code=404, detail=f"Document with ID {document_id} not found")
        
        file_path = os.path.join(UPLOAD_DIR, matching_files[0])
        
        # You would typically use FileResponse for actual file download
        # from fastapi.responses import FileResponse
        # return FileResponse(file_path, filename=matching_files[0].split('_', 1)[1])
        
        return {
            "status": "success",
            "message": f"Document {document_id} found",
            "filename": matching_files[0],
            "download_url": f"/documents/file/{matching_files[0]}"  # This would be another endpoint
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Download error: {str(e)}")

# -------- New endpoints required by mobile app --------
# 1) download-url (returns URL)
@app.get("/api/documents/{document_id}/download-url")
async def get_download_url(document_id: str, request: Request):
    filename, _ = _find_file_by_id(document_id)
    origin = str(request.base_url).rstrip("/")
    return {"url": f"{origin}/api/documents/file/{filename}"}

# Alias without /api
@app.get("/documents/{document_id}/download-url")
async def get_download_url_alias(document_id: str, request: Request):
    return await get_download_url(document_id, request)

# 2) view-url (can return bytes directly)
@app.get("/api/documents/{document_id}/view-url")
async def view_document(document_id: str, request: Request):
    filename, file_path = _find_file_by_id(document_id)
    media_type = _guess_mime_type(filename)
    ext = os.path.splitext(filename)[1].lower()
    original_name = filename.split("_", 1)[1] if "_" in filename else filename

    origin = str(request.base_url).rstrip("/")

    # Always return JSON with a URL so mobile can fetch bytes consistently
    if ext in [".docx", ".xlsx", ".csv", ".txt"]:
        return {
            "url": f"{origin}/api/conversion/{document_id}/download/txt",
            "conversionStatus": "completed",
            "conversionError": None,
            "isPdf": False,
            "mimeType": "text/plain",
            "originalMimeType": media_type,
            "fileName": original_name,
        }

    # Legacy formats not supported for preview
    if ext in [".doc", ".xls"]:
        return {
            "conversionStatus": "failed",
            "conversionError": "Preview not supported for legacy Office formats. Please upload DOCX/XLSX.",
            "isPdf": False,
            "mimeType": media_type,
            "originalMimeType": media_type,
            "fileName": original_name,
        }

    # PDFs and images return direct file URL
    return {
        "url": f"{origin}/api/documents/file/{filename}",
        "conversionStatus": "completed",
        "conversionError": None,
        "isPdf": ext == ".pdf",
        "mimeType": media_type,
        "originalMimeType": media_type,
        "fileName": original_name,
    }

# Alias without /api
@app.get("/documents/{document_id}/view-url")
async def view_document_alias(document_id: str, request: Request):
    return await view_document(document_id, request)


# Streaming content endpoint (mobile preview)
@app.get("/api/documents/{document_id}/content")
async def get_document_content(document_id: str, request: Request, format: str = "auto"):
    filename, file_path = _find_file_by_id(document_id)
    ext = os.path.splitext(filename)[1].lower()
    media_type = _guess_mime_type(filename)
    original_name = filename.split("_", 1)[1] if "_" in filename else filename

    if format not in ["auto", "pdf", "txt"]:
        raise HTTPException(status_code=400, detail="Invalid format")

    def pending_response(message: Optional[str] = None):
        return JSONResponse(
            status_code=409,
            content={
                "error": "Conversion not ready",
                "conversionStatus": "pending",
                "conversionError": message,
            },
        )

    # TXT preview
    if format == "txt" or (format == "auto" and ext in [".txt", ".csv", ".docx", ".xlsx"]):
        txt_path = _ensure_text_extract(document_id, file_path, ext)
        if txt_path and os.path.exists(txt_path):
            with open(txt_path, "rb") as f:
                data = f.read()
            return Response(content=data, media_type="text/plain")
        # OCR not configured for PDFs/images
        if ext in [".pdf", ".png", ".jpg", ".jpeg", ".gif", ".bmp"]:
            return pending_response("OCR not configured")

    # Image preview
    if format == "auto" and media_type.startswith("image/"):
        return FileResponse(file_path, media_type=media_type, filename=original_name)

    # PDF preview (auto or forced)
    if format in ["auto", "pdf"]:
        if ext == ".pdf":
            return _serve_file_with_range(request, file_path, "application/pdf", original_name)
        if ext in [".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx"]:
            pdf_path = _converted_pdf_path(document_id)
            if os.path.exists(pdf_path):
                return _serve_file_with_range(request, pdf_path, "application/pdf", original_name)
            # conversion not ready (or converter not configured)
            return pending_response("PDF conversion not ready")

    # Fallback: return raw bytes if directly viewable
    return FileResponse(file_path, media_type=media_type, filename=original_name)

# 3) direct file bytes (used by download-url)
@app.get("/api/documents/file/{filename}")
@app.get("/documents/file/{filename}")
async def serve_file_alias(filename: str):
    return await serve_file(filename)

async def serve_file(filename: str):
    file_path = os.path.join(UPLOAD_DIR, filename)
    if not os.path.isfile(file_path):
        raise HTTPException(status_code=404, detail="File not found")
    media_type = _guess_mime_type(filename)
    return FileResponse(
        file_path,
        media_type=media_type,
        filename=filename.split("_", 1)[1] if "_" in filename else filename,
    )

# -------- Upload URL flow (matches Flutter UploadService) --------
@app.post("/api/documents/upload-url")
@app.post("/documents/upload-url")
async def get_upload_url(request: Request):
    data = await request.json()
    file_name = (
        data.get("fileName")
        or data.get("file_name")
        or data.get("filename")
        or "document"
    )
    mime_type = data.get("mimeType") or data.get("mime_type")
    file_size = data.get("fileSize") or data.get("file_size") or data.get("size")

    document_id = str(uuid4())
    safe_name = _safe_filename(file_name)
    stored_name = f"{document_id}_{safe_name}"
    pending_uploads[document_id] = {
        "original_name": file_name,
        "stored_name": stored_name,
        "mime_type": mime_type,
        "file_size": file_size,
        "created_at": datetime.now().isoformat(),
    }

    return {
        "uploadUrl": f"/documents/upload/{document_id}",
        "documentId": document_id,
        "id": document_id,
    }

@app.post("/api/documents/bulk-upload-urls")
@app.post("/documents/bulk-upload-urls")
async def get_bulk_upload_urls(request: Request):
    data = await request.json()
    files = data.get("files") or []
    uploads = []
    for f in files:
        file_name = (
            f.get("fileName")
            or f.get("file_name")
            or f.get("filename")
            or "document"
        )
        mime_type = f.get("mimeType") or f.get("mime_type")
        file_size = f.get("fileSize") or f.get("file_size") or f.get("size")

        document_id = str(uuid4())
        safe_name = _safe_filename(file_name)
        stored_name = f"{document_id}_{safe_name}"
        pending_uploads[document_id] = {
            "original_name": file_name,
            "stored_name": stored_name,
            "mime_type": mime_type,
            "file_size": file_size,
            "created_at": datetime.now().isoformat(),
        }

        uploads.append(
            {
                "uploadUrl": f"/documents/upload/{document_id}",
                "documentId": document_id,
                "id": document_id,
                "fileName": file_name,
            }
        )

    return {"uploads": uploads}

@app.put("/api/documents/upload/{document_id}")
@app.put("/documents/upload/{document_id}")
async def upload_via_url(document_id: str, request: Request):
    meta = pending_uploads.get(document_id)
    if not meta:
        raise HTTPException(status_code=404, detail="Upload session not found")

    contents = await request.body()
    if not contents:
        raise HTTPException(status_code=400, detail="Empty upload body")

    stored_name = meta["stored_name"]
    file_path = os.path.join(UPLOAD_DIR, stored_name)
    with open(file_path, "wb") as f:
        f.write(contents)

    return {"status": "success", "documentId": document_id, "fileName": stored_name}

@app.post("/api/documents/{document_id}/confirm-upload")
@app.post("/documents/{document_id}/confirm-upload")
async def confirm_upload(document_id: str, request: Request):
    _ = await request.body()
    meta = pending_uploads.get(document_id)
    if not meta:
        raise HTTPException(status_code=404, detail="Upload session not found")

    stored_name = meta.get("stored_name")
    if stored_name:
        file_path = os.path.join(UPLOAD_DIR, stored_name)
        ext = os.path.splitext(stored_name)[1].lower()

        # Auto-trigger text extraction (for txt/csv/docx/xlsx)
        if ext in [".txt", ".csv", ".docx", ".xlsx"]:
            _ensure_text_extract(document_id, file_path, ext)

        # Conversion status tracking (PDF conversion for Office)
        if ext in [".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx"]:
            # PDF converter not configured in this backend
            _set_conversion_status(document_id, "pending", "PDF conversion not configured")
        else:
            _set_conversion_status(document_id, "completed", None)

    # Keep metadata for now; in real app, persist to DB
    return {"status": "success", "documentId": document_id}

# -------- Conversion / Preview helpers --------
@app.get("/conversion/{document_id}/status")
@app.get("/api/conversion/{document_id}/status")
async def get_conversion_status(document_id: str):
    pdf_path = _converted_pdf_path(document_id)
    if os.path.exists(pdf_path):
        return {"status": "completed", "message": "PDF ready"}
    status = _get_conversion_status(document_id)
    if status:
        return {"status": status["status"], "error": status.get("error"), "updated_at": status.get("updated_at")}
    return {"status": "pending", "message": "Conversion pending"}

@app.post("/conversion/{document_id}/convert")
@app.post("/api/conversion/{document_id}/convert")
async def conversion_request(document_id: str):
    _set_conversion_status(document_id, "pending", "PDF conversion not configured")
    return {"status": "queued"}

@app.get("/conversion/{document_id}/download/{format}")
@app.get("/api/conversion/{document_id}/download/{format}")
async def conversion_download(document_id: str, format: str):
    filename, file_path = _find_file_by_id(document_id)
    ext = os.path.splitext(filename)[1].lower()
    fmt = format.lower()

    if fmt == "pdf":
        if ext == ".pdf":
            return FileResponse(file_path, media_type="application/pdf", filename=filename)
        pdf_path = _converted_pdf_path(document_id)
        if os.path.exists(pdf_path):
            return FileResponse(pdf_path, media_type="application/pdf", filename=filename)
        raise HTTPException(status_code=409, detail="Conversion not ready")

    if fmt == "txt":
        txt_path = _ensure_text_extract(document_id, file_path, ext)
        if txt_path and os.path.exists(txt_path):
            with open(txt_path, "rb") as f:
                data = f.read()
            return Response(content=data, media_type="text/plain")

    raise HTTPException(status_code=415, detail="Conversion format not supported")

# Health Check Endpoint
@app.get("/api/health")
async def health_check():
    """
    Check if the API is running and healthy.
    """
    return {
        "status": "healthy",
        "service": "DigiSanchika API",
        "timestamp": datetime.now().isoformat(),
        "upload_dir_exists": os.path.exists(UPLOAD_DIR),
        "upload_dir": os.path.abspath(UPLOAD_DIR)
    }
# Folder model
class FolderCreate(BaseModel):
    name: str
    parent_id: Optional[str] = None

class FolderResponse(BaseModel):
    id: str
    name: str
    parent_id: Optional[str] = None
    created_at: str

# In-memory storage for folders (replace with database later)
folders_db = {}

# Folder endpoints
@app.post("/api/folders", response_model=FolderResponse)
async def create_folder(folder: FolderCreate):
    folder_id = str(datetime.now().timestamp()).replace('.', '')
    
    new_folder = {
        "id": folder_id,
        "name": folder.name,
        "parent_id": folder.parent_id,
        "created_at": datetime.now().isoformat()
    }
    
    folders_db[folder_id] = new_folder
    
    return new_folder

@app.get("/api/folders")
async def get_folders():
    return {
        "status": "success",
        "folders": list(folders_db.values())
    }

@app.get("/api/folders/{folder_id}")
async def get_folder(folder_id: str):
    if folder_id not in folders_db:
        raise HTTPException(status_code=404, detail="Folder not found")
    
    return {
        "status": "success",
        "folder": folders_db[folder_id]
    }

@app.delete("/api/folders/{folder_id}")
async def delete_folder(folder_id: str):
    if folder_id not in folders_db:
        raise HTTPException(status_code=404, detail="Folder not found")
    
    del folders_db[folder_id]
    
    return {
        "status": "success",
        "message": f"Folder {folder_id} deleted"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)

# Shared document model
class ShareDocumentRequest(BaseModel):
    document_id: str
    share_with_users: List[str]  # List of user emails or IDs
    permissions: str = "view"  # view, download, edit

class SharedDocument(BaseModel):
    id: str
    document_id: str
    shared_by: str
    shared_with: List[str]
    permissions: str
    shared_at: str

# In-memory storage for shared documents (replace with database later)
shared_documents_db = {}

# Share a document endpoint
@app.post("/api/share-document")
async def share_document(share_request: ShareDocumentRequest):
    share_id = str(datetime.now().timestamp()).replace('.', '')
    
    shared_document = {
        "id": share_id,
        "document_id": share_request.document_id,
        "shared_by": "current_user",  # In real app, get from auth
        "shared_with": share_request.share_with_users,
        "permissions": share_request.permissions,
        "shared_at": datetime.now().isoformat()
    }
    
    shared_documents_db[share_id] = shared_document
    
    return {
        "status": "success",
        "message": "Document shared successfully",
        "shared_document": shared_document
    }

# Get documents shared with me
@app.get("/api/shared-with-me")
async def get_shared_with_me():
    # In a real app, you would filter by current user
    # For now, return all shared documents
    shared_docs = list(shared_documents_db.values())
    
    # Get actual document details for each shared document
    documents_with_details = []
    
    for shared_doc in shared_docs:
        # Find the actual document
        document_id = shared_doc["document_id"]
        matching_files = []
        
        if os.path.exists(UPLOAD_DIR):
            for filename in os.listdir(UPLOAD_DIR):
                if filename.startswith(document_id):
                    file_path = os.path.join(UPLOAD_DIR, filename)
                    if os.path.isfile(file_path):
                        stat = os.stat(file_path)
                        documents_with_details.append({
                            "id": shared_doc["id"],
                            "document_id": document_id,
                            "filename": filename,
                            "original_name": filename.split('_', 1)[1] if '_' in filename else filename,
                            "size": stat.st_size,
                        "file_size_bytes": stat.st_size,
                            "upload_date": datetime.fromtimestamp(stat.st_ctime).isoformat(),
                        "created_at": datetime.fromtimestamp(stat.st_ctime).isoformat(),
                        "mime_type": _guess_mime_type(filename),
                            "file_type": os.path.splitext(filename)[1].lower().replace('.', '') or 'unknown',
                            "shared_by": shared_doc["shared_by"],
                            "shared_with": shared_doc["shared_with"],
                            "permissions": shared_doc["permissions"],
                            "shared_at": shared_doc["shared_at"]
                        })
    
    return {
        "status": "success",
        "count": len(documents_with_details),
        "documents": documents_with_details
    }

# Get documents I have shared
@app.get("/api/shared-by-me")
async def get_shared_by_me():
    # Filter documents shared by current user
    # For demo, return all shared documents
    shared_by_me = [doc for doc in shared_documents_db.values() 
                   if doc["shared_by"] == "current_user"]
    
    documents_with_details = []
    
    for shared_doc in shared_by_me:
        document_id = shared_doc["document_id"]
        
        if os.path.exists(UPLOAD_DIR):
            for filename in os.listdir(UPLOAD_DIR):
                if filename.startswith(document_id):
                    file_path = os.path.join(UPLOAD_DIR, filename)
                    if os.path.isfile(file_path):
                        stat = os.stat(file_path)
                        documents_with_details.append({
                            "id": shared_doc["id"],
                            "document_id": document_id,
                            "filename": filename,
                            "original_name": filename.split('_', 1)[1] if '_' in filename else filename,
                            "size": stat.st_size,
                        "file_size_bytes": stat.st_size,
                            "upload_date": datetime.fromtimestamp(stat.st_ctime).isoformat(),
                        "created_at": datetime.fromtimestamp(stat.st_ctime).isoformat(),
                        "mime_type": _guess_mime_type(filename),
                            "file_type": os.path.splitext(filename)[1].lower().replace('.', '') or 'unknown',
                            "shared_with": shared_doc["shared_with"],
                            "permissions": shared_doc["permissions"],
                            "shared_at": shared_doc["shared_at"]
                        })
    
    return {
        "status": "success",
        "count": len(documents_with_details),
        "documents": documents_with_details
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)




























