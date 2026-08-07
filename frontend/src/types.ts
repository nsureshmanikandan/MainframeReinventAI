export type Backend = "azure" | "gemini";

export interface AzureModelOption {
  id: string;
  label: string;
}

export interface CobolFile {
  filename: string;
  size_bytes: number;
}

export interface MigrationResult {
  filename: string;
  backend: Backend;
  status: string;
  functional_spec?: string | null;
  dependency_map?: string | null;
  test_cases?: string | null;
  java_code?: string | null;
  python_code?: string | null;
  equivalence_review?: string | null;
  refinement_log?: string | null;
  model_used?: string | null;
  updated_at?: string | null;
  python_tests?: string | null;
  python_test_results?: string | null;
  test_execution_status?: string | null;
}

export type ResultsByBackend = Partial<Record<Backend, MigrationResult>>;

export interface PytestCaseResult {
  name: string;
  outcome: "PASSED" | "FAILED" | "ERROR";
}

export interface PythonTestResults {
  executed: boolean;
  error?: string;
  collection_error?: boolean;
  raw_output?: string;
  tests: PytestCaseResult[];
  passed: number;
  failed: number;
  total: number;
  return_code?: number;
}

export interface TraceSpan {
  id: number;
  filename: string;
  backend: string;
  trace_id: string;
  span_id: string;
  parent_span_id: string | null;
  name: string;
  start_time: number;
  end_time: number;
  duration_ms: number;
  status: string;
  attributes: string;
}

export const PILLARS = [
  { key: "functional_spec", label: "Functional Spec", pillar: "Legacy Understanding" },
  { key: "dependency_map", label: "Dependency Map", pillar: "Legacy Understanding" },
  { key: "test_cases", label: "Test Cases", pillar: "Robust Testing" },
  { key: "java_code", label: "Java", pillar: "Code Modernization" },
  { key: "python_code", label: "Python", pillar: "Code Modernization" },
  { key: "equivalence_review", label: "Equivalence Review", pillar: "Continuous Optimization" },
] as const;

export type StepState = "done" | "active" | "pending" | "error";

export interface PillarStep {
  key: string;
  label: string;
  pillar: string;
  state: StepState;
}

/**
 * Steps run strictly in PILLARS order on the backend, one field populated
 * per step. The first unpopulated field while status is running/queued is
 * the step currently in flight; anything before it is done.
 */
export function getPillarSteps(result: MigrationResult | undefined): PillarStep[] {
  const status = result?.status || "idle";
  const isError = status.startsWith("error");
  const isDone = status === "completed";

  let activeIndex = -1;
  if (!isDone) {
    activeIndex = PILLARS.findIndex((p) => !(result as any)?.[p.key]);
    if (activeIndex === -1) activeIndex = PILLARS.length;
  }

  return PILLARS.map((p, i) => {
    const hasValue = Boolean((result as any)?.[p.key]);
    let state: StepState = "pending";
    if (isDone || hasValue) state = "done";
    else if (isError && i === activeIndex) state = "error";
    else if (!isError && i === activeIndex && status !== "idle") state = "active";
    return { key: p.key, label: p.label, pillar: p.pillar, state };
  });
}
