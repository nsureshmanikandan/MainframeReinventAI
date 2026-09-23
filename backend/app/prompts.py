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
currency/rate fields, not float/double). Package: com.example.modernized. Output \
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

The Python code below will be saved as `{module_name}.py` in the same \
directory as your test file. Write a pytest test file that:
- Imports everything it needs with `from {module_name} import *` (or \
`import {module_name}`).
- Uses plain `assert` statements or pytest idioms (no unittest.TestCase needed).
- Is fully self-contained: no other fixtures, files, or network/database access.
- Every test function name starts with `test_`.

Coverage has TWO mandatory layers -- write BOTH, not one instead of the other:

LAYER 1 -- one baseline test per distinct outcome/return code/branch the \
COBOL can produce (every SET ...-TO-TRUE / every distinct return code / every \
distinct paragraph outcome), calling the actual classes/functions defined in \
{module_name}.py -- do not invent methods that aren't in the code below. Every \
branch the COBOL can take needs at least one test proving it's reachable and \
returns the right result. This layer alone is not sufficient on its own -- \
see Layer 2.

LAYER 2 -- for every numeric threshold/limit comparison in the COBOL (every \
`IF field > limit`, `>=`, `<`, `<=` against a literal or a WS-...-LIMIT/ \
THRESHOLD field), ADD two more test functions on top of (not instead of) that \
rule's Layer-1 test:
1. A test with the value exactly AT the boundary (the boundary case itself \
belongs to whichever branch the COBOL's own comparison operator puts it in \
-- e.g. `>` means the boundary value itself is still accepted, `>=` means it \
is rejected).
2. A test with the value one cent/one unit PAST the boundary, landing in the \
other branch.
Also add a test for any priority/ordering rule between two failure conditions \
(e.g. if both a limit-exceeded and an insufficient-funds condition could \
apply, prove which one the COBOL actually reports first).

Before finishing, count the distinct return codes / outcomes in the COBOL and \
verify your test file has at least one test for every single one of them --  \
a thorough boundary suite that silently drops coverage of an entire rule \
(e.g. never testing the sanctioned-country check at all) is still an \
incomplete test suite.

If the Python code defines a class with a constructor, instantiate it with \
realistic values before asserting on results. If it raises exceptions for \
invalid input, use `pytest.raises` to verify that.

CRITICAL -- any value in an assertion that is COMPUTED rather than a fixed \
COBOL literal (checksums/check digits; an accumulating score built from \
several independent point contributions, e.g. a fraud score; a code or ID \
derived from substrings/digits of other fields, e.g. an auth code built from \
part of the card number plus part of a timestamp; a fee that sums a \
percentage plus a flat surcharge): NEVER assert a value you have not derived \
yourself, step by step, in a comment directly above the assertion, using the \
exact formula/fields from the COBOL above and the exact input values your \
test constructs. This applies just as much to values you expect to STAY \
unchanged (e.g. "fraud score should still be 0" or "this contribution \
shouldn't apply") as to ones that change -- an accumulating score has no \
default of 0; every contributing rule that could apply to your chosen input \
must be individually checked and summed, not assumed absent. Show the full \
sum (or full digit-by-digit derivation) as a comment, e.g. `# base 20 (high \
amount) + 40 (card not present) + 0 (not intl) = 60`, then assert that \
computed number -- never a round number or a value that merely looks \
plausible. When in doubt for a checksum-style field specifically, default to \
the trivially-valid value (e.g. an all-zero routing number: every weighted \
term is 0, so a mod-10 checksum of 0 always passes) rather than a \
real-world-looking number reused from memory.

CRITICAL -- isolating ONE rule when several rules could fire on the same \
input: most of these COBOL programs evaluate several independent conditions \
against the same fields (e.g. a fraud score that accumulates from multiple \
independent triggers, or several decline reasons that could each apply to \
the same transaction). Before asserting the expected outcome of a test aimed \
at rule X, trace through EVERY OTHER rule in the COBOL against the exact \
input values you constructed -- if rule Y's condition is ALSO true for that \
input, the real outcome reflects Y too (added to X's score, or reported \
instead of X if Y is evaluated first), not X in isolation. Either (a) choose \
input values that keep every other rule's condition false so only your \
target rule fires, or (b) if multiple rules necessarily fire together for \
the scenario you're testing, compute the combined expected outcome by \
tracing all of them, not just the one you meant to isolate. A test with a \
wrong fixture value fails for a reason that has nothing to do with the \
business rule it claims to test -- worse than no test at all, because it \
looks like a real defect.

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
    "deployment_wrapper": """You are a platform engineer turning a modernized \
banking program into a REAL, deployable {language} artifact -- not \
documentation, and not a rewrite of the business logic itself.

DEPLOYMENT TARGET FOR THIS FILE:
{deployment_style_guidance}

CONVERTED BUSINESS LOGIC (already written and tested -- wrap it, do not \
re-implement or alter its internals):
```
{converted_code}
```

ORIGINAL COBOL (for context on what this program actually does, so you can \
name the endpoint/script sensibly):
```
{code}
```

Output ONLY the {language} wrapper code in a single fenced code block, no \
commentary outside the code block.
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
