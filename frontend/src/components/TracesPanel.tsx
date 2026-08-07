import { useEffect, useState } from "react";
import { getTraces } from "../api";
import type { Backend, TraceSpan } from "../types";

interface Props {
  backend: Backend;
  filename: string;
  refreshKey: string;
}

export default function TracesPanel({ backend, filename, refreshKey }: Props) {
  const [spans, setSpans] = useState<TraceSpan[]>([]);
  const [loading, setLoading] = useState(false);

  async function load() {
    setLoading(true);
    try {
      const s = await getTraces(filename, backend);
      setSpans(s);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filename, backend, refreshKey]);

  if (spans.length === 0) {
    return (
      <div className="eval-panel">
        <button className="run-button" onClick={load} disabled={loading}>
          {loading ? "Loading…" : "Refresh Traces"}
        </button>
        <div className="empty-state">
          No OpenTelemetry spans recorded yet for this program/backend. Run a migration, refine,
          or test execution to generate a trace.
        </div>
      </div>
    );
  }

  const minStart = Math.min(...spans.map((s) => s.start_time));
  const maxEnd = Math.max(...spans.map((s) => s.end_time));
  const totalMs = (maxEnd - minStart) * 1000 || 1;

  const byId = new Map(spans.map((s) => [s.span_id, s]));
  function depthOf(span: TraceSpan): number {
    let depth = 0;
    let current: TraceSpan | undefined = span;
    while (current?.parent_span_id) {
      current = byId.get(current.parent_span_id);
      if (!current) break;
      depth += 1;
    }
    return depth;
  }

  return (
    <div className="eval-panel">
      <div className="eval-panel-header">
        <button className="run-button" onClick={load} disabled={loading}>
          {loading ? "Loading…" : "Refresh Traces"}
        </button>
        <span className="eval-status-label">{spans.length} spans</span>
      </div>
      <p className="eval-caveat-line">
        Real OpenTelemetry spans (TracerProvider + SDK), exported to SQLite in this environment
        instead of a Jaeger/OTLP collector. Each row is one pipeline stage; nested stages are
        indented by their trace hierarchy.
      </p>
      <div className="trace-waterfall">
        {spans.map((s) => {
          const offsetPct = (((s.start_time - minStart) * 1000) / totalMs) * 100;
          const widthPct = Math.max((s.duration_ms / totalMs) * 100, 0.4);
          const depth = depthOf(s);
          return (
            <div key={s.id} className="trace-row">
              <div
                className="trace-row-label"
                style={{ paddingLeft: `${depth * 14}px` }}
                title={s.attributes}
              >
                {s.name}
              </div>
              <div className="trace-row-track">
                <div
                  className={`trace-row-bar ${s.status === "error" ? "trace-bar-error" : ""}`}
                  style={{ marginLeft: `${offsetPct}%`, width: `${widthPct}%` }}
                  title={`${s.duration_ms.toFixed(1)}ms`}
                />
              </div>
              <div className="trace-row-duration">{s.duration_ms.toFixed(0)}ms</div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
