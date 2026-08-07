import { useState } from "react";
import { getQualityScore } from "../qualityScores";
import type { Backend, MigrationResult } from "../types";
import { getPillarSteps, PILLARS } from "../types";
import CodeBlock from "./CodeBlock";
import MarkdownBlock from "./MarkdownBlock";
import QualityScorePanel from "./QualityScorePanel";
import StatusBadge from "./StatusBadge";
import DeploymentPanel from "./DeploymentPanel";
import TestExecutionPanel from "./TestExecutionPanel";
import TracesPanel from "./TracesPanel";

interface Props {
  backend: Backend;
  result: MigrationResult | undefined;
  stem: string;
  filename: string;
  isMaximized: boolean;
  isHidden: boolean;
  onToggleMaximize: () => void;
  onRefreshResults: () => void;
}

const BACKEND_LABEL: Record<Backend, string> = {
  azure: "Azure OpenAI",
  gemini: "Google · gemini-3.1-flash-lite",
};

const EXTRA_TABS = [
  { key: "quality_score", label: "Quality Score" },
  { key: "test_execution", label: "Test Execution" },
  { key: "deployment", label: "Deployment" },
  { key: "traces", label: "Traces" },
  { key: "refinement_log", label: "Refinement Log" },
];

export default function BackendColumn({
  backend,
  result,
  stem,
  filename,
  isMaximized,
  isHidden,
  onToggleMaximize,
  onRefreshResults,
}: Props) {
  const [activeTab, setActiveTab] = useState<string>("java_code");

  if (isHidden) return null;

  const pillar = PILLARS.find((p) => p.key === activeTab);
  const value = result ? (result as any)[activeTab] : null;
  const steps = getPillarSteps(result);
  const activeStep = steps.find((s) => s.state === "active");
  const status = result?.status || "idle";
  const score = getQualityScore(backend, stem);

  let liveLabel: string | null = null;
  if (status === "queued") liveLabel = "Queued…";
  else if (status.startsWith("refining")) liveLabel = status.replace("refining", "Refining");
  else if (activeStep) liveLabel = `Running · ${activeStep.label}…`;

  return (
    <div className={`backend-column ${isMaximized ? "column-maximized" : ""}`}>
      <div className="backend-column-header">
        <div>
          <div className="backend-name">{backend === "azure" ? "Azure OpenAI" : "Gemini"}</div>
          <div className="backend-model">
            {backend === "azure" && result?.model_used ? result.model_used : BACKEND_LABEL[backend]}
          </div>
        </div>
        <div className="header-right">
          {score && (
            <span className="mini-score-badge" title={score.verdict}>
              {score.overall.toFixed(1)}/10
            </span>
          )}
          <StatusBadge status={result?.status} />
          <button className="panel-toggle-btn" onClick={onToggleMaximize} title={isMaximized ? "Restore" : "Maximize"}>
            {isMaximized ? "⤡" : "⤢"}
          </button>
        </div>
      </div>

      {liveLabel && (
        <div className="live-progress">
          <span className="live-dot" />
          {liveLabel}
        </div>
      )}

      <div className="step-tracker">
        {steps.map((s) => (
          <div key={s.key} className={`step-dot step-${s.state}`} title={`${s.label} — ${s.state}`} />
        ))}
      </div>

      <div className="tab-bar">
        {PILLARS.map((p) => {
          const step = steps.find((s) => s.key === p.key)!;
          return (
            <button
              key={p.key}
              className={`tab-button ${activeTab === p.key ? "active" : ""}`}
              onClick={() => setActiveTab(p.key)}
              title={p.pillar}
            >
              <span className={`tab-status-dot tab-status-${step.state}`} />
              {p.label}
            </button>
          );
        })}
        {EXTRA_TABS.map((t) => (
          <button
            key={t.key}
            className={`tab-button ${activeTab === t.key ? "active" : ""}`}
            onClick={() => setActiveTab(t.key)}
          >
            {t.label}
          </button>
        ))}
      </div>
      <div className="pillar-caption">
        {pillar ? pillar.pillar : "Continuous Optimization"}
      </div>

      <div className="pane-content">
        {activeTab === "java_code" && <CodeBlock code={value || ""} language="java" />}
        {activeTab === "python_code" && <CodeBlock code={value || ""} language="python" />}
        {(activeTab === "functional_spec" ||
          activeTab === "dependency_map" ||
          activeTab === "test_cases" ||
          activeTab === "equivalence_review" ||
          activeTab === "refinement_log") && <MarkdownBlock content={value} />}
        {activeTab === "quality_score" && (
          <QualityScorePanel score={score} codeUpdatedAt={result?.updated_at} status={status} />
        )}
        {activeTab === "test_execution" && (
          <TestExecutionPanel
            backend={backend}
            filename={filename}
            result={result}
            onRefresh={onRefreshResults}
          />
        )}
        {activeTab === "deployment" && (
          <DeploymentPanel
            backend={backend}
            filename={filename}
            result={result}
            onRefresh={onRefreshResults}
          />
        )}
        {activeTab === "traces" && (
          <TracesPanel backend={backend} filename={filename} refreshKey={result?.updated_at || ""} />
        )}
      </div>
    </div>
  );
}
