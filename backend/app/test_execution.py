"""Real, executable test generation for the Python conversion.

The LLM generates a pytest file targeting the actual generated Python code;
this module writes both to a temp directory and runs pytest against them in
a real subprocess. This is genuine execution, not a self-reported score --
a test either passes or it doesn't.

(Java/JUnit execution is not implemented: this environment has no JDK --
verified no java/javac/mvn on PATH or in common Windows install locations
-- so Java code cannot be compiled or run here.)
"""

import pathlib
import re
import subprocess
import sys
import tempfile

PYTEST_TIMEOUT_SECONDS = 30

_RESULT_LINE_RE = re.compile(
    r"^test_solution\.py::(.+?)\s+(PASSED|FAILED|ERROR)\s+\[\s*\d+%\]\s*$"
)


def execute_python_tests(python_code: str, pytest_code: str, timeout: int = PYTEST_TIMEOUT_SECONDS) -> dict:
    with tempfile.TemporaryDirectory(prefix="mfr_pytest_") as tmp:
        tmp_path = pathlib.Path(tmp)
        (tmp_path / "solution.py").write_text(python_code, encoding="utf-8")
        (tmp_path / "test_solution.py").write_text(pytest_code, encoding="utf-8")

        try:
            proc = subprocess.run(
                [sys.executable, "-m", "pytest", "test_solution.py",
                 "-v", "--tb=short", "--no-header", "-p", "no:cacheprovider"],
                cwd=tmp_path,
                capture_output=True,
                text=True,
                timeout=timeout,
            )
        except subprocess.TimeoutExpired:
            return {
                "executed": False,
                "error": f"pytest run exceeded the {timeout}s timeout (possible infinite loop in generated code)",
                "tests": [],
                "passed": 0,
                "failed": 0,
                "total": 0,
            }
        except Exception as exc:  # noqa: BLE001 - surface any failure to the caller
            return {
                "executed": False,
                "error": f"failed to launch pytest subprocess: {exc}",
                "tests": [],
                "passed": 0,
                "failed": 0,
                "total": 0,
            }

        output = proc.stdout + "\n" + proc.stderr

        tests = []
        for line in output.splitlines():
            match = _RESULT_LINE_RE.match(line.strip())
            if match:
                tests.append({"name": match.group(1), "outcome": match.group(2)})

        # Count directly from parsed per-test outcomes rather than regexing
        # pytest's summary line, whose clause order/presence varies (e.g. no
        # "failed" clause at all when everything passes).
        passed = sum(1 for t in tests if t["outcome"] == "PASSED")
        failed = sum(1 for t in tests if t["outcome"] in ("FAILED", "ERROR"))

        collection_error = (
            not tests
            and ("error" in output.lower() or proc.returncode not in (0, 1))
        )

        return {
            "executed": True,
            "collection_error": collection_error,
            "raw_output": output[-8000:],
            "tests": tests,
            "passed": passed,
            "failed": failed,
            "total": len(tests),
            "return_code": proc.returncode,
        }
