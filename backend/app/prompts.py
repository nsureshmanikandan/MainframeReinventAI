"""The 5-pillar prompt set: Legacy Understanding, Code Modernization, Robust
Testing, Rapid Modernization (the pipeline itself), Continuous Optimization."""

import re

PROMPTS = {
    "functional_spec": """You are a mainframe reverse-engineering agent, part of an \
Agentic Modernization Workbench (Legacy Understanding pillar).

Analyze the following COBOL program and produce a FUNCTIONAL SPECIFICATION in \
markdown covering:
1. Purpose / business scenario (who uses this and why)
2. Inputs and outputs
3. Business rules, numbered, extracted precisely from the logic (reference the \
   actual thresholds/values used, don't paraphrase generically)
4. Data elements and what they represent in the business domain

Do not include the raw COBOL in your answer -- documentation only.

COBOL SOURCE:
```
{code}
```
""",
    "dependency_map": """You are a mainframe reverse-engineering agent (Legacy \
Understanding pillar). Produce a DEPENDENCY MAP in markdown for the following \
COBOL program: paragraph call graph (which paragraph performs which), data \
records/fields referenced by each paragraph, and any external dependencies \
implied by the logic (files, other systems, downstream consumers).

COBOL SOURCE:
```
{code}
```
""",
    "test_cases": """You are a quality-engineering agent (Robust Testing pillar). \
Generate a markdown table of test cases for the business logic in the following \
COBOL program. Cover normal, boundary, and edge cases. Columns: Test ID, \
Scenario, Input Values, Expected Output, Business Rule Covered.

COBOL SOURCE:
```
{code}
```
""",
    "convert_java": """You are a forward-engineering agent (Code Modernization \
pillar). Convert the following COBOL program into equivalent, idiomatic Java. \
Preserve business logic and numeric precision exactly (use BigDecimal for \
currency/rate fields, not float/double). Package: com.amex.modernized. Output \
ONLY the Java code in a single fenced code block, no commentary outside the \
code block.

COBOL SOURCE:
```
{code}
```
""",
    "convert_python": """You are a forward-engineering agent (Code Modernization \
pillar). Convert the following COBOL program into equivalent, idiomatic \
Python 3. Preserve business logic and numeric precision exactly (use the \
decimal.Decimal type for currency/rate fields, not float). Output ONLY the \
Python code in a single fenced code block, no commentary outside the code \
block.

COBOL SOURCE:
```
{code}
```
""",
    "equivalence_review": """You are a quality-engineering validation agent \
(Continuous Optimization pillar), similar to WCA4Z's Validation Assistant. \
Compare the ORIGINAL COBOL logic to the CONVERTED code below. List any point \
where the converted code's behavior could diverge from the original (rounding, \
edge cases, condition ordering, missing rules). If you find no divergence, say \
so explicitly and explain why you're confident they're equivalent. Format as \
markdown.

ORIGINAL COBOL:
```
{code}
```

CONVERTED CODE:
```
{converted_code}
```
""",
    "pytest_tests": """You are a quality-engineering agent (Robust Testing pillar) \
generating REAL, EXECUTABLE pytest tests -- not documentation. These will be \
saved to disk and actually run.

The Python code below will be saved as `solution.py` in the same directory \
as your test file. Write a pytest test file that:
- Imports everything it needs with `from solution import *` (or `import solution`).
- Exercises the real business rules from the COBOL source below (normal, \
boundary, and edge cases) by calling the actual classes/functions defined in \
solution.py -- do not invent methods that aren't in the code below.
- Uses plain `assert` statements or pytest idioms (no unittest.TestCase needed).
- Is fully self-contained: no other fixtures, files, or network/database access.
- Every test function name starts with `test_`.

If the Python code defines a class with a constructor, instantiate it with \
realistic values before asserting on results. If it raises exceptions for \
invalid input, use `pytest.raises` to verify that.

COBOL SOURCE (business rules to test):
```
{code}
```

PYTHON CODE UNDER TEST (will be saved as solution.py):
```
{converted_code}
```

Output ONLY the pytest code in a single fenced code block, no commentary \
outside the code block.
""",
    "refine_code": """You are a senior banking-software reviewer acting as a \
forward-engineering agent (Continuous Optimization pillar). The {language} code \
below was auto-converted from COBOL and has known defects that must be fixed \
before this would be acceptable as enterprise banking code.

Rules for the corrected version:
- Fix every issue listed under KNOWN ISSUES below.
- Preserve exact business-rule fidelity with the COBOL. In particular: \
independent sequential COBOL `IF` statements that each unconditionally test \
their own condition and can overwrite a shared result field must be converted \
to separate consecutive `if` statements (NOT an `else if` chain) unless the \
COBOL itself uses `ELSE` -- COBOL's fall-through means the LAST true condition \
wins, not the first.
- Use BigDecimal (Java) / decimal.Decimal (Python) for every currency, rate, \
and point-balance field. Match COBOL's COMPUTE rounding exactly: a `COMPUTE` \
with NO `ROUNDED` clause truncates (does not round); a `COMPUTE ... ROUNDED` \
rounds half-up.
- Treat every per-transaction/per-call field as a local variable or method \
parameter, never persistent instance/object state -- this code must be safe \
to call concurrently for different accounts in a real service.
- Implement every COBOL paragraph, including output/logging paragraphs (e.g. \
a `WRITE-LEDGER` or `WRITE-RESPONSE` paragraph) -- do not silently drop one.
- Add proper documentation and structured logging (not System.out.println / \
print) suitable for a real banking codebase.
- The EQUIVALENCE REVIEW below is the model's own prior self-assessment. \
Verify each claim against the COBOL before acting on it -- some claims in a \
self-review can be mathematically wrong (e.g. flagging code that is actually \
equivalent). Only apply a fix if the COBOL logic genuinely supports it.

KNOWN ISSUES (verified by independent audit):
{known_issues}

PRIOR EQUIVALENCE REVIEW (verify before trusting):
{equivalence_review}

ORIGINAL COBOL:
```
{code}
```

CURRENT {language} CODE (has the issues above):
```
{current_code}
```

Output ONLY the corrected {language} code in a single fenced code block, no \
commentary outside the code block.
""",
}


def extract_code_block(text: str) -> str:
    if not text:
        return ""
    match = re.search(r"```(?:\w+)?\n(.*?)```", text, re.DOTALL)
    if match:
        return match.group(1).strip()
    # No closing fence -- the response was likely truncated (hit max_tokens).
    # Still strip a leading opening fence so we don't ship a raw ```java line.
    return re.sub(r"^```(?:\w+)?\n", "", text.strip()).strip()


def looks_truncated(code: str, language: str) -> bool:
    """Heuristic brace-balance check to catch responses cut off by max_tokens."""
    if not code:
        return False
    if language == "java":
        return code.count("{") != code.count("}")
    return False
