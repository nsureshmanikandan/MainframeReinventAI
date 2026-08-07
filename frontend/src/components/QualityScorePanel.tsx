import type { QualityScore } from "../qualityScores";

interface Props {
  score: QualityScore | undefined;
  codeUpdatedAt?: string | null;
  status?: string;
}

const ROWS: { key: keyof QualityScore; label: string }[] = [
  { key: "businessRuleFidelity", label: "Business Rule Fidelity" },
  { key: "financialPrecision", label: "Financial Precision" },
  { key: "completeness", label: "Completeness" },
  { key: "codeQuality", label: "Code Quality" },
  { key: "productionReadiness", label: "Production Readiness" },
];

function barColor(score: number): string {
  if (score >= 8) return "var(--success)";
  if (score >= 5) return "var(--warning)";
  return "var(--danger)";
}

export default function QualityScorePanel({ score, codeUpdatedAt, status }: Props) {
  if (!score) {
    return (
      <div className="empty-state">
        No independent audit score recorded yet for this program/backend.
      </div>
    );
  }

  // A run currently in flight has already cleared/is overwriting the code
  // this score was verified against -- flag it regardless of timestamps,
  // since "in progress" always means "not yet verified."
  const isInFlight = Boolean(
    status && status !== "completed" && !status.startsWith("error")
  );

  // Date-only comparison has a same-day blind spot (a re-run today can't be
  // detected against an audit dated "today"), so isInFlight above is the
  // primary signal. This timestamp check catches staleness on later days.
  const isStaleByDate = Boolean(
    codeUpdatedAt && new Date(codeUpdatedAt) > new Date(score.auditedAt + "T23:59:59Z")
  );

  return (
    <div className="quality-panel">
      {isInFlight && (
        <div className="quality-stale-banner">
          ⚠ A migration/refine run is currently in progress ({status}) — the code is being
          rewritten right now. The score below is from the last completed run and does not
          reflect what's generating.
        </div>
      )}
      {!isInFlight && isStaleByDate && (
        <div className="quality-stale-banner">
          ⚠ Code was re-run or refined after this audit (last audited {score.auditedAt}) —
          this score may no longer reflect the current code. Ask for a fresh review.
        </div>
      )}

      <div className="quality-overall">
        <span className="quality-overall-number" style={{ color: barColor(score.overall) }}>
          {score.overall.toFixed(1)}
        </span>
        <span className="quality-overall-label">/ 10 overall</span>
      </div>

      {ROWS.map((r) => (
        <div key={r.key} className="quality-row">
          <div className="quality-row-label">{r.label}</div>
          <div className="quality-bar-track">
            <div
              className="quality-bar-fill"
              style={{
                width: `${(score[r.key] as number) * 10}%`,
                background: barColor(score[r.key] as number),
              }}
            />
          </div>
          <div className="quality-row-value">{score[r.key]}/10</div>
        </div>
      ))}

      <div className="quality-verdict">
        <strong>Auditor's note</strong> (as of {score.auditedAt}): {score.verdict}
      </div>
    </div>
  );
}
