"""FastAPI backend for the Mainframe Reinvent AI PoC.

Mirrors the 5-pillar Agentic Modernization flow (Legacy Understanding, Code
Modernization, Robust Testing, Rapid Modernization, Continuous Optimization)
over sample COBOL programs, using Azure OpenAI (gpt-5.4-mini) and/or Gemini
side by side.
"""

import io
import json
import pathlib
import threading
import zipfile

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from . import db, test_execution, tracing
from .known_issues import get_known_issues
from .llm_clients import AVAILABLE_AZURE_MODELS, AZURE_DEFAULT_MODEL, BACKENDS, GEMINI_MODEL
from .prompts import PROMPTS, extract_code_block

INPUT_DIR = pathlib.Path(__file__).parent.parent / "input_cobol"

app = FastAPI(title="Mainframe Reinvent AI")

app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1):\d+",
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def on_startup():
    db.init_db()


class MigrateRequest(BaseModel):
    filename: str
    backend: str  # "azure" | "gemini" | "both"
    azure_model: str = AZURE_DEFAULT_MODEL


class RefineRequest(BaseModel):
    filename: str
    backend: str  # "azure" | "gemini" | "both"
    cycles: int = 2
    azure_model: str = AZURE_DEFAULT_MODEL


def run_pillar(call_fn, code: str, prompt_key: str, max_tokens: int = 8000, model: str | None = None, **extra):
    prompt = PROMPTS[prompt_key].format(code=code, **extra)
    text, err = call_fn(prompt, max_tokens=max_tokens, model=model)
    return text, err


def run_migration(filename: str, backend_name: str, azure_model: str = AZURE_DEFAULT_MODEL):
    cbl_path = INPUT_DIR / filename
    code = cbl_path.read_text(encoding="utf-8")
    call_fn = BACKENDS[backend_name]
    model = azure_model if backend_name == "azure" else GEMINI_MODEL

    db.upsert_result(filename, backend_name, status="running", model_used=model)

    with tracing.traced_stage("migration", filename, backend_name, model=model):
        with tracing.traced_stage("functional_spec", filename, backend_name, model=model):
            spec, err = run_pillar(call_fn, code, "functional_spec", model=model)
        if err:
            db.upsert_result(filename, backend_name, status=f"error: {err}")
            return
        db.upsert_result(filename, backend_name, status="running", functional_spec=spec)

        with tracing.traced_stage("dependency_map", filename, backend_name, model=model):
            dep_map, err = run_pillar(call_fn, code, "dependency_map", model=model)
        db.upsert_result(
            filename, backend_name, status="running", dependency_map=dep_map or ""
        )

        with tracing.traced_stage("test_cases", filename, backend_name, model=model):
            tests, err = run_pillar(call_fn, code, "test_cases", model=model)
        db.upsert_result(filename, backend_name, status="running", test_cases=tests or "")

        with tracing.traced_stage("convert_java", filename, backend_name, model=model):
            java_raw, err = run_pillar(call_fn, code, "convert_java", max_tokens=12000, model=model)
        java_code = extract_code_block(java_raw)
        db.upsert_result(filename, backend_name, status="running", java_code=java_code)

        with tracing.traced_stage("convert_python", filename, backend_name, model=model):
            py_raw, err = run_pillar(call_fn, code, "convert_python", max_tokens=12000, model=model)
        python_code = extract_code_block(py_raw)
        db.upsert_result(
            filename, backend_name, status="running", python_code=python_code
        )

        if java_code:
            with tracing.traced_stage("equivalence_review", filename, backend_name, model=model):
                review, err = run_pillar(
                    call_fn, code, "equivalence_review", model=model, converted_code=java_code
                )
            db.upsert_result(
                filename, backend_name, status="completed", equivalence_review=review or ""
            )
        else:
            db.upsert_result(filename, backend_name, status="completed")


def refine_migration(filename: str, backend_name: str, cycles: int, azure_model: str = AZURE_DEFAULT_MODEL):
    stem = pathlib.Path(filename).stem
    cbl_path = INPUT_DIR / filename
    code = cbl_path.read_text(encoding="utf-8")
    call_fn = BACKENDS[backend_name]
    model = azure_model if backend_name == "azure" else GEMINI_MODEL
    known_issues = get_known_issues(backend_name, stem)

    result = db.get_result(filename, backend_name) or {}
    java_code = result.get("java_code") or ""
    python_code = result.get("python_code") or ""
    equivalence_review = result.get("equivalence_review") or "(none yet)"
    log_entries = [result.get("refinement_log") or ""]

    db.upsert_result(filename, backend_name, status="refining", model_used=model)

    with tracing.traced_stage("refine", filename, backend_name, model=model, cycles=cycles):
        for cycle in range(1, cycles + 1):
            cycle_notes = [f"## Refinement Cycle {cycle}"]

            with tracing.traced_stage(f"refine_cycle_{cycle}", filename, backend_name, model=model):
                if java_code:
                    db.upsert_result(
                        filename, backend_name,
                        status=f"refining · cycle {cycle}/{cycles} · Java",
                    )
                    with tracing.traced_stage("refine_java", filename, backend_name, model=model):
                        raw, err = run_pillar(
                            call_fn, code, "refine_code", max_tokens=12000, model=model,
                            language="Java", current_code=java_code,
                            known_issues=known_issues, equivalence_review=equivalence_review,
                        )
                    if not err:
                        java_code = extract_code_block(raw)
                        db.upsert_result(filename, backend_name, status="refining", java_code=java_code)
                        cycle_notes.append("- Regenerated Java against known issues + equivalence review.")
                    else:
                        cycle_notes.append(f"- Java refinement skipped ({err}).")

                if python_code:
                    db.upsert_result(
                        filename, backend_name,
                        status=f"refining · cycle {cycle}/{cycles} · Python",
                    )
                    with tracing.traced_stage("refine_python", filename, backend_name, model=model):
                        raw, err = run_pillar(
                            call_fn, code, "refine_code", max_tokens=12000, model=model,
                            language="Python", current_code=python_code,
                            known_issues=known_issues, equivalence_review=equivalence_review,
                        )
                    if not err:
                        python_code = extract_code_block(raw)
                        db.upsert_result(filename, backend_name, status="refining", python_code=python_code)
                        cycle_notes.append("- Regenerated Python against known issues + equivalence review.")
                    else:
                        cycle_notes.append(f"- Python refinement skipped ({err}).")

                # Re-check equivalence against the refined Java so cycle N+1 (and
                # the UI) sees whether this pass actually resolved anything.
                if java_code:
                    db.upsert_result(
                        filename, backend_name,
                        status=f"refining · cycle {cycle}/{cycles} · re-checking equivalence",
                    )
                    with tracing.traced_stage("recheck_equivalence", filename, backend_name, model=model):
                        review_raw, err = run_pillar(
                            call_fn, code, "equivalence_review", model=model, converted_code=java_code
                        )
                    if not err:
                        equivalence_review = review_raw or equivalence_review
                        cycle_notes.append("- Re-ran equivalence review on the refined code.")

            log_entries.append("\n".join(cycle_notes))

    db.upsert_result(
        filename, backend_name,
        status="completed",
        java_code=java_code,
        python_code=python_code,
        equivalence_review=equivalence_review,
        refinement_log="\n\n".join(e for e in log_entries if e),
    )


def run_test_execution(filename: str, backend_name: str):
    cbl_path = INPUT_DIR / filename
    code = cbl_path.read_text(encoding="utf-8")
    call_fn = BACKENDS[backend_name]
    result = db.get_result(filename, backend_name) or {}
    model = result.get("model_used")
    python_code = result.get("python_code") or ""

    py_tests = result.get("python_tests") or ""
    py_results = None

    with tracing.traced_stage("test_execution", filename, backend_name, model=model):
        if python_code:
            if not py_tests:
                with tracing.traced_stage("generate_pytest", filename, backend_name, model=model):
                    raw, err = run_pillar(
                        call_fn, code, "pytest_tests", max_tokens=6000, model=model,
                        converted_code=python_code,
                    )
                py_tests = extract_code_block(raw) if raw else ""
                if not py_tests and err:
                    db.upsert_result(
                        filename, backend_name, status=result.get("status", "completed"),
                        test_execution_status=f"error: {err}",
                    )
                    return

            with tracing.traced_stage("run_pytest", filename, backend_name, model=model):
                py_results = test_execution.execute_python_tests(python_code, py_tests)

    db.upsert_result(
        filename, backend_name, status=result.get("status", "completed"),
        test_execution_status="completed",
        python_tests=py_tests,
        python_test_results=json.dumps(py_results) if py_results else "",
    )


@app.get("/api/health")
def health():
    return {"status": "ok"}


class InputDirRequest(BaseModel):
    path: str


@app.get("/api/config/input-dir")
def get_input_dir():
    return {"path": str(INPUT_DIR), "file_count": len(list(INPUT_DIR.glob("*.cbl")))}


@app.post("/api/config/input-dir")
def set_input_dir(req: InputDirRequest):
    global INPUT_DIR
    new_dir = pathlib.Path(req.path)
    if not new_dir.exists() or not new_dir.is_dir():
        raise HTTPException(status_code=400, detail=f"Not a valid directory: {req.path}")
    INPUT_DIR = new_dir
    cbl_files = list(INPUT_DIR.glob("*.cbl"))
    return {"path": str(INPUT_DIR), "file_count": len(cbl_files)}


@app.get("/api/files")
def list_files():
    files = []
    for cbl in sorted(INPUT_DIR.glob("*.cbl")):
        files.append(
            {
                "filename": cbl.name,
                "size_bytes": cbl.stat().st_size,
            }
        )
    return files


@app.get("/api/files/{filename}/source")
def get_source(filename: str):
    cbl_path = INPUT_DIR / filename
    if not cbl_path.exists():
        raise HTTPException(status_code=404, detail="File not found")
    return {"filename": filename, "source": cbl_path.read_text(encoding="utf-8")}


@app.post("/api/migrate")
def migrate(req: MigrateRequest):
    cbl_path = INPUT_DIR / req.filename
    if not cbl_path.exists():
        raise HTTPException(status_code=404, detail="File not found")

    backend_names = list(BACKENDS.keys()) if req.backend == "both" else [req.backend]
    if any(b not in BACKENDS for b in backend_names):
        raise HTTPException(status_code=400, detail="Unknown backend")

    # Each backend gets its own OS thread so Azure and Gemini genuinely run
    # concurrently -- FastAPI's BackgroundTasks would run them sequentially.
    for backend_name in backend_names:
        # Clear the previous run's output so the UI doesn't show stale
        # "done" content (and a stale Quality Score) sitting next to a
        # RUNNING badge -- each field goes back to empty until this run
        # actually produces it.
        db.upsert_result(
            req.filename, backend_name, status="queued",
            functional_spec="", dependency_map="", test_cases="",
            java_code="", python_code="", equivalence_review="",
            refinement_log="", python_tests="", python_test_results="",
            test_execution_status="",
        )
        db.clear_spans(req.filename, backend_name)
        threading.Thread(
            target=run_migration,
            args=(req.filename, backend_name, req.azure_model),
            daemon=True,
        ).start()

    return {"status": "started", "backends": backend_names, "azure_model": req.azure_model}


@app.get("/api/azure-models")
def get_azure_models():
    return AVAILABLE_AZURE_MODELS


@app.post("/api/refine")
def refine(req: RefineRequest):
    cbl_path = INPUT_DIR / req.filename
    if not cbl_path.exists():
        raise HTTPException(status_code=404, detail="File not found")

    backend_names = list(BACKENDS.keys()) if req.backend == "both" else [req.backend]
    if any(b not in BACKENDS for b in backend_names):
        raise HTTPException(status_code=400, detail="Unknown backend")
    cycles = max(1, min(3, req.cycles))

    for backend_name in backend_names:
        existing = db.get_result(req.filename, backend_name)
        if not existing or not (existing.get("java_code") or existing.get("python_code")):
            raise HTTPException(
                status_code=400,
                detail=f"Run a migration for {backend_name} before refining it",
            )
        threading.Thread(
            target=refine_migration,
            args=(req.filename, backend_name, cycles, req.azure_model),
            daemon=True,
        ).start()

    return {"status": "started", "backends": backend_names, "cycles": cycles}


@app.get("/api/results/{filename}")
def get_results(filename: str):
    return db.get_all_results(filename)


class TestExecutionRequest(BaseModel):
    filename: str
    backend: str  # "azure" | "gemini" | "both"


@app.post("/api/execute-tests")
def execute_tests(req: TestExecutionRequest):
    cbl_path = INPUT_DIR / req.filename
    if not cbl_path.exists():
        raise HTTPException(status_code=404, detail="File not found")

    backend_names = list(BACKENDS.keys()) if req.backend == "both" else [req.backend]
    if any(b not in BACKENDS for b in backend_names):
        raise HTTPException(status_code=400, detail="Unknown backend")

    for backend_name in backend_names:
        existing = db.get_result(req.filename, backend_name)
        if not existing or not existing.get("python_code"):
            raise HTTPException(
                status_code=400,
                detail=f"Run a migration for {backend_name} before executing tests",
            )
        db.upsert_result(
            req.filename, backend_name, status=existing["status"],
            test_execution_status="running",
        )
        threading.Thread(
            target=run_test_execution,
            args=(req.filename, backend_name),
            daemon=True,
        ).start()

    return {"status": "started", "backends": backend_names}


@app.get("/api/traces/{filename}")
def get_traces(filename: str, backend: str | None = None):
    return db.get_spans(filename, backend)


def _java_class_name(stem: str) -> str:
    return "".join(part.capitalize() for part in stem.split("_"))


def _add_result_to_zip(zf: zipfile.ZipFile, stem: str, backend_name: str, result: dict):
    base = f"{backend_name}/{stem}"
    docs = {
        "functional_spec": f"{stem}_functional_spec.md",
        "dependency_map": f"{stem}_dependency_map.md",
        "test_cases": f"{stem}_test_cases.md",
        "equivalence_review": f"{stem}_equivalence_review.md",
        "refinement_log": f"{stem}_refinement_log.md",
    }
    for field, doc_name in docs.items():
        if result.get(field):
            zf.writestr(f"{base}/docs/{doc_name}", result[field])

    if result.get("java_code"):
        class_name = _java_class_name(stem)
        zf.writestr(f"{base}/java/com/amex/modernized/{class_name}.java", result["java_code"])

    if result.get("python_code"):
        zf.writestr(f"{base}/python/{stem.lower()}.py", result["python_code"])


@app.get("/api/export/{filename}")
def export_file(filename: str, backend: str = "both"):
    cbl_path = INPUT_DIR / filename
    if not cbl_path.exists():
        raise HTTPException(status_code=404, detail="File not found")

    backend_names = list(BACKENDS.keys()) if backend == "both" else [backend]
    stem = pathlib.Path(filename).stem
    results = db.get_all_results(filename)

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr(f"original_cobol/{filename}", cbl_path.read_text(encoding="utf-8"))
        for backend_name in backend_names:
            result = results.get(backend_name)
            if result:
                _add_result_to_zip(zf, stem, backend_name, result)
    buf.seek(0)

    return StreamingResponse(
        buf,
        media_type="application/zip",
        headers={"Content-Disposition": f'attachment; filename="{stem}_modernized.zip"'},
    )


@app.get("/api/export-all")
def export_all():
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for cbl in sorted(INPUT_DIR.glob("*.cbl")):
            stem = cbl.stem
            zf.writestr(f"original_cobol/{cbl.name}", cbl.read_text(encoding="utf-8"))
            results = db.get_all_results(cbl.name)
            for backend_name, result in results.items():
                _add_result_to_zip(zf, stem, backend_name, result)
    buf.seek(0)

    return StreamingResponse(
        buf,
        media_type="application/zip",
        headers={
            "Content-Disposition": 'attachment; filename="mainframe_reinvent_export.zip"'
        },
    )
