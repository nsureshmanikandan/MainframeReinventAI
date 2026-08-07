       IDENTIFICATION DIVISION.
       PROGRAM-ID. LOANAMRT.
       AUTHOR. ACCENTURE-MAINFRAME-REINVENTION.
      *****************************************************************
      * PERSONAL LOAN AMORTIZATION ENGINE                             *
      *                                                                *
      * COMPUTES THE FIXED MONTHLY INSTALLMENT (EMI) FOR A PERSONAL   *
      * LOAN, BUILDS A FULL PRINCIPAL/INTEREST AMORTIZATION SCHEDULE, *
      * APPLIES AN OPTIONAL EXTRA PRINCIPAL PAYMENT EACH MONTH,       *
      * ASSESSES LATE FEES ON MISSED PAYMENTS, AND CALCULATES AN      *
      * EARLY-PAYOFF QUOTE WITH A PREPAYMENT PENALTY DURING THE       *
      * LOAN'S FIRST 12 MONTHS.                                       *
      *****************************************************************
       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. IBM-Z17.
       OBJECT-COMPUTER. IBM-Z17.

       DATA DIVISION.
       WORKING-STORAGE SECTION.

      *---------------------------------------------------------------*
      * LOAN ACCOUNT PROFILE                                          *
      *---------------------------------------------------------------*
       01  WS-LOAN-ACCOUNT.
           05  WS-LOAN-NUMBER              PIC X(12).
           05  WS-ORIGINAL-PRINCIPAL       PIC 9(9)V99 COMP-3.
           05  WS-CURRENT-PRINCIPAL        PIC 9(9)V99 COMP-3.
           05  WS-ANNUAL-PCT-RATE          PIC 9(2)V999 COMP-3.
           05  WS-TERM-MONTHS              PIC 9(3)      COMP-3.
           05  WS-MONTHS-ELAPSED           PIC 9(3)      COMP-3.
           05  WS-LOAN-ORIGINATION-DATE    PIC X(8).
           05  WS-CONSECUTIVE-LATE-PMTS    PIC 9(2)      COMP-3.

      *---------------------------------------------------------------*
      * PAYMENT / SCHEDULE INPUTS                                     *
      *---------------------------------------------------------------*
       01  WS-PAYMENT-INPUT.
           05  WS-EXTRA-PRINCIPAL-PMT      PIC 9(7)V99 COMP-3.
           05  WS-DAYS-PAST-DUE            PIC 9(3)      COMP-3.
           05  WS-REQUEST-PAYOFF-QUOTE     PIC X(1)      VALUE 'N'.
               88  PAYOFF-QUOTE-REQUESTED    VALUE 'Y'.

      *---------------------------------------------------------------*
      * EMI CALCULATION WORK AREAS                                    *
      *---------------------------------------------------------------*
       01  WS-EMI-CALC.
           05  WS-MONTHLY-RATE             PIC 9V9999999 COMP-3.
           05  WS-RATE-FACTOR              PIC 9(3)V9999999 COMP-3.
           05  WS-MONTHLY-INSTALLMENT      PIC 9(7)V99 COMP-3.

      *---------------------------------------------------------------*
      * AMORTIZATION SCHEDULE TABLE (UP TO 360 MONTHS / 30 YEARS)     *
      *---------------------------------------------------------------*
       01  WS-SCHEDULE-TABLE.
           05  WS-SCHEDULE-ENTRY OCCURS 360 TIMES
                   INDEXED BY WS-SCHED-IDX.
               10  WS-SCHED-MONTH-NUM      PIC 9(3).
               10  WS-SCHED-PRINCIPAL-PMT  PIC 9(7)V99.
               10  WS-SCHED-INTEREST-PMT   PIC 9(7)V99.
               10  WS-SCHED-EXTRA-PMT      PIC 9(7)V99.
               10  WS-SCHED-REMAINING-BAL  PIC 9(9)V99.
       01  WS-SCHEDULE-MONTHS-BUILT        PIC 9(3)      COMP-3 VALUE ZERO.

      *---------------------------------------------------------------*
      * LATE FEE / PENALTY WORK AREAS                                 *
      *---------------------------------------------------------------*
       01  WS-FEES.
           05  WS-LATE-FEE                 PIC 9(3)V99 COMP-3 VALUE ZERO.
           05  WS-STANDARD-LATE-FEE        PIC 9(3)V99 COMP-3 VALUE 035.00.
           05  WS-GRACE-PERIOD-DAYS        PIC 9(2)      COMP-3 VALUE 15.
           05  WS-PREPAYMENT-PENALTY-PCT   PIC 9V999     COMP-3 VALUE 0.020.
           05  WS-PREPAYMENT-PENALTY-MONTHS PIC 9(2)     COMP-3 VALUE 12.

      *---------------------------------------------------------------*
      * PAYOFF QUOTE OUTPUT                                           *
      *---------------------------------------------------------------*
       01  WS-PAYOFF-QUOTE.
           05  WS-ACCRUED-INTEREST-TO-DATE PIC 9(7)V99 COMP-3.
           05  WS-PREPAYMENT-PENALTY-AMT   PIC 9(6)V99 COMP-3.
           05  WS-TOTAL-PAYOFF-AMOUNT      PIC 9(9)V99 COMP-3.

       PROCEDURE DIVISION.

       0000-MAIN-PROCESS.
           PERFORM 1000-CALCULATE-EMI
           PERFORM 2000-BUILD-AMORTIZATION-SCHEDULE
           PERFORM 3000-ASSESS-LATE-FEE
           IF PAYOFF-QUOTE-REQUESTED
               PERFORM 4000-CALCULATE-PAYOFF-QUOTE
           END-IF
           PERFORM 9000-PRINT-LOAN-SUMMARY
           STOP RUN.

       1000-CALCULATE-EMI.
      *    MONTHLY RATE = ANNUAL RATE / 12
           COMPUTE WS-MONTHLY-RATE ROUNDED =
               WS-ANNUAL-PCT-RATE / 12

      *    STANDARD AMORTIZING LOAN FORMULA:
      *    EMI = P * r * (1+r)^n / ((1+r)^n - 1)
           COMPUTE WS-RATE-FACTOR ROUNDED =
               (1 + WS-MONTHLY-RATE) ** WS-TERM-MONTHS

           COMPUTE WS-MONTHLY-INSTALLMENT ROUNDED =
               (WS-ORIGINAL-PRINCIPAL * WS-MONTHLY-RATE * WS-RATE-FACTOR)
               / (WS-RATE-FACTOR - 1).

       2000-BUILD-AMORTIZATION-SCHEDULE.
           MOVE WS-ORIGINAL-PRINCIPAL TO WS-CURRENT-PRINCIPAL
           MOVE ZERO TO WS-SCHEDULE-MONTHS-BUILT

           PERFORM VARYING WS-SCHED-IDX FROM 1 BY 1
               UNTIL WS-SCHED-IDX > WS-TERM-MONTHS
                  OR WS-CURRENT-PRINCIPAL <= ZERO

               PERFORM 2100-CALCULATE-MONTH-SPLIT

               SET WS-SCHED-IDX UP BY 0
               ADD 1 TO WS-SCHEDULE-MONTHS-BUILT
           END-PERFORM.

       2100-CALCULATE-MONTH-SPLIT.
      *    EACH MONTH'S INTEREST PORTION IS THE CURRENT BALANCE TIMES
      *    THE MONTHLY RATE; THE REMAINDER OF THE INSTALLMENT REDUCES
      *    PRINCIPAL, PLUS ANY VOLUNTARY EXTRA PRINCIPAL PAYMENT
           COMPUTE WS-SCHED-INTEREST-PMT (WS-SCHED-IDX) ROUNDED =
               WS-CURRENT-PRINCIPAL * WS-MONTHLY-RATE

           COMPUTE WS-SCHED-PRINCIPAL-PMT (WS-SCHED-IDX) =
               WS-MONTHLY-INSTALLMENT -
               WS-SCHED-INTEREST-PMT (WS-SCHED-IDX)

           MOVE WS-EXTRA-PRINCIPAL-PMT TO WS-SCHED-EXTRA-PMT (WS-SCHED-IDX)

           COMPUTE WS-CURRENT-PRINCIPAL =
               WS-CURRENT-PRINCIPAL -
               WS-SCHED-PRINCIPAL-PMT (WS-SCHED-IDX) -
               WS-SCHED-EXTRA-PMT (WS-SCHED-IDX)

           IF WS-CURRENT-PRINCIPAL < ZERO
               MOVE ZERO TO WS-CURRENT-PRINCIPAL
           END-IF

           MOVE WS-CURRENT-PRINCIPAL TO
               WS-SCHED-REMAINING-BAL (WS-SCHED-IDX).

       3000-ASSESS-LATE-FEE.
      *    RULE: PAYMENTS MORE THAN 15 DAYS PAST DUE INCUR A FLAT $35
      *    LATE FEE; THREE OR MORE CONSECUTIVE LATE PAYMENTS ESCALATE
      *    THE FEE TO 150% OF STANDARD
           MOVE ZERO TO WS-LATE-FEE
           IF WS-DAYS-PAST-DUE > WS-GRACE-PERIOD-DAYS
               IF WS-CONSECUTIVE-LATE-PMTS >= 3
                   COMPUTE WS-LATE-FEE ROUNDED =
                       WS-STANDARD-LATE-FEE * 1.5
               ELSE
                   MOVE WS-STANDARD-LATE-FEE TO WS-LATE-FEE
               END-IF
           END-IF.

       4000-CALCULATE-PAYOFF-QUOTE.
      *    ACCRUED INTEREST SINCE LAST PAYMENT, PRORATED BY DAYS PAST
      *    DUE OVER A 30-DAY MONTH CONVENTION
           COMPUTE WS-ACCRUED-INTEREST-TO-DATE ROUNDED =
               WS-CURRENT-PRINCIPAL * WS-MONTHLY-RATE *
               (WS-DAYS-PAST-DUE / 30)

      *    PREPAYMENT PENALTY APPLIES ONLY WITHIN THE FIRST 12 MONTHS
      *    OF THE LOAN, CHARGED AS 2% OF THE REMAINING PRINCIPAL
           MOVE ZERO TO WS-PREPAYMENT-PENALTY-AMT
           IF WS-MONTHS-ELAPSED < WS-PREPAYMENT-PENALTY-MONTHS
               COMPUTE WS-PREPAYMENT-PENALTY-AMT ROUNDED =
                   WS-CURRENT-PRINCIPAL * WS-PREPAYMENT-PENALTY-PCT
           END-IF

           COMPUTE WS-TOTAL-PAYOFF-AMOUNT =
               WS-CURRENT-PRINCIPAL + WS-ACCRUED-INTEREST-TO-DATE +
               WS-PREPAYMENT-PENALTY-AMT + WS-LATE-FEE.

       9000-PRINT-LOAN-SUMMARY.
           DISPLAY 'LOAN: ' WS-LOAN-NUMBER
           DISPLAY 'MONTHLY INSTALLMENT: ' WS-MONTHLY-INSTALLMENT
           DISPLAY 'SCHEDULE MONTHS BUILT: ' WS-SCHEDULE-MONTHS-BUILT
           DISPLAY 'LATE FEE ASSESSED: ' WS-LATE-FEE
           IF PAYOFF-QUOTE-REQUESTED
               DISPLAY 'PAYOFF QUOTE: ' WS-TOTAL-PAYOFF-AMOUNT
               DISPLAY 'PREPAYMENT PENALTY: ' WS-PREPAYMENT-PENALTY-AMT
           END-IF.
