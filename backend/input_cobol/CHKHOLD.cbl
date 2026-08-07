       IDENTIFICATION DIVISION.
       PROGRAM-ID. CHKHOLD.
       AUTHOR. ACCENTURE-MAINFRAME-REINVENTION.
      *****************************************************************
      * CHECK DEPOSIT FUNDS AVAILABILITY ENGINE (REG CC STYLE)        *
      *                                                                *
      * DETERMINES HOW MUCH OF A DEPOSITED ITEM IS AVAILABLE NEXT     *
      * BUSINESS DAY VERSUS PLACED ON HOLD, BASED ON DEPOSIT TYPE     *
      * (CASH, LOCAL CHECK, NON-LOCAL CHECK), ACCOUNT AGE, LARGE-      *
      * DEPOSIT EXCEPTION HOLDS, AND A "REASONABLE CAUSE" EXCEPTION   *
      * HOLD FOR ACCOUNTS WITH A RECENT OVERDRAFT HISTORY.            *
      *****************************************************************
       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. IBM-Z17.
       OBJECT-COMPUTER. IBM-Z17.

       DATA DIVISION.
       WORKING-STORAGE SECTION.

      *---------------------------------------------------------------*
      * ACCOUNT PROFILE                                                *
      *---------------------------------------------------------------*
       01  WS-ACCOUNT.
           05  WS-ACCOUNT-NUMBER           PIC X(17).
           05  WS-ACCOUNT-OPEN-DATE        PIC X(8).
           05  WS-CURRENT-DATE             PIC X(8).
           05  WS-ACCOUNT-AGE-DAYS         PIC 9(5)      COMP-3.
           05  WS-OVERDRAFT-COUNT-6MO      PIC 9(2)      COMP-3.
           05  WS-AGGREGATE-DEPOSITS-TODAY PIC 9(9)V99 COMP-3.

      *---------------------------------------------------------------*
      * INCOMING DEPOSIT                                               *
      *---------------------------------------------------------------*
       01  WS-DEPOSIT.
           05  WS-DEPOSIT-AMOUNT           PIC 9(7)V99 COMP-3.
           05  WS-DEPOSIT-TYPE             PIC X(2).
               88  DEPOSIT-CASH              VALUE 'CA'.
               88  DEPOSIT-LOCAL-CHECK       VALUE 'LC'.
               88  DEPOSIT-NONLOCAL-CHECK    VALUE 'NC'.
               88  DEPOSIT-ACH-CREDIT        VALUE 'AC'.
               88  DEPOSIT-US-TREASURY-CHECK VALUE 'TC'.
           05  WS-DEPOSIT-DATE             PIC X(8).

      *---------------------------------------------------------------*
      * REGULATORY THRESHOLDS                                         *
      *---------------------------------------------------------------*
       01  WS-THRESHOLDS.
           05  WS-NEXT-DAY-AVAIL-AMOUNT    PIC 9(3)V99 COMP-3
                   VALUE 225.00.
           05  WS-LARGE-DEPOSIT-THRESHOLD  PIC 9(6)V99 COMP-3
                   VALUE 5525.00.
           05  WS-NEW-ACCOUNT-AGE-DAYS     PIC 9(3)      COMP-3
                   VALUE 030.
           05  WS-LOCAL-CHECK-HOLD-DAYS    PIC 9(2)      COMP-3
                   VALUE 02.
           05  WS-NONLOCAL-CHECK-HOLD-DAYS PIC 9(2)      COMP-3
                   VALUE 05.
           05  WS-NEW-ACCOUNT-HOLD-DAYS    PIC 9(2)      COMP-3
                   VALUE 09.
           05  WS-EXCEPTION-HOLD-DAYS      PIC 9(2)      COMP-3
                   VALUE 07.
           05  WS-OVERDRAFT-EXCEPTION-TRIGGER PIC 9        COMP-3
                   VALUE 4.

      *---------------------------------------------------------------*
      * HOLD CALCULATION RESULT                                       *
      *---------------------------------------------------------------*
       01  WS-HOLD-RESULT.
           05  WS-IMMEDIATE-AVAILABLE      PIC 9(7)V99 COMP-3.
           05  WS-NEXT-DAY-AVAILABLE       PIC 9(7)V99 COMP-3.
           05  WS-AMOUNT-ON-HOLD           PIC 9(7)V99 COMP-3.
           05  WS-STANDARD-HOLD-DAYS       PIC 9(2)      COMP-3.
           05  WS-IS-NEW-ACCOUNT           PIC X(1)      VALUE 'N'.
               88  NEW-ACCOUNT-EXCEPTION     VALUE 'Y'.
           05  WS-IS-LARGE-DEPOSIT         PIC X(1)      VALUE 'N'.
               88  LARGE-DEPOSIT-EXCEPTION   VALUE 'Y'.
           05  WS-IS-REASONABLE-CAUSE      PIC X(1)      VALUE 'N'.
               88  REASONABLE-CAUSE-EXCEPTION VALUE 'Y'.
           05  WS-FUNDS-AVAILABLE-DATE     PIC X(8).
           05  WS-HOLD-NOTICE-REQUIRED     PIC X(1)      VALUE 'N'.
               88  HOLD-NOTICE-REQUIRED-YES  VALUE 'Y'.

       PROCEDURE DIVISION.

       0000-MAIN-PROCESS.
           PERFORM 1000-DETERMINE-STANDARD-HOLD-PERIOD
           PERFORM 2000-CHECK-NEW-ACCOUNT-EXCEPTION
           PERFORM 3000-CHECK-LARGE-DEPOSIT-EXCEPTION
           PERFORM 4000-CHECK-REASONABLE-CAUSE-EXCEPTION
           PERFORM 5000-CALCULATE-AVAILABILITY-SPLIT
           PERFORM 6000-DETERMINE-NOTICE-REQUIREMENT
           PERFORM 9000-WRITE-HOLD-DECISION
           STOP RUN.

       1000-DETERMINE-STANDARD-HOLD-PERIOD.
      *    CASH, ACH CREDITS, AND US TREASURY CHECKS ARE AVAILABLE
      *    THE NEXT BUSINESS DAY IN FULL, NO STANDARD HOLD APPLIES
           EVALUATE TRUE
               WHEN DEPOSIT-CASH
                   MOVE ZERO TO WS-STANDARD-HOLD-DAYS
               WHEN DEPOSIT-ACH-CREDIT
                   MOVE ZERO TO WS-STANDARD-HOLD-DAYS
               WHEN DEPOSIT-US-TREASURY-CHECK
                   MOVE ZERO TO WS-STANDARD-HOLD-DAYS
               WHEN DEPOSIT-LOCAL-CHECK
                   MOVE WS-LOCAL-CHECK-HOLD-DAYS TO WS-STANDARD-HOLD-DAYS
               WHEN DEPOSIT-NONLOCAL-CHECK
                   MOVE WS-NONLOCAL-CHECK-HOLD-DAYS TO
                       WS-STANDARD-HOLD-DAYS
               WHEN OTHER
                   MOVE WS-NONLOCAL-CHECK-HOLD-DAYS TO
                       WS-STANDARD-HOLD-DAYS
           END-EVALUATE.

       2000-CHECK-NEW-ACCOUNT-EXCEPTION.
      *    ACCOUNTS OPEN LESS THAN 30 DAYS GET AN EXTENDED HOLD
      *    PERIOD ON CHECK DEPOSITS (NOT ON CASH OR ACH)
           MOVE 'N' TO WS-IS-NEW-ACCOUNT
           IF WS-ACCOUNT-AGE-DAYS < WS-NEW-ACCOUNT-AGE-DAYS
              AND (DEPOSIT-LOCAL-CHECK OR DEPOSIT-NONLOCAL-CHECK)
               SET NEW-ACCOUNT-EXCEPTION TO TRUE
               MOVE WS-NEW-ACCOUNT-HOLD-DAYS TO WS-STANDARD-HOLD-DAYS
           END-IF.

       3000-CHECK-LARGE-DEPOSIT-EXCEPTION.
      *    THE FIRST $5,525 OF AGGREGATE SAME-DAY CHECK DEPOSITS
      *    FOLLOWS THE STANDARD SCHEDULE; ANY EXCESS ABOVE THAT
      *    AMOUNT GETS AN ADDITIONAL EXTENDED HOLD
           MOVE 'N' TO WS-IS-LARGE-DEPOSIT
           IF (WS-AGGREGATE-DEPOSITS-TODAY + WS-DEPOSIT-AMOUNT)
                   > WS-LARGE-DEPOSIT-THRESHOLD
              AND (DEPOSIT-LOCAL-CHECK OR DEPOSIT-NONLOCAL-CHECK)
               SET LARGE-DEPOSIT-EXCEPTION TO TRUE
               ADD WS-EXCEPTION-HOLD-DAYS TO WS-STANDARD-HOLD-DAYS
           END-IF.

       4000-CHECK-REASONABLE-CAUSE-EXCEPTION.
      *    FOUR OR MORE OVERDRAFTS IN THE TRAILING 6 MONTHS GIVES THE
      *    BANK REASONABLE CAUSE TO PLACE AN ADDITIONAL EXCEPTION HOLD
           MOVE 'N' TO WS-IS-REASONABLE-CAUSE
           IF WS-OVERDRAFT-COUNT-6MO >= WS-OVERDRAFT-EXCEPTION-TRIGGER
              AND (DEPOSIT-LOCAL-CHECK OR DEPOSIT-NONLOCAL-CHECK)
               SET REASONABLE-CAUSE-EXCEPTION TO TRUE
               ADD WS-EXCEPTION-HOLD-DAYS TO WS-STANDARD-HOLD-DAYS
           END-IF.

       5000-CALCULATE-AVAILABILITY-SPLIT.
      *    UP TO $225 OF A CHECK DEPOSIT IS AVAILABLE THE NEXT
      *    BUSINESS DAY REGARDLESS OF THE STANDARD HOLD; THE REMAINDER
      *    FOLLOWS THE COMPUTED HOLD SCHEDULE
           IF WS-STANDARD-HOLD-DAYS = ZERO
               MOVE WS-DEPOSIT-AMOUNT TO WS-IMMEDIATE-AVAILABLE
               MOVE ZERO TO WS-NEXT-DAY-AVAILABLE
               MOVE ZERO TO WS-AMOUNT-ON-HOLD
           ELSE
               MOVE ZERO TO WS-IMMEDIATE-AVAILABLE
               IF WS-DEPOSIT-AMOUNT <= WS-NEXT-DAY-AVAIL-AMOUNT
                   MOVE WS-DEPOSIT-AMOUNT TO WS-NEXT-DAY-AVAILABLE
                   MOVE ZERO TO WS-AMOUNT-ON-HOLD
               ELSE
                   MOVE WS-NEXT-DAY-AVAIL-AMOUNT TO
                       WS-NEXT-DAY-AVAILABLE
                   COMPUTE WS-AMOUNT-ON-HOLD =
                       WS-DEPOSIT-AMOUNT - WS-NEXT-DAY-AVAIL-AMOUNT
               END-IF
           END-IF.

       6000-DETERMINE-NOTICE-REQUIREMENT.
      *    A WRITTEN HOLD NOTICE IS REQUIRED WHENEVER ANY EXCEPTION
      *    HOLD (NEW ACCOUNT, LARGE DEPOSIT, OR REASONABLE CAUSE) IS
      *    APPLIED ON TOP OF THE STANDARD SCHEDULE
           MOVE 'N' TO WS-HOLD-NOTICE-REQUIRED
           IF NEW-ACCOUNT-EXCEPTION OR LARGE-DEPOSIT-EXCEPTION
              OR REASONABLE-CAUSE-EXCEPTION
               SET HOLD-NOTICE-REQUIRED-YES TO TRUE
           END-IF.

       9000-WRITE-HOLD-DECISION.
           DISPLAY 'ACCOUNT: ' WS-ACCOUNT-NUMBER
           DISPLAY 'IMMEDIATELY AVAILABLE: ' WS-IMMEDIATE-AVAILABLE
           DISPLAY 'NEXT-DAY AVAILABLE: ' WS-NEXT-DAY-AVAILABLE
           DISPLAY 'ON HOLD: ' WS-AMOUNT-ON-HOLD
           DISPLAY 'TOTAL HOLD DAYS: ' WS-STANDARD-HOLD-DAYS
           IF HOLD-NOTICE-REQUIRED-YES
               DISPLAY 'WRITTEN HOLD NOTICE REQUIRED'
           END-IF.
