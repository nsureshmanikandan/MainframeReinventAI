interface Props {
  status: string | undefined;
}

export default function StatusBadge({ status }: Props) {
  const raw = status || "idle";
  const isError = raw.startsWith("error");
  // Multi-part statuses like "refining · cycle 1/2 · Java" reduce to their
  // first word so the CSS class and badge stay a single clean token.
  const base = isError ? "error" : raw.split(/[\s·]/)[0] || "idle";
  const cls = `status-badge status-${base}`;
  return <span className={cls}>{base}</span>;
}
