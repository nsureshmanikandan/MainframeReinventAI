       IDENTIFICATION DIVISION.
       PROGRAM-ID. CLIELIG.
       AUTHOR. ACCENTURE-MAINFRAME-REINVENTION.
      *****************************************************************
      * CREDIT LINE INCREASE (CLI) ELIGIBILITY ENGINE                 *
      *                                                                *
      * EVALUATES A CARDMEMBER'S ELIGIBILITY FOR AN AUTOMATIC CREDIT  *
      * LIMIT INCREASE BASED ON ON-TIME PAYMENT HISTORY, CREDIT       *
      * UTILIZATION, ACCOUNT TENURE, RECENT DELINQUENCY, AND A        *
      * DEBT-TO-INCOME CHECK, THEN COMPUTES A CAPPED RECOMMENDED NEW  *
      * CREDIT LIMIT.                                                 *
      *****************************************************************
       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. IBM-Z17.
       OBJECT-COMPUTER. IBM-Z17.

       DATA DIVISION.
       WORKING-STORAGE SECTION.

      *---------------------------------------------------------------*
      * CARDMEMBER CREDIT PROFILE                                      *
      *---------------------------------------------------------------*
       01  WS-CARDMEMBER.
           05  WS-ACCOUNT-NUMBER           PIC X(16).
           05  WS-CURRENT-CREDIT-LIMIT     PIC 9(7)V99 COMP-3.
           05  WS-CURRENT-BALANCE          PIC 9(7)V99 COMP-3.
           05  WS-ACCOUNT-TENURE-MONTHS    PIC 9(3)      COMP-3.
           05  WS-ON-TIME-PMT-STREAK-MOS   PIC 9(3)      COMP-3.
           05  WS-DELINQUENCY-LAST-12MO    PIC 9(2)      COMP-3.
           05  WS-SELF-REPORTED-INCOME     PIC 9(7)V99 COMP-3.
           05  WS-ESTIMATED-MONTHLY-DEBT   PIC 9(6)V99 COMP-3.
           05  WS-INTERNAL-RISK-SCORE      PIC 9(3)      COMP-3.
           05  WS-RECENT-CLI-LAST-6MO      PIC X(1)      VALUE 'N'.
               88  RECEIVED-CLI-RECENTLY     VALUE 'Y'.

      *---------------------------------------------------------------*
      * ELIGIBILITY THRESHOLDS                                        *
      *---------------------------------------------------------------*
       01  WS-ELIGIBILITY-RULES.
           05  WS-MIN-TENURE-MONTHS        PIC 9(3)      COMP-3
                   VALUE 012.
           05  WS-MIN-ON-TIME-STREAK       PIC 9(3)      COMP-3
                   VALUE 006.
           05  WS-MAX-DELINQUENCY-12MO     PIC 9(2)      COMP-3
                   VALUE 00.
           05  WS-MIN-RISK-SCORE           PIC 9(3)      COMP-3
                   VALUE 680.
           05  WS-MAX-DTI-RATIO            PIC 9V999     COMP-3
                   VALUE 0.400.
           05  WS-HIGH-UTILIZATION-PCT     PIC 9V999     COMP-3
                   VALUE 0.700.
           05  WS-LOW-UTILIZATION-PCT      PIC 9V999     COMP-3
                   VALUE 0.300.

      *---------------------------------------------------------------*
      * CALCULATED RATIOS                                             *
      *---------------------------------------------------------------*
       01  WS-CALCULATED-RATIOS.
           05  WS-UTILIZATION-RATIO        PIC 9V9999    COMP-3.
           05  WS-DTI-RATIO                PIC 9V9999    COMP-3.
           05  WS-MONTHLY-INCOME           PIC 9(7)V99 COMP-3.

      *---------------------------------------------------------------*
      * ELIGIBILITY DECISION / RECOMMENDED LIMIT                       *
      *---------------------------------------------------------------*
       01  WS-DECISION.
           05  WS-IS-ELIGIBLE              PIC X(1)      VALUE 'N'.
               88  CLI-ELIGIBLE               VALUE 'Y'.
           05  WS-DECLINE-REASON           PIC X(40).
           05  WS-INCREASE-MULTIPLIER      PIC 9V99      COMP-3.
           05  WS-RECOMMENDED-INCREASE     PIC 9(6)V99 COMP-3.
           05  WS-RECOMMENDED-NEW-LIMIT    PIC 9(7)V99 COMP-3.
           05  WS-MAX-INCREASE-CAP         PIC 9(5)V99 COMP-3
                   VALUE 05000.00.

       PROCEDURE DIVISION.

       0000-MAIN-PROCESS.
           PERFORM 1000-CALCULATE-RATIOS
           PERFORM 2000-CHECK-BASIC-ELIGIBILITY
           IF CLI-ELIGIBLE
               PERFORM 3000-DETERMINE-INCREASE-MULTIPLIER
               PERFORM 4000-CALCULATE-RECOMMENDED-LIMIT
           END-IF
           PERFORM 9000-WRITE-DECISION
           STOP RUN.

       1000-CALCULATE-RATIOS.
           COMPUTE WS-UTILIZATION-RATIO ROUNDED =
               WS-CURRENT-BALANCE / WS-CURRENT-CREDIT-LIMIT

           COMPUTE WS-MONTHLY-INCOME ROUNDED =
               WS-SELF-REPORTED-INCOME / 12

           COMPUTE WS-DTI-RATIO ROUNDED =
               WS-ESTIMATED-MONTHLY-DEBT / WS-MONTHLY-INCOME.

       2000-CHECK-BASIC-ELIGIBILITY.
      *    ALL OF THE FOLLOWING MUST HOLD FOR AUTOMATIC CLI
      *    ELIGIBILITY: MINIMUM TENURE, ON-TIME PAYMENT STREAK, ZERO
      *    DELINQUENCIES IN THE TRAILING 12 MONTHS, A QUALIFYING RISK
      *    SCORE, AN ACCEPTABLE DEBT-TO-INCOME RATIO, AND NO CLI
      *    ALREADY GRANTED IN THE LAST 6 MONTHS
           SET CLI-ELIGIBLE TO TRUE
           MOVE SPACES TO WS-DECLINE-REASON

           IF WS-ACCOUNT-TENURE-MONTHS < WS-MIN-TENURE-MONTHS
               MOVE 'N' TO WS-IS-ELIGIBLE
               MOVE 'ACCOUNT TENURE BELOW MINIMUM' TO WS-DECLINE-REASON
           END-IF

           IF WS-ON-TIME-PMT-STREAK-MOS < WS-MIN-ON-TIME-STREAK
               MOVE 'N' TO WS-IS-ELIGIBLE
               MOVE 'INSUFFICIENT ON-TIME PAYMENT STREAK' TO
                   WS-DECLINE-REASON
           END-IF

           IF WS-DELINQUENCY-LAST-12MO > WS-MAX-DELINQUENCY-12MO
               MOVE 'N' TO WS-IS-ELIGIBLE
               MOVE 'DELINQUENCY IN TRAILING 12 MONTHS' TO
                   WS-DECLINE-REASON
           END-IF

           IF WS-INTERNAL-RISK-SCORE < WS-MIN-RISK-SCORE
               MOVE 'N' TO WS-IS-ELIGIBLE
               MOVE 'RISK SCORE BELOW MINIMUM THRESHOLD' TO
                   WS-DECLINE-REASON
           END-IF

           IF WS-DTI-RATIO > WS-MAX-DTI-RATIO
               MOVE 'N' TO WS-IS-ELIGIBLE
               MOVE 'DEBT-TO-INCOME RATIO TOO HIGH' TO WS-DECLINE-REASON
           END-IF

           IF RECEIVED-CLI-RECENTLY
               MOVE 'N' TO WS-IS-ELIGIBLE
               MOVE 'CLI ALREADY GRANTED WITHIN 6 MONTHS' TO
                   WS-DECLINE-REASON
           END-IF.

       3000-DETERMINE-INCREASE-MULTIPLIER.
      *    HIGH UTILIZATION (>70%) SUPPORTS A LARGER INCREASE TO
      *    RESTORE HEALTHY UTILIZATION; LOW UTILIZATION (<30%) GETS
      *    A SMALLER, MORE CONSERVATIVE INCREASE
           EVALUATE TRUE
               WHEN WS-UTILIZATION-RATIO > WS-HIGH-UTILIZATION-PCT
                   MOVE 0.50 TO WS-INCREASE-MULTIPLIER
               WHEN WS-UTILIZATION-RATIO < WS-LOW-UTILIZATION-PCT
                   MOVE 0.15 TO WS-INCREASE-MULTIPLIER
               WHEN OTHER
                   MOVE 0.30 TO WS-INCREASE-MULTIPLIER
           END-EVALUATE.

       4000-CALCULATE-RECOMMENDED-LIMIT.
           COMPUTE WS-RECOMMENDED-INCREASE ROUNDED =
               WS-CURRENT-CREDIT-LIMIT * WS-INCREASE-MULTIPLIER

           IF WS-RECOMMENDED-INCREASE > WS-MAX-INCREASE-CAP
               MOVE WS-MAX-INCREASE-CAP TO WS-RECOMMENDED-INCREASE
           END-IF

           COMPUTE WS-RECOMMENDED-NEW-LIMIT =
               WS-CURRENT-CREDIT-LIMIT + WS-RECOMMENDED-INCREASE.

       9000-WRITE-DECISION.
           DISPLAY 'ACCOUNT: ' WS-ACCOUNT-NUMBER
           DISPLAY 'ELIGIBLE: ' WS-IS-ELIGIBLE
           IF CLI-ELIGIBLE
               DISPLAY 'RECOMMENDED INCREASE: ' WS-RECOMMENDED-INCREASE
               DISPLAY 'RECOMMENDED NEW LIMIT: ' WS-RECOMMENDED-NEW-LIMIT
           ELSE
               DISPLAY 'DECLINE REASON: ' WS-DECLINE-REASON
           END-IF.
