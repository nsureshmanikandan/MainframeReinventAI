import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";

interface Props {
  content: string | null | undefined;
}

export default function MarkdownBlock({ content }: Props) {
  if (!content) {
    return <div className="empty-state">No content yet.</div>;
  }
  return (
    <div className="markdown-body">
      <ReactMarkdown remarkPlugins={[remarkGfm]}>{content}</ReactMarkdown>
    </div>
  );
}
