import type { Backend } from "./types";

export interface QualityScore {
  businessRuleFidelity: number;
  financialPrecision: number;
  completeness: number;
  codeQuality: number;
  productionReadiness: number;
  overall: number;
  verdict: string;
  // ISO date this score was actually verified against the code by reading
  // it directly. This is a manually-recorded audit, not a live computation
  // -- re-running a migration or refine cycle changes the code but does NOT
  // recompute this score automatically. Compare against the result's
  // updated_at in the UI to detect when a score has gone stale.
  auditedAt: string;
}

// Scores from an independent audit (not the model's own equivalence_review,
// which is a claim to verify, not ground truth). Keyed by "<backend>:<stem>".
// NOTE: "azure" scores reflect whichever Azure model produced the code at
// audit time (see verdict) -- switching the model dropdown and re-running
// will make this stale until the next manual re-audit.
//
// Error-handling pass (2026-08-06): a static scan found ZERO of the 20
// artifacts (10 programs x 2 backends) used a custom/domain-specific
// exception type -- all threw generic IllegalArgumentException/
// RuntimeException in Java or let built-in exceptions propagate in Python.
// Added ERROR_HANDLING_GUIDANCE to known_issues.py (applied universally via
// get_known_issues()), refined all 20, and verified via static scan that
// all 20 now define and actually use a custom exception class for real
// input validation (spot-checked gemini:CARDAUTH's CardAuthValidationException
// in detail -- null/length/range checks at entry points, not just declared).
// Code Quality bumped +1 (capped at 10) everywhere this was verified.
export const QUALITY_SCORES: Record<string, QualityScore> = {
  "azure:CARDAUTH": {
    businessRuleFidelity: 9,
    financialPrecision: 9,
    completeness: 9,
    codeQuality: 10,
    productionReadiness: 9,
    overall: 9.2,
    verdict:
      "gpt-5.6-sol, production-readiness pass 2026-08-06: replaced System.out with java.util.logging.Logger, externalized every threshold into a validated AuthorizationConfig record. Error-handling pass 2026-08-06: added CardAuthValidationException used for real null/length/range validation at entry points -- verified in code, not just declared.",
    auditedAt: "2026-08-06",
  },
  "azure:REWARDCALC": {
    businessRuleFidelity: 9,
    financialPrecision: 9,
    completeness: 9,
    codeQuality: 10,
    productionReadiness: 7,
    overall: 8.8,
    verdict:
      "gpt-5.6-sol, fresh run 2026-08-06: fixed the earlier mini rounding bug -- base-points now correctly truncates while redemption value correctly rounds HALF_UP. Error-handling pass 2026-08-06: custom validation exception added and verified in use, replacing generic Java exceptions.",
    auditedAt: "2026-08-06",
  },
  "azure:STMTGEN": {
    businessRuleFidelity: 9,
    financialPrecision: 9,
    completeness: 9,
    codeQuality: 10,
    productionReadiness: 7,
    overall: 8.8,
    verdict:
      "gpt-5.6-sol, verified 2026-08-06 line-by-line against every COBOL rule (annual fee, late-fee tiers, grace period, CARD Act payment allocation). Error-handling pass 2026-08-06: custom validation exception added and verified in use.",
    auditedAt: "2026-08-06",
  },
  "gemini:CARDAUTH": {
    businessRuleFidelity: 9,
    financialPrecision: 9,
    completeness: 8,
    codeQuality: 9,
    productionReadiness: 8,
    overall: 8.6,
    verdict:
      "Production-readiness pass 2026-08-06: adopted records matching Azure's pattern, added Logger and externalized config. Re-confirmed no else-if or rounding regression. Error-handling pass 2026-08-06: custom validation exception added and verified in use, closing the last real gap vs. Azure's version.",
    auditedAt: "2026-08-06",
  },
  "gemini:REWARDCALC": {
    businessRuleFidelity: 8,
    financialPrecision: 8,
    completeness: 9,
    codeQuality: 9,
    productionReadiness: 7,
    overall: 8.2,
    verdict:
      "Refined 2026-08-06: Python's dropped ledger-write paragraph fixed via structured logging plus a per-transaction context dict. Error-handling pass 2026-08-06: custom validation exception added and verified in use.",
    auditedAt: "2026-08-06",
  },
  "gemini:STMTGEN": {
    businessRuleFidelity: 9,
    financialPrecision: 9,
    completeness: 9,
    codeQuality: 9,
    productionReadiness: 8,
    overall: 8.8,
    verdict:
      "Best conversion in the original set. Its own equivalence_review flags 2 'critical' issues that are actually mathematically equivalent to the COBOL -- false positives. Error-handling pass 2026-08-06: custom validation exception added and verified in use.",
    auditedAt: "2026-08-06",
  },
  "azure:ACHBATCH": {
    businessRuleFidelity: 8,
    financialPrecision: 7,
    completeness: 8,
    codeQuality: 9,
    productionReadiness: 6,
    overall: 7.6,
    verdict:
      "Checksum weights, thresholds, and OFAC list correct. Real bug: a 42-char OFAC decline reason exceeds the 40-char field validator, crashing instead of returning R07. Java/Python rounding-mode mismatch also unresolved. Error-handling pass 2026-08-06: custom validation exception added and verified in use.",
    auditedAt: "2026-08-06",
  },
  "gemini:ACHBATCH": {
    businessRuleFidelity: 9,
    financialPrecision: 7,
    completeness: 8,
    codeQuality: 8,
    productionReadiness: 3,
    overall: 7.0,
    verdict:
      "Verified: real public constructor now exists, routing-number parsing checks length==9 and all-digit before indexing. Error-handling pass 2026-08-06: custom validation exception added and verified in use. Production readiness still print-based, untouched.",
    auditedAt: "2026-08-06",
  },
  "azure:CHKHOLD": {
    businessRuleFidelity: 10,
    financialPrecision: 9,
    completeness: 9,
    codeQuality: 10,
    productionReadiness: 7,
    overall: 9.0,
    verdict:
      "All thresholds and the overwrite-then-add hold-day precedence match COBOL exactly in both languages. Minor Java/Python output-formatting mismatch not caught by self-review. Error-handling pass 2026-08-06: custom validation exception added and verified in use.",
    auditedAt: "2026-08-06",
  },
  "gemini:CHKHOLD": {
    businessRuleFidelity: 7,
    financialPrecision: 6,
    completeness: 8,
    codeQuality: 8,
    productionReadiness: 6,
    overall: 7.0,
    verdict:
      "Verified: real public constructor exists, explicit null check guards the depositType switch (fixed NPE), Python has the same hardcoded regulatory constants as Java. Error-handling pass 2026-08-06: custom validation exception added and verified in use. A separate, unverified equivalence_review claim about EVALUATE-vs-if-chain semantics is still pending.",
    auditedAt: "2026-08-06",
  },
  "azure:CLIELIG": {
    businessRuleFidelity: 10,
    financialPrecision: 9,
    completeness: 10,
    codeQuality: 10,
    productionReadiness: 6,
    overall: 9.0,
    verdict:
      "Correctly uses independent if-blocks in both languages, faithfully preserving COBOL's last-failing-gate-wins decline reason. All thresholds, multiplier tiers, and cap ordering verified exact. Error-handling pass 2026-08-06: custom validation exception added and verified in use.",
    auditedAt: "2026-08-06",
  },
  "gemini:CLIELIG": {
    businessRuleFidelity: 9,
    financialPrecision: 9,
    completeness: 9,
    codeQuality: 8,
    productionReadiness: 5,
    overall: 8.0,
    verdict:
      "Verified: all 6 eligibility gates now use separate consecutive if statements, correctly preserving COBOL's last-failing-gate-wins decline reason. The remaining else-if (utilization-tier multiplier) is legitimately correct there. Error-handling pass 2026-08-06: custom validation exception added and verified in use.",
    auditedAt: "2026-08-06",
  },
  "azure:FXWIRE": {
    businessRuleFidelity: 9,
    financialPrecision: 9,
    completeness: 7,
    codeQuality: 9,
    productionReadiness: 5,
    overall: 7.8,
    verdict:
      "The COBOL itself has a dead-code same-day-surcharge flag -- Azure faithfully preserved this exact quirk in both languages, with comments explicitly noting it's intentional. Error-handling pass 2026-08-06: custom validation exception added and verified in use.",
    auditedAt: "2026-08-06",
  },
  "gemini:FXWIRE": {
    businessRuleFidelity: 9,
    financialPrecision: 6,
    completeness: 6,
    codeQuality: 7,
    productionReadiness: 4,
    overall: 6.4,
    verdict:
      "Verified: the dead same-day-surcharge quirk is now faithfully reproduced (flag hardcoded false immediately before the check, matching COBOL's own bug). Error-handling pass 2026-08-06: custom validation exception added and verified in use. Completeness/production-readiness weren't targeted and remain unchanged.",
    auditedAt: "2026-08-06",
  },
  "azure:LOANAMRT": {
    businessRuleFidelity: 9,
    financialPrecision: 9,
    completeness: 9,
    codeQuality: 9,
    productionReadiness: 5,
    overall: 8.2,
    verdict:
      "Correctly replicates COBOL's two-stage rounding of the EMI rate factor before reuse -- exactly the subtle financial-precision detail that's easy to miss. Loop bounds and payoff proration also verified correct. Error-handling pass 2026-08-06: custom validation exception added and verified in use.",
    auditedAt: "2026-08-06",
  },
  "gemini:LOANAMRT": {
    businessRuleFidelity: 8,
    financialPrecision: 9,
    completeness: 8,
    codeQuality: 7,
    productionReadiness: 3,
    overall: 7.0,
    verdict:
      "Verified: EMI rate factor now explicitly rounded via .setScale(7, HALF_UP) before reuse, matching COBOL exactly, and a real public constructor exists. Error-handling pass 2026-08-06: custom validation exception added and verified in use. Production readiness still print-based, untouched.",
    auditedAt: "2026-08-06",
  },
  "azure:MERCHSTL": {
    businessRuleFidelity: 9,
    financialPrecision: 10,
    completeness: 9,
    codeQuality: 10,
    productionReadiness: 6,
    overall: 8.8,
    verdict:
      "Verified all 6 cells of the interchange rate matrix independently, including the deliberate CP/CP collision trap -- no swaps found, using collision-proof enums (Java) and tuple-keyed dicts (Python). Error-handling pass 2026-08-06: custom validation exception added and verified in use.",
    auditedAt: "2026-08-06",
  },
  "gemini:MERCHSTL": {
    businessRuleFidelity: 9,
    financialPrecision: 8,
    completeness: 9,
    codeQuality: 9,
    productionReadiness: 4,
    overall: 7.8,
    verdict:
      "Went beyond the requested fix -- Java now uses type-safe CardType/EntryMode enums with a fully-populated EnumMap (invalid combinations now structurally impossible), Python explicitly raises SettlementException instead of silently defaulting to zero. Error-handling pass 2026-08-06: custom validation exception added and verified in use.",
    auditedAt: "2026-08-06",
  },
  "azure:OVDPROC": {
    businessRuleFidelity: 10,
    financialPrecision: 10,
    completeness: 10,
    codeQuality: 10,
    productionReadiness: 7,
    overall: 8.9,
    verdict:
      "Sweep-before-courtesy-overdraft ordering, debit-card opt-in gate, and the unconditional sustained-overdraft surcharge all correctly preserved in both languages. Error-handling pass 2026-08-06: custom validation exception confirmed present (already had strong defensive design; no score headroom left on Code Quality).",
    auditedAt: "2026-08-06",
  },
  "gemini:OVDPROC": {
    businessRuleFidelity: 8,
    financialPrecision: 7,
    completeness: 8,
    codeQuality: 8,
    productionReadiness: 4,
    overall: 7.0,
    verdict:
      "Fixed the instantiability problem via method parameters instead of a constructor -- more thread-safe than what was asked for. Error-handling pass 2026-08-06: custom validation exception added and verified in use.",
    auditedAt: "2026-08-06",
  },
};

export function getQualityScore(backend: Backend, stem: string): QualityScore | undefined {
  return QUALITY_SCORES[`${backend}:${stem}`];
}
