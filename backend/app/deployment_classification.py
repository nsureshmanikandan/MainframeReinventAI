"""Real-world deployment classification for each COBOL program.

This is a judgment call about how each program is actually invoked in
production, not something derivable from the code alone -- CARDAUTH and
ACHBATCH have the same kind of validation-paragraph structure, but one
answers a single card swipe in real time and the other processes a file of
many transactions overnight. That distinction decides whether the modernized
target is a REST API (Java Spring Boot controller / Python FastAPI route)
or a batch entrypoint (scheduled job / message consumer) -- turning a batch
job into a synchronous API would misrepresent how the bank actually uses it.
"""

API = "api"
BATCH = "batch"

DEPLOYMENT_STYLE = {
    "CARDAUTH": (API, "Card swipe triggers a sub-second authorize/decline decision."),
    "FXWIRE": (API, "Wire is initiated and needs a real-time risk/limit check before it's sent."),
    "CLIELIG": (API, "Credit line request needs a real-time eligibility decision at application time."),
    "OVDPROC": (API, "A transaction posts and needs a real-time overdraft decision."),
    "CHKHOLD": (API, "Check is deposited at a teller/ATM and needs a real-time hold-days decision."),
    "ACHBATCH": (BATCH, "Processes a file of many ACH/wire transactions in one run, not a single caller waiting on a response."),
    "REWARDCALC": (BATCH, "Rewards points are recalculated on a cycle (e.g. nightly), not per-swipe."),
    "STMTGEN": (BATCH, "Statements are generated for the whole portfolio on a billing cycle."),
    "LOANAMRT": (BATCH, "Amortization schedules are built/recalculated in bulk, not per-request."),
    "MERCHSTL": (BATCH, "Merchant settlement is an end-of-day batch run across many transactions."),
}


def get_deployment_style(stem: str) -> tuple[str, str]:
    return DEPLOYMENT_STYLE.get(
        stem, (API, "No explicit classification for this program -- defaulting to API; verify against how it's actually invoked.")
    )


_PYTHON_API_GUIDANCE = """\
A FastAPI microservice exposing this logic as a real, callable REST endpoint \
(this replaces a CICS transaction that used to be invoked from a teller \
terminal, ATM, or POS device in real time, one request per customer action).
Requirements:
- Define Pydantic request/response models mirroring the underlying \
function's/constructor's fields exactly.
- One POST endpoint with a URL path and function name that reflects what \
this program actually does (e.g. /authorize, /check-eligibility) -- not a \
generic /process.
- Catch the module's own custom exception type and return it as an HTTP 400 \
with a clear `detail` message -- never let it become an unhandled 500.
- Include a `if __name__ == "__main__":` block that runs it with \
`uvicorn.run(app, host="0.0.0.0", port=8000)` so it can be started directly \
with `python <this file>`.
- This file will sit next to the module below, saved as `{module_name}.py` \
-- import from it with `from {module_name} import ...`; do not redefine the \
business logic here.
"""

_PYTHON_BATCH_GUIDANCE = """\
A standalone batch script (this replaces a JCL/JES overnight batch job, not \
a live API -- there is no single caller waiting on a response; it processes \
many records in one run).
Requirements:
- Use argparse for --input and --output file paths (default to \
input.csv/output.csv).
- Read one record per input row (CSV), construct whatever the underlying \
function/constructor needs from its columns, call the real logic for each \
row, and write one result row per input row to the output CSV -- including \
error rows (catch the module's own exception per-row so one bad row doesn't \
crash the whole batch; record the failure reason in that row's output).
- Print a final summary line: total records processed, succeeded, failed.
- Include a `if __name__ == "__main__":` entrypoint so it runs with \
`python <this file> --input records.csv --output results.csv`.
- This file will sit next to the module below, saved as `{module_name}.py` \
-- import from it with `from {module_name} import ...`; do not redefine the \
business logic here.
"""

_JAVA_API_GUIDANCE = """\
A Spring Boot REST controller exposing this logic as a callable endpoint \
(this replaces a CICS transaction). Requirements: package \
com.amex.modernized; use @RestController, @PostMapping, and \
@RequestBody/@ResponseBody with a request/response DTO class mirroring the \
underlying class's fields; catch the module's own custom exception and \
translate it to a 400 response via @ExceptionHandler or \
ResponseStatusException.
NOTE: this environment has no JDK, so this file is generated as correct, \
idiomatic Spring Boot source for you to build with Maven/Gradle -- it will \
not be compiled or run here.
"""

_JAVA_BATCH_GUIDANCE = """\
A Spring Boot CommandLineRunner (or a plain class with a main method) that \
reads records from a CSV file, calls the underlying class for each row, and \
writes results to an output CSV, catching the module's own exception \
per-row so one bad record doesn't abort the whole batch, ending with a \
summary count.
NOTE: this environment has no JDK, so this file is generated as correct, \
idiomatic Java source for you to build with Maven/Gradle -- it will not be \
compiled or run here.
"""

_GUIDANCE = {
    ("python", API): _PYTHON_API_GUIDANCE,
    ("python", BATCH): _PYTHON_BATCH_GUIDANCE,
    ("java", API): _JAVA_API_GUIDANCE,
    ("java", BATCH): _JAVA_BATCH_GUIDANCE,
}


def get_wrapper_guidance(language: str, style: str, module_name: str) -> str:
    template = _GUIDANCE[(language.lower(), style)]
    return template.format(module_name=module_name)
