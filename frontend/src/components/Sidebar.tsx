import { useEffect, useState } from "react";
import type { CobolFile, ResultsByBackend } from "../types";
import StatusBadge from "./StatusBadge";

interface Props {
  files: CobolFile[];
  selected: string | null;
  onSelect: (filename: string) => void;
  resultsByFile: Record<string, ResultsByBackend>;
  currentPath: string;
  onRefresh: () => void;
  onChangePath: (path: string) => void;
}

export default function Sidebar({
  files,
  selected,
  onSelect,
  resultsByFile,
  currentPath,
  onRefresh,
  onChangePath,
}: Props) {
  const [pathInput, setPathInput] = useState(currentPath);

  useEffect(() => {
    setPathInput(currentPath);
  }, [currentPath]);

  return (
    <aside className="sidebar">
      <div className="sidebar-header">
        <div className="brand-mark">MR</div>
        <div>
          <div className="brand-title">Mainframe Reinvent AI</div>
          <div className="brand-subtitle">COBOL Modernization Studio</div>
        </div>
      </div>

      <div className="folder-config">
        <div className="sidebar-section-label-row">
          <span className="sidebar-section-label">Legacy Programs</span>
          <button className="icon-button" onClick={onRefresh} title="Refresh file list from this folder">
            ⟳
          </button>
        </div>
        <div className="folder-path-row">
          <input
            className="folder-path-input"
            value={pathInput}
            onChange={(e) => setPathInput(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") onChangePath(pathInput);
            }}
            placeholder="C:\path\to\cobol\folder"
            title={currentPath}
          />
          <button className="folder-load-btn" onClick={() => onChangePath(pathInput)}>
            Load
          </button>
        </div>
      </div>

      <ul className="file-list">
        {files.map((f) => {
          const results = resultsByFile[f.filename] || {};
          return (
            <li
              key={f.filename}
              className={`file-item ${selected === f.filename ? "active" : ""}`}
              onClick={() => onSelect(f.filename)}
            >
              <div className="file-item-name">{f.filename}</div>
              <div className="file-item-meta">
                <span>{(f.size_bytes / 1024).toFixed(1)} KB</span>
                <div className="file-item-badges">
                  {results.azure && <StatusBadge status={results.azure.status} />}
                  {results.gemini && <StatusBadge status={results.gemini.status} />}
                </div>
              </div>
            </li>
          );
        })}
        {files.length === 0 && (
          <li className="file-list-empty">No .cbl files found in this folder.</li>
        )}
      </ul>
    </aside>
  );
}
