"""Defects verified by independent human/agent audit (not self-reported by the
LLM). Keyed by (backend, program_stem). Fed into the refine_code prompt as
ground truth the model should trust over its own equivalence_review claims."""

# Verified by a static scan across all 20 generated artifacts (10 programs x
# 2 backends, 2026-08-06): ZERO use a custom/domain-specific exception type.
# Every Java file throws generic IllegalArgumentException/RuntimeException/
# NullPointerException, and Python functions largely don't validate input at
# all. This is universal, not per-program, so it's appended to every
# get_known_issues() result below rather than duplicated into every entry.
ERROR_HANDLING_GUIDANCE = """\
- Error-handling gap (verified across the full 10-program test suite, not
  specific to this file): this conversion uses generic Java exceptions
  (IllegalArgumentException, RuntimeException, NullPointerException) with no
  domain-specific exception type, and the Python side either doesn't
  validate input at all or lets a built-in exception (KeyError, TypeError,
  IndexError) propagate uncaught as the effective error signal. Fix:
  1. Define ONE small custom exception type for this program (e.g.
     `<ProgramName>ValidationException extends RuntimeException` in Java, a
     matching `class <ProgramName>ValidationError(Exception)` in Python) and
     throw/raise that instead of a generic built-in exception.
  2. Validate every public entry point's inputs explicitly at the top of the
     method (null/None checks, length/range checks matching the COBOL PIC
     clause's implied constraints -- e.g. a 16-digit card number, a 9-digit
     routing number) and raise the custom exception with a specific,
     actionable message. Do not let a NullPointerException, KeyError, or
     IndexOutOfBoundsException be the actual error a caller sees.
  3. Never use a bare `except:` in Python -- catch specific exception types
     only, and never silently swallow an error (no empty except blocks).
"""

PRODUCTION_READINESS_CARDAUTH = """\
- Production-readiness gaps (audited): the code uses System.out.println for
  output instead of a real logging framework, and hardcodes business
  thresholds (fraud score threshold 70, international fee rate 0.030, cash
  advance fee rate 0.050, cash advance fee floor $10.00, high-value
  threshold $2000.00, card-not-present threshold $500.00, blacklisted
  MCC/country) as literals baked into the code. For enterprise banking code
  these must be:
  1. Logged via java.util.logging.Logger (a Logger field on the class,
     e.g. `private static final Logger LOGGER = Logger.getLogger(...)`),
     using LOGGER.info(...) for approvals and LOGGER.warning(...) for
     fraud-referral/decline paths -- never System.out/System.err.
  2. Externalized as fields on a configuration object/record passed into
     the constructor (e.g. a `FraudRules` or `AuthorizationConfig` record
     with sensible defaults matching the COBOL VALUE clauses), not
     hardcoded `private static final` literals, so risk/fraud teams can
     tune them without a code change or redeploy.
"""

KNOWN_ISSUES = {
    ("azure", "CARDAUTH"): PRODUCTION_READINESS_CARDAUTH,
    ("gemini", "CARDAUTH"): """\
- In validateCardStatus, validateCvvAndPin, and checkVelocityLimits, COBOL's
  independent sequential IF statements (each of which can overwrite the
  shared response code) were incorrectly converted into an else-if chain.
  COBOL's checks are independent and the LAST true condition wins (overwrite
  semantics), not the first. Example: a card that is both CLOSED and expired
  must produce COBOL's final response '54' (CARD EXPIRED), but an else-if
  chain stops at the first match and would return '05' (ACCOUNT CLOSED)
  instead -- a materially different decline reason on a real transaction.
  Rewrite these three methods using separate consecutive `if` statements (no
  else-if) so later conditions can overwrite the result of earlier ones,
  exactly matching COBOL's fall-through behavior.
- IMPORTANT: 2100-CALCULATE-TRANSACTION-FEES in the COBOL uses
  'COMPUTE WS-CALCULATED-FEE ROUNDED = ...' for BOTH the international fee
  and the cash-advance fee -- both computations explicitly have the ROUNDED
  clause. Fee rounding must be RoundingMode.HALF_UP, not truncation/DOWN. A
  prior refinement pass incorrectly changed this to truncation by wrongly
  generalizing from an unrelated program's rule -- do not repeat that error.
- Code-quality gap vs. the Azure conversion of this same program (audited):
  this version uses plain mutable instance fields and a `setResponse()`
  mutator instead of immutable value types. Restructure using Java records
  for the account profile, incoming transaction, and authorization response
  (mirroring the COBOL WS-CARD-ACCOUNT / WS-INCOMING-TRANSACTION /
  WS-AUTH-RESPONSE groupings), with defensive validation in the record's
  compact constructor (e.g. reject a null or wrong-length card number),
  instead of untyped mutable state.
""" + PRODUCTION_READINESS_CARDAUTH,
    ("azure", "REWARDCALC"): """\
- WS-BASE-POINTS is computed in COBOL as
  'COMPUTE WS-BASE-POINTS = WS-SPEND-AMOUNT * WS-MULTIPLIER' with NO
  'ROUNDED' clause, meaning standard COBOL truncation applies (fractional
  points are dropped). The current code applies HALF_UP rounding to this
  calculation instead, which inflates points on any fractional-cent spend
  (e.g. $19.99 * 3.00 = 59.97 should truncate to 59 points, not round to 60).
  Fix the base-points calculation to truncate toward zero, matching COBOL's
  default arithmetic. Do NOT change rounding for WS-REDEMPTION-VALUE, which
  DOES have an explicit ROUNDED clause in COBOL and should keep HALF_UP.
""",
    ("gemini", "REWARDCALC"): """\
- (Python only) The main processing method computes total_points_earned and
  redemption results but never returns or prints them anywhere -- there are
  no print() calls and no return statements in the entire file. This
  silently drops the COBOL 7000-WRITE-REWARDS-LEDGER-ENTRY paragraph,
  making every computed result an unrecoverable dead value. Add the missing
  ledger-writing/output logic so results are never silently discarded.
""",
    ("gemini", "ACHBATCH"): """\
- CRITICAL COMPLETENESS BUG (verified by direct inspection): the Java class
  has NO CONSTRUCTOR and NO SETTERS for any field (accountNumber,
  accountStatus, availableBalance, routingNumber, txnAmount, etc.). It is
  not instantiable with real data through any public API as delivered --
  add a public constructor (or builder) that accepts every field needed to
  run validate(), and add getters. This is the single highest-priority fix.
- validateRoutingNumber does character-by-character parsing with charAt(i)
  and no length/digit guard beforehand -- a routing number shorter than 9
  characters or containing a non-digit throws StringIndexOutOfBounds or
  silently miscomputes via Character.getNumericValue on a letter. Validate
  length==9 and all-digit BEFORE indexing into the string.
""",
    ("azure", "ACHBATCH"): """\
- The OFAC decline reason string ("DESTINATION COUNTRY ON OFAC SANCTIONS
  LIST" or similar, 42 characters) is longer than the 40-character
  fixed-width field validator, so a real sanctioned-country wire crashes
  with IllegalArgumentException instead of returning response code R07.
  Shorten the reason text to fit 40 characters (e.g. "OFAC SANCTIONED
  DESTINATION COUNTRY") or widen the field -- either way, an OFAC hold must
  never crash the validator.
- Java uses RoundingMode.UNNECESSARY (throws on non-2-decimal input) while
  the Python conversion uses ROUND_DOWN (silently truncates) for the same
  currency fields -- pick ONE behavior and match it in both languages so
  the two artifacts are actually equivalent to each other, not just each
  independently plausible.
""",
    ("gemini", "CHKHOLD"): """\
- CRITICAL COMPLETENESS BUG (verified by direct inspection): the Java class
  has NO CONSTRUCTOR and NO SETTERS for any field. It cannot be populated
  with real data through any public API -- add a public constructor (or
  builder) accepting every field the hold calculation needs, plus getters.
- Calling the hold logic with an unset/null depositType throws
  NullPointerException immediately on the switch statement (Java's `switch`
  on a null String always throws -- it does NOT fall through to a default
  case). Add an explicit null check before the switch and handle it as an
  invalid/unrecognized deposit type, matching COBOL's WHEN OTHER branch.
- Your own equivalence_review.md claims "the Java switch statement handles
  the default correctly" for a null depositType. That claim is WRONG --
  verify this yourself: a Java switch on a null reference throws NPE before
  it ever reaches any case, including default. Do not repeat this claim.
- Python has NO hardcoded threshold constants ($225 next-day, $5,525
  large-deposit, 30-day new-account, 2/5/9/7 hold-days, 4 overdraft
  trigger) -- they are pulled from an external dict with no defaults
  supplied in this file, making the regulatory figures unverifiable from
  this deliverable alone. Add the same named constants Java uses, with the
  same COBOL-matching values, as a fallback/default when the dict lacks a
  key.
""",
    ("gemini", "CLIELIG"): """\
- Same class of bug as CARDAUTH: the six eligibility gates (tenure,
  on-time-streak, delinquency, risk score, DTI ratio, recent-CLI) are
  COBOL's independent sequential IFs with NO ELSE, so the LAST failing
  gate determines the displayed decline reason. Your conversion uses an
  if/elif chain in both Java and Python, so the FIRST failing gate wins
  instead -- changing the decline reason shown to the customer/auditor
  whenever 2+ gates fail simultaneously. Your own equivalence_review.md
  already correctly identified this and marked the Java file "NOT
  EQUIVALENT" -- but the bug was never actually fixed, and the review never
  checked the Python file (which has the identical defect). Fix it in BOTH
  languages this time: use separate consecutive `if` statements with no
  early exit, so a later failing gate overwrites an earlier one's reason.
""",
    ("gemini", "FXWIRE"): """\
- The COBOL source has a genuine bug: WS-SAME-DAY-REQUESTED is reset to 'N'
  immediately before the IF that checks it, with no code path that ever
  sets it to 'Y' first -- so in the ORIGINAL COBOL, the same-day surcharge
  can NEVER actually fire, regardless of what the caller intended. This is
  ground truth to REPRODUCE faithfully (Azure's conversion does this
  correctly, with an explicit comment noting it's intentional), not a bug
  to silently fix by making the surcharge "work as probably intended."
  Your current Java and Python both let the caller-supplied same-day flag
  through directly, which means your code's behavior does NOT match the
  COBOL: e.g. a same-day EUR wire submitted after the 14:00 cutoff should
  bill a $45 fee per the COBOL (surcharge never applies), but your code
  currently bills $85 (surcharge incorrectly applied). Reproduce the
  COBOL's flag-reset-before-check sequence exactly, even though it means
  intentionally preserving a source-level bug.
""",
    ("gemini", "LOANAMRT"): """\
- CRITICAL FINANCIAL PRECISION BUG: COBOL computes the EMI rate factor as
  'COMPUTE WS-RATE-FACTOR ROUNDED = (1+WS-MONTHLY-RATE) ** WS-TERM-MONTHS'
  into a field declared PIC 9(3)V9999999 -- i.e. the COBOL explicitly
  rounds/truncates the rate factor to 7 decimal places and STORES it before
  reusing it in the EMI formula. Your conversion computes the same power
  but never rounds/stores it to 7 decimals before reuse -- it carries full
  BigDecimal/Decimal precision straight into the EMI numerator/denominator.
  This produces EMI values that can silently differ from COBOL's by a cent
  on real loan amounts. Fix: after computing the rate factor, explicitly
  round/quantize it to 7 decimal places (HALF_UP) and use THAT rounded
  value for every subsequent calculation, exactly mirroring the COBOL field
  declaration and ROUNDED clause.
- CRITICAL COMPLETENESS BUG (Java only, verified by direct inspection): the
  Java class has NO CONSTRUCTOR and NO SETTERS for any field -- it cannot
  be populated with real loan data through any public API. Add a public
  constructor (or builder) plus getters. The Python version already has a
  working __init__ -- match that level of usability in Java.
""",
    ("gemini", "MERCHSTL"): """\
- The interchange rate matrix (6 combinations of card type x entry mode) is
  implemented as a magic-string if/elif chain instead of an enum-keyed
  switch (Java) or tuple-keyed dict (Python) -- and because there is no
  final else/default branch, an unmatched card type leaves the rate
  uninitialized. In Java this means calculateInterchangeFee later throws
  NullPointerException; in Python the equivalent path silently defaults to
  Decimal('0') and proceeds, producing a settlement with zero interchange
  fee. Same backend, two different wrong behaviors for the same invalid
  input. Restructure both languages to use a proper lookup structure (an
  enum-pair switch in Java, a tuple-keyed dict in Python) with an explicit
  error path (not a silent zero) when the card type or entry mode doesn't
  match any known value.
""",
    ("gemini", "OVDPROC"): """\
- CRITICAL COMPLETENESS BUG (Java only, verified by direct inspection): the
  Java class has NO CONSTRUCTOR and NO SETTERS for any field -- it cannot
  be populated with real account/transaction data through any public API.
  Add a public constructor (or builder) plus getters, matching the
  Python version which already has a working, fully usable __init__.
- Your own equivalence_review.md flags the "sustained-overdraft fee still
  gets added even when the daily fee cap already zeroed out the per-item
  fee" behavior as a bug. It is NOT a bug -- verify this against the COBOL
  yourself: 3000-ASSESS-OVERDRAFT-FEE has the daily-cap check and the
  sustained-fee check as two SEPARATE, unconditional IF statements (COBOL
  lines ~154-155), so COBOL itself always adds the sustained fee
  regardless of whether the cap zeroed the per-item fee. Your code already
  reproduces this correctly -- do not "fix" it into a single combined
  conditional, that would introduce a real divergence from the source.
""",
}


def get_known_issues(backend: str, stem: str) -> str:
    specific = KNOWN_ISSUES.get((backend, stem), "")
    if not specific:
        return ERROR_HANDLING_GUIDANCE
    return specific + "\n" + ERROR_HANDLING_GUIDANCE
