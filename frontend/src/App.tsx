import { useEffect, useRef, useState } from "react";
import "./App.css";
import {
  getAzureModels,
  getInputDir,
  getResults,
  getSource,
  listFiles,
  setInputDir,
  triggerMigration,
  triggerRefine,
} from "./api";
import BackendColumn from "./components/BackendColumn";
import CodeBlock from "./components/CodeBlock";
import Sidebar from "./components/Sidebar";
import type { AzureModelOption, Backend, CobolFile, ResultsByBackend } from "./types";

type BackendMode = Backend | "both";
type PanelId = "source" | "azure" | "gemini";

function App() {
  const [files, setFiles] = useState<CobolFile[]>([]);
  const [selected, setSelected] = useState<string | null>(null);
  const [source, setSource] = useState<string>("");
  const [mode, setMode] = useState<BackendMode>("both");
  const [resultsByFile, setResultsByFile] = useState<Record<string, ResultsByBackend>>({});
  const [running, setRunning] = useState(false);
  const [refining, setRefining] = useState(false);
  const [cycles, setCycles] = useState(2);
  const [maximizedPanel, setMaximizedPanel] = useState<PanelId | null>(null);
  const [azureModels, setAzureModels] = useState<AzureModelOption[]>([]);
  const [azureModel, setAzureModel] = useState<string>("gpt-5.6-sol");
  const [inputDirPath, setInputDirPath] = useState<string>("");
  const pollRef = useRef<number | null>(null);

  async function refreshFiles() {
    const f = await listFiles();
    setFiles(f);
    if (f.length > 0 && !f.some((x) => x.filename === selected)) {
      setSelected(f[0].filename);
    } else if (f.length === 0) {
      setSelected(null);
    }
  }

  async function changeInputDir(path: string) {
    try {
      const result = await setInputDir(path);
      setInputDirPath(result.path);
      await refreshFiles();
    } catch (e) {
      alert((e as Error).message);
    }
  }

  useEffect(() => {
    getInputDir().then((d) => setInputDirPath(d.path));
    listFiles().then((f) => {
      setFiles(f);
      if (f.length > 0) setSelected(f[0].filename);
    });
    getAzureModels().then((models) => {
      setAzureModels(models);
      if (models.length > 0) setAzureModel(models[0].id);
    });
  }, []);

  useEffect(() => {
    if (!selected) return;
    getSource(selected).then(setSource);
    getResults(selected).then((r) =>
      setResultsByFile((prev) => ({ ...prev, [selected]: r }))
    );
  }, [selected]);

  useEffect(() => {
    return () => {
      if (pollRef.current) window.clearInterval(pollRef.current);
    };
  }, []);

  async function refreshCurrentResults() {
    if (!selected) return;
    const r = await getResults(selected);
    setResultsByFile((prev) => ({ ...prev, [selected]: r }));
  }

  function isDone(results: ResultsByBackend, backends: Backend[]) {
    return backends.every((b) => {
      const s = results[b]?.status;
      return s === "completed" || (s && s.startsWith("error"));
    });
  }

  function pollUntilDone(backends: Backend[], onDone: () => void) {
    if (!selected) return;
    if (pollRef.current) window.clearInterval(pollRef.current);
    pollRef.current = window.setInterval(async () => {
      const r = await getResults(selected);
      setResultsByFile((prev) => ({ ...prev, [selected]: r }));
      if (isDone(r, backends)) {
        if (pollRef.current) window.clearInterval(pollRef.current);
        onDone();
      }
    }, 2000);
  }

  async function runMigration() {
    if (!selected) return;
    setRunning(true);
    await triggerMigration(selected, mode, azureModel);
    const backends: Backend[] = mode === "both" ? ["azure", "gemini"] : [mode];
    pollUntilDone(backends, () => setRunning(false));
  }

  async function runRefine() {
    if (!selected) return;
    setRefining(true);
    try {
      await triggerRefine(selected, mode, cycles, azureModel);
    } catch (e) {
      alert((e as Error).message);
      setRefining(false);
      return;
    }
    const backends: Backend[] = mode === "both" ? ["azure", "gemini"] : [mode];
    pollUntilDone(backends, () => setRefining(false));
  }

  const currentResults = selected ? resultsByFile[selected] || {} : {};
  const hasAnyResult = Boolean(currentResults.azure || currentResults.gemini);
  const hasAnyCode = Boolean(
    currentResults.azure?.java_code ||
      currentResults.azure?.python_code ||
      currentResults.gemini?.java_code ||
      currentResults.gemini?.python_code
  );
  const stem = selected ? selected.replace(/\.cbl$/i, "") : "";

  function exportCurrentFile() {
    if (!selected) return;
    window.location.href = `/api/export/${encodeURIComponent(selected)}?backend=${mode}`;
  }

  function exportAllFiles() {
    window.location.href = `/api/export-all`;
  }

  function toggleMaximize(panel: PanelId) {
    setMaximizedPanel((prev) => (prev === panel ? null : panel));
  }

  const panelVisible = (panel: PanelId) => maximizedPanel === null || maximizedPanel === panel;

  return (
    <div className="app-shell">
      <Sidebar
        files={files}
        selected={selected}
        onSelect={setSelected}
        resultsByFile={resultsByFile}
        currentPath={inputDirPath}
        onRefresh={refreshFiles}
        onChangePath={changeInputDir}
      />

      <div className="main-area">
        <header className="toolbar">
          <div className="toolbar-title-row">
            <div className="toolbar-title">{selected ?? "Select a program"}</div>
            <div className="toolbar-subtitle">
              Agentic Modernization Workbench — Legacy Understanding · Code Modernization ·
              Robust Testing · Continuous Optimization
            </div>
          </div>
          <div className="toolbar-actions">
            <select
              className="backend-select"
              value={mode}
              onChange={(e) => setMode(e.target.value as BackendMode)}
            >
              <option value="both">Azure + Gemini (side by side)</option>
              <option value="azure">Azure OpenAI only</option>
              <option value="gemini">Gemini only</option>
            </select>
            {(mode === "both" || mode === "azure") && azureModels.length > 0 && (
              <select
                className="backend-select model-select"
                value={azureModel}
                onChange={(e) => setAzureModel(e.target.value)}
                title="Which Azure-deployed model to use for the Azure column"
              >
                {azureModels.map((m) => (
                  <option key={m.id} value={m.id}>
                    {m.label}
                  </option>
                ))}
              </select>
            )}
            <button
              className="run-button"
              onClick={runMigration}
              disabled={!selected || running || refining}
            >
              {running ? "Running…" : "Run Migration"}
            </button>
            <select
              className="backend-select cycles-select"
              value={cycles}
              onChange={(e) => setCycles(Number(e.target.value))}
              title="Number of refinement cycles"
            >
              <option value={1}>1 cycle</option>
              <option value={2}>2 cycles</option>
              <option value={3}>3 cycles</option>
            </select>
            <button
              className="refine-button"
              onClick={runRefine}
              disabled={!selected || !hasAnyCode || running || refining}
              title="Feed the equivalence review + audited defects back into the LLM to fix them"
            >
              {refining ? "Refining…" : "Refine Code"}
            </button>
            <button
              className="export-button"
              onClick={exportCurrentFile}
              disabled={!hasAnyResult}
              title="Download this program's generated docs + code as a ZIP"
            >
              Export File
            </button>
            <button
              className="export-button"
              onClick={exportAllFiles}
              title="Download every migrated program as one ZIP"
            >
              Export All
            </button>
          </div>
        </header>

        <div className={`columns ${maximizedPanel ? "has-maximized" : ""}`}>
          {panelVisible("source") && (
            <div className={`source-column ${maximizedPanel === "source" ? "column-maximized" : ""}`}>
              <div className="backend-column-header">
                <div>
                  <div className="backend-name">Original COBOL</div>
                  <div className="backend-model">Legacy z/OS source</div>
                </div>
                <button
                  className="panel-toggle-btn"
                  onClick={() => toggleMaximize("source")}
                  title={maximizedPanel === "source" ? "Restore" : "Maximize"}
                >
                  {maximizedPanel === "source" ? "⤡" : "⤢"}
                </button>
              </div>
              <div className="pane-content">
                <CodeBlock code={source} language="cobol" />
              </div>
            </div>
          )}

          {(mode === "both" || mode === "azure") && panelVisible("azure") && (
            <BackendColumn
              backend="azure"
              result={currentResults.azure}
              stem={stem}
              filename={selected || ""}
              isMaximized={maximizedPanel === "azure"}
              isHidden={false}
              onToggleMaximize={() => toggleMaximize("azure")}
              onRefreshResults={refreshCurrentResults}
            />
          )}
          {(mode === "both" || mode === "gemini") && panelVisible("gemini") && (
            <BackendColumn
              backend="gemini"
              result={currentResults.gemini}
              stem={stem}
              filename={selected || ""}
              isMaximized={maximizedPanel === "gemini"}
              isHidden={false}
              onToggleMaximize={() => toggleMaximize("gemini")}
              onRefreshResults={refreshCurrentResults}
            />
          )}
        </div>
      </div>
    </div>
  );
}

export default App;
