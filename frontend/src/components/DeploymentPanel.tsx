import { useEffect, useState } from "react";
import { downloadWrapperUrl, getDeploymentStyle, triggerGenerateWrapper } from "../api";
import type { Backend, DeploymentStyle, MigrationResult } from "../types";
import CodeBlock from "./CodeBlock";

interface Props {
  backend: Backend;
  filename: string;
  result: MigrationResult | undefined;
  onRefresh: () => void;
}

export default function DeploymentPanel({ backend, filename, result, onRefresh }: Props) {
  const [starting, setStarting] = useState(false);
  const [style, setStyle] = useState<DeploymentStyle | null>(null);
  const status = result?.wrapper_status || "";

  useEffect(() => {
    getDeploymentStyle(filename).then(setStyle).catch(() => setStyle(null));
  }, [filename]);

  useEffect(() => {
    if (status !== "running") return;
    const interval = window.setInterval(onRefresh, 2000);
    return () => window.clearInterval(interval);
  }, [status, onRefresh]);

  async function run() {
    setStarting(true);
    try {
      await triggerGenerateWrapper(filename, backend);
      onRefresh();
    } catch (e) {
      alert((e as Error).message);
    } finally {
      setStarting(false);
    }
  }

  const isRunning = starting || status === "running";
  const isError = status.startsWith("error");
  const hasPython = Boolean(result?.python_wrapper);
  const hasJava = Boolean(result?.java_wrapper);

  return (
    <div className="eval-panel">
      <div className="eval-panel-header">
        <button
          className="run-button"
          onClick={run}
          disabled={isRunning || !(result?.python_code || result?.java_code)}
        >
          {isRunning ? "Generating…" : "Generate Deployment Wrapper"}
        </button>
        {isError && <span className="eval-status-label eval-status-error">{status}</span>}
      </div>

      {style && (
        <div className={`deployment-style-badge deployment-style-${style.style}`}>
          {style.style === "api" ? "ONLINE / REST API" : "BATCH JOB"}
          <span className="deployment-style-reason"> — {style.reason}</span>
        </div>
      )}

      <p className="eval-caveat-line">
        {!style
          ? "Loading deployment classification…"
          : style.style === "api"
          ? "Generates a real FastAPI microservice wrapping the Python conversion (runnable with `python <file>`), plus Spring Boot REST controller source for Java (not compiled here — no JDK)."
          : "Generates a real batch script wrapping the Python conversion (runnable with `python <file> --input records.csv --output results.csv`), plus a Spring Boot batch-runner source for Java (not compiled here — no JDK)."}
      </p>

      {!hasPython && !hasJava && !isRunning && (
        <div className="empty-state">
          No deployment wrapper generated yet. Click "Generate Deployment Wrapper" above.
        </div>
      )}

      {hasPython && (
        <div className="eval-section">
          <div className="eval-panel-header">
            <h4 style={{ margin: 0 }}>Python wrapper (real, runnable)</h4>
            <a
              className="export-button"
              href={downloadWrapperUrl(filename, backend, "python")}
              download
            >
              Download .py
            </a>
          </div>
          <CodeBlock code={result?.python_wrapper || ""} language="python" />
        </div>
      )}

      {hasJava && (
        <div className="eval-section">
          <div className="eval-panel-header">
            <h4 style={{ margin: 0 }}>Java wrapper (source only — no JDK in this environment)</h4>
            <a
              className="export-button"
              href={downloadWrapperUrl(filename, backend, "java")}
              download
            >
              Download .java
            </a>
          </div>
          <CodeBlock code={result?.java_wrapper || ""} language="java" />
        </div>
      )}
    </div>
  );
}
