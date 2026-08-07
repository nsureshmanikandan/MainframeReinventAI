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


def execute_python_tests(
    python_code: str, pytest_code: str, module_name: str, timeout: int = PYTEST_TIMEOUT_SECONDS
) -> dict:
    """Runs pytest_code against python_code in a real subprocess.

    module_name must match the name the exported ZIP saves the converted
    Python file as (`{stem.lower()}.py`) -- the pytest file's own `from
    {module_name} import ...` line only works, both here and after a user
    downloads the export, if the two agree on that name.
    """
    test_filename = f"test_{module_name}.py"
    result_line_re = re.compile(
        rf"^{re.escape(test_filename)}::(.+?)\s+(PASSED|FAILED|ERROR)\s+\[\s*\d+%\]\s*$"
    )

    with tempfile.TemporaryDirectory(prefix="mfr_pytest_") as tmp:
        tmp_path = pathlib.Path(tmp)
        (tmp_path / f"{module_name}.py").write_text(python_code, encoding="utf-8")
        (tmp_path / test_filename).write_text(pytest_code, encoding="utf-8")

        try:
            proc = subprocess.run(
                [sys.executable, "-m", "pytest", test_filename,
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
            match = result_line_re.match(line.strip())
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
