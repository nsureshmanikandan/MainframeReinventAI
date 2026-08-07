import type {
  AzureModelOption,
  Backend,
  CobolFile,
  DeploymentStyle,
  ResultsByBackend,
  TraceSpan,
} from "./types";

const API_BASE = "/api";

export async function listFiles(): Promise<CobolFile[]> {
  const resp = await fetch(`${API_BASE}/files`);
  if (!resp.ok) throw new Error(`Failed to list files: ${resp.status}`);
  return resp.json();
}

export async function getAzureModels(): Promise<AzureModelOption[]> {
  const resp = await fetch(`${API_BASE}/azure-models`);
  if (!resp.ok) throw new Error(`Failed to load Azure models: ${resp.status}`);
  return resp.json();
}

export async function getSource(filename: string): Promise<string> {
  const resp = await fetch(`${API_BASE}/files/${encodeURIComponent(filename)}/source`);
  if (!resp.ok) throw new Error(`Failed to load source: ${resp.status}`);
  const data = await resp.json();
  return data.source as string;
}

export async function triggerMigration(
  filename: string,
  backend: Backend | "both",
  azureModel: string
): Promise<void> {
  const resp = await fetch(`${API_BASE}/migrate`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ filename, backend, azure_model: azureModel }),
  });
  if (!resp.ok) throw new Error(`Failed to start migration: ${resp.status}`);
}

export async function triggerRefine(
  filename: string,
  backend: Backend | "both",
  cycles: number,
  azureModel: string
): Promise<void> {
  const resp = await fetch(`${API_BASE}/refine`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ filename, backend, cycles, azure_model: azureModel }),
  });
  if (!resp.ok) {
    const body = await resp.json().catch(() => ({}));
    throw new Error(body.detail || `Failed to start refinement: ${resp.status}`);
  }
}

export async function getInputDir(): Promise<{ path: string; file_count: number }> {
  const resp = await fetch(`${API_BASE}/config/input-dir`);
  if (!resp.ok) throw new Error(`Failed to load input dir: ${resp.status}`);
  return resp.json();
}

export async function setInputDir(path: string): Promise<{ path: string; file_count: number }> {
  const resp = await fetch(`${API_BASE}/config/input-dir`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ path }),
  });
  if (!resp.ok) {
    const body = await resp.json().catch(() => ({}));
    throw new Error(body.detail || `Failed to set input dir: ${resp.status}`);
  }
  return resp.json();
}

export async function getResults(filename: string): Promise<ResultsByBackend> {
  const resp = await fetch(`${API_BASE}/results/${encodeURIComponent(filename)}`);
  if (!resp.ok) throw new Error(`Failed to load results: ${resp.status}`);
  return resp.json();
}

export async function triggerTestExecution(
  filename: string,
  backend: Backend | "both"
): Promise<void> {
  const resp = await fetch(`${API_BASE}/execute-tests`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ filename, backend }),
  });
  if (!resp.ok) {
    const body = await resp.json().catch(() => ({}));
    throw new Error(body.detail || `Failed to start test execution: ${resp.status}`);
  }
}

export async function getDeploymentStyle(filename: string): Promise<DeploymentStyle> {
  const resp = await fetch(`${API_BASE}/deployment-style/${encodeURIComponent(filename)}`);
  if (!resp.ok) throw new Error(`Failed to load deployment style: ${resp.status}`);
  return resp.json();
}

export async function triggerGenerateWrapper(
  filename: string,
  backend: Backend | "both"
): Promise<void> {
  const resp = await fetch(`${API_BASE}/generate-wrapper`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ filename, backend }),
  });
  if (!resp.ok) {
    const body = await resp.json().catch(() => ({}));
    throw new Error(body.detail || `Failed to start wrapper generation: ${resp.status}`);
  }
}

export function downloadWrapperUrl(filename: string, backend: Backend, language: "python" | "java"): string {
  return `${API_BASE}/download-wrapper/${encodeURIComponent(filename)}?backend=${backend}&language=${language}`;
}

export async function getTraces(filename: string, backend?: Backend): Promise<TraceSpan[]> {
  const url = backend
    ? `${API_BASE}/traces/${encodeURIComponent(filename)}?backend=${backend}`
    : `${API_BASE}/traces/${encodeURIComponent(filename)}`;
  const resp = await fetch(url);
  if (!resp.ok) throw new Error(`Failed to load traces: ${resp.status}`);
  return resp.json();
}
