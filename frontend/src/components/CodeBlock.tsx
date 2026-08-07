import { Prism as SyntaxHighlighter } from "react-syntax-highlighter";
import { vscDarkPlus } from "react-syntax-highlighter/dist/esm/styles/prism";

interface Props {
  code: string;
  language: string;
}

export default function CodeBlock({ code, language }: Props) {
  if (!code) {
    return <div className="empty-state">No content yet.</div>;
  }
  return (
    <SyntaxHighlighter
      language={language}
      style={vscDarkPlus}
      showLineNumbers
      wrapLongLines={false}
      customStyle={{
        margin: 0,
        height: "100%",
        fontSize: "12.5px",
        background: "transparent",
      }}
    >
      {code}
    </SyntaxHighlighter>
  );
}
