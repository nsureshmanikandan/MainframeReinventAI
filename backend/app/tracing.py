"""OpenTelemetry tracing for the modernization pipeline.

Uses the real OpenTelemetry SDK (TracerProvider + a custom SpanExporter) so
spans follow the standard OTel data model (trace_id, span_id, parent,
attributes, status). There is no collector/Jaeger in this environment, so
spans are exported to both the console (structured logs, correlated by
trace/span id) and to SQLite, so the frontend can render a per-run trace
waterfall without standing up separate tracing infrastructure.
"""

import json
import logging
import time
from contextlib import contextmanager

from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import (
    SimpleSpanProcessor,
    SpanExporter,
    SpanExportResult,
)
from opentelemetry.trace import Status, StatusCode

from . import db

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("mainframe_reinvent")


class SqliteSpanExporter(SpanExporter):
    """Persists finished spans into the `spans` table.

    mfr.filename / mfr.backend attributes (set by every traced_stage call)
    are pulled out into their own indexed-by-query columns so the frontend
    can fetch a single program's trace without scanning every span ever
    recorded.
    """

    def export(self, spans):
        for span in spans:
            attrs = dict(span.attributes or {})
            filename = attrs.get("mfr.filename", "")
            backend = attrs.get("mfr.backend", "")
            start = span.start_time / 1e9
            end = span.end_time / 1e9
            db.insert_span(
                filename=filename,
                backend=backend,
                trace_id=format(span.context.trace_id, "032x"),
                span_id=format(span.context.span_id, "016x"),
                parent_span_id=format(span.parent.span_id, "016x") if span.parent else None,
                name=span.name,
                start_time=start,
                end_time=end,
                duration_ms=(end - start) * 1000,
                status="error" if span.status.status_code == StatusCode.ERROR else "ok",
                attributes=json.dumps(attrs, default=str),
            )
        return SpanExportResult.SUCCESS

    def shutdown(self):
        pass

    def force_flush(self, timeout_millis: int = 30000) -> bool:
        return True


_provider = TracerProvider(
    resource=Resource.create({"service.name": "mainframe-reinvent-ai"})
)
_provider.add_span_processor(SimpleSpanProcessor(SqliteSpanExporter()))
trace.set_tracer_provider(_provider)

tracer = trace.get_tracer("mainframe_reinvent")


@contextmanager
def traced_stage(name: str, filename: str, backend: str, **attrs):
    """Wraps one pipeline stage (a pillar call, a test run, ...) in an OTel
    span, nested automatically under whatever span is currently active."""
    with tracer.start_as_current_span(name) as span:
        span.set_attribute("mfr.filename", filename)
        span.set_attribute("mfr.backend", backend)
        for key, value in attrs.items():
            span.set_attribute(f"mfr.{key}", "" if value is None else str(value))

        start = time.time()
        logger.info(
            "stage_start name=%s filename=%s backend=%s attrs=%s",
            name, filename, backend, attrs,
        )
        try:
            yield span
        except Exception as exc:  # noqa: BLE001 - re-raised after recording
            span.set_status(Status(StatusCode.ERROR, str(exc)))
            logger.error(
                "stage_error name=%s filename=%s backend=%s error=%s",
                name, filename, backend, exc,
            )
            raise
        else:
            duration_ms = (time.time() - start) * 1000
            logger.info(
                "stage_end name=%s filename=%s backend=%s duration_ms=%.1f",
                name, filename, backend, duration_ms,
            )
