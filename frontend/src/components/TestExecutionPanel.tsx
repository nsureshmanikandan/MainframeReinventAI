import { useEffect, useState } from "react";
import { triggerTestExecution } from "../api";
import type { Backend, MigrationResult, PythonTestResults } from "../types";

interface Props {
  backend: Backend;
  filename: string;
  result: MigrationResult | undefined;
  onRefresh: () => void;
}

export default function TestExecutionPanel({ backend, filename, result, onRefresh }: Props) {
  const [starting, setStarting] = useState(false);
  const status = result?.test_execution_status || "";

  useEffect(() => {
    if (status !== "running") return;
    const interval = window.setInterval(onRefresh, 2000);
    return () => window.clearInterval(interval);
  }, [status, onRefresh]);

  async function run() {
    setStarting(true);
    try {
      await triggerTestExecution(filename, backend);
      onRefresh();
    } catch (e) {
      alert((e as Error).message);
    } finally {
      setStarting(false);
    }
  }

  const pyResults: PythonTestResults | null = result?.python_test_results
    ? JSON.parse(result.python_test_results)
    : null;
  const isRunning = starting || status === "running";
  const isError = status.startsWith("error");

  return (
    <div className="eval-panel">
      <div className="eval-panel-header">
        <button className="run-button" onClick={run} disabled={isRunning || !result?.python_code}>
          {isRunning ? "Running Tests…" : "Run Tests"}
        </button>
        {isError && <span className="eval-status-label eval-status-error">{status}</span>}
      </div>

      <p className="eval-caveat-line">
        Generates a real pytest file for the Python conversion and actually executes it in a
        subprocess — this is genuine pass/fail, not a self-reported score. (Java/JUnit execution
        isn't available: this environment has no JDK installed.)
      </p>

      {!pyResults && !isRunning && (
        <div className="empty-state">
          No test execution recorded yet. Click "Run Tests" to generate and run pytest against the
          Python conversion.
        </div>
      )}

      {pyResults && (
        <div className="eval-section">
          <h4>Python (pytest — actually executed)</h4>
          {pyResults.executed ? (
            <>
              <div className={`test-summary-line ${pyResults.failed > 0 ? "has-failures" : "all-passed"}`}>
                {pyResults.passed}/{pyResults.total} passed
              </div>
              {pyResults.total === 0 && (
                <div className="empty-state">
                  pytest collected zero tests — the generated test file may have a syntax or
                  import error. See raw output below.
                </div>
              )}
              <ul className="test-case-list">
                {pyResults.tests.map((t) => (
                  <li key={t.name} className={t.outcome === "PASSED" ? "test-pass" : "test-fail"}>
                    {t.outcome === "PASSED" ? "✓" : "✗"} {t.name}
                  </li>
                ))}
              </ul>
              {pyResults.raw_output && (
                <details className="raw-output-details">
                  <summary>Raw pytest output</summary>
                  <pre>{pyResults.raw_output}</pre>
                </details>
              )}
            </>
          ) : (
            <div className="empty-state">{pyResults.error}</div>
          )}
        </div>
      )}
    </div>
  );
}
