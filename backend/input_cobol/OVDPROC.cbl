       IDENTIFICATION DIVISION.
       PROGRAM-ID. OVDPROC.
       AUTHOR. ACCENTURE-MAINFRAME-REINVENTION.
      *****************************************************************
      * OVERDRAFT / NSF ITEM PROCESSING ENGINE                        *
      *                                                                *
      * DECIDES WHETHER TO PAY OR RETURN A TRANSACTION THAT WOULD     *
      * OVERDRAW AN ACCOUNT, APPLYING THE COURTESY OVERDRAFT LIMIT,   *
      * THE CUSTOMER'S DEBIT-CARD OVERDRAFT OPT-IN STATUS, A LINKED-  *
      * ACCOUNT OVERDRAFT SWEEP, AND A DAILY CAP ON THE NUMBER OF     *
      * OVERDRAFT FEES CHARGED PER DAY.                                *
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
           05  WS-LEDGER-BALANCE           PIC S9(9)V99 COMP-3.
           05  WS-COURTESY-OD-LIMIT        PIC 9(4)V99 COMP-3.
           05  WS-DEBIT-CARD-OD-OPT-IN     PIC X(1)      VALUE 'N'.
               88  DEBIT-CARD-OD-ENROLLED    VALUE 'Y'.
           05  WS-LINKED-SAVINGS-ACCOUNT   PIC X(17).
           05  WS-LINKED-ACCOUNT-BALANCE   PIC 9(9)V99 COMP-3.
           05  WS-OD-FEES-CHARGED-TODAY    PIC 9(2)      COMP-3.
           05  WS-CONSECUTIVE-OD-DAYS      PIC 9(3)      COMP-3.

      *---------------------------------------------------------------*
      * INCOMING TRANSACTION                                           *
      *---------------------------------------------------------------*
       01  WS-TRANSACTION.
           05  WS-TXN-AMOUNT               PIC 9(7)V99 COMP-3.
           05  WS-TXN-CHANNEL              PIC X(2).
               88  CHANNEL-DEBIT-CARD        VALUE 'DC'.
               88  CHANNEL-CHECK             VALUE 'CK'.
               88  CHANNEL-ACH               VALUE 'AC'.
               88  CHANNEL-ATM               VALUE 'AT'.

      *---------------------------------------------------------------*
      * FEE SCHEDULE                                                   *
      *---------------------------------------------------------------*
       01  WS-FEE-SCHEDULE.
           05  WS-OD-FEE-PER-ITEM          PIC 9(2)V99 COMP-3
                   VALUE 034.00.
           05  WS-RETURNED-ITEM-FEE        PIC 9(2)V99 COMP-3
                   VALUE 034.00.
           05  WS-MAX-OD-FEES-PER-DAY      PIC 9(1)      COMP-3
                   VALUE 3.
           05  WS-SUSTAINED-OD-FEE         PIC 9(2)V99 COMP-3
                   VALUE 015.00.
           05  WS-SUSTAINED-OD-TRIGGER-DAYS PIC 9(2)     COMP-3
                   VALUE 05.
           05  WS-SWEEP-TRANSFER-FEE       PIC 9(1)V99 COMP-3
                   VALUE 5.00.

      *---------------------------------------------------------------*
      * DECISION RESULT                                                *
      *---------------------------------------------------------------*
       01  WS-DECISION.
           05  WS-DECISION-CODE            PIC X(4).
               88  DECISION-PAID-COURTESY-OD  VALUE 'PDOD'.
               88  DECISION-PAID-SWEEP        VALUE 'PDSW'.
               88  DECISION-PAID-NORMAL       VALUE 'PDNM'.
               88  DECISION-RETURNED          VALUE 'RTND'.
           05  WS-OD-FEE-ASSESSED          PIC 9(3)V99 COMP-3
                   VALUE ZERO.
           05  WS-SWEEP-AMOUNT             PIC 9(7)V99 COMP-3
                   VALUE ZERO.
           05  WS-RESULTING-BALANCE        PIC S9(9)V99 COMP-3.
           05  WS-DECISION-REASON          PIC X(40).

       PROCEDURE DIVISION.

       0000-MAIN-PROCESS.
           IF WS-TXN-AMOUNT <= WS-LEDGER-BALANCE
               SET DECISION-PAID-NORMAL TO TRUE
               MOVE 'SUFFICIENT FUNDS - NO OVERDRAFT' TO
                   WS-DECISION-REASON
               COMPUTE WS-RESULTING-BALANCE =
                   WS-LEDGER-BALANCE - WS-TXN-AMOUNT
           ELSE
               PERFORM 1000-ATTEMPT-SWEEP-TRANSFER
               IF NOT DECISION-PAID-SWEEP
                   PERFORM 2000-ATTEMPT-COURTESY-OVERDRAFT
               END-IF
           END-IF

           IF DECISION-PAID-COURTESY-OD OR DECISION-RETURNED
               PERFORM 3000-ASSESS-OVERDRAFT-FEE
           END-IF

           PERFORM 9000-WRITE-DECISION
           STOP RUN.

       1000-ATTEMPT-SWEEP-TRANSFER.
      *    IF A LINKED SAVINGS ACCOUNT HAS ENOUGH FUNDS TO COVER THE
      *    SHORTFALL, SWEEP IT AUTOMATICALLY INSTEAD OF OVERDRAWING,
      *    CHARGING A FLAT SWEEP TRANSFER FEE INSTEAD OF AN OD FEE
           COMPUTE WS-SWEEP-AMOUNT =
               WS-TXN-AMOUNT - WS-LEDGER-BALANCE

           IF WS-LINKED-ACCOUNT-BALANCE >= WS-SWEEP-AMOUNT
               SET DECISION-PAID-SWEEP TO TRUE
               MOVE 'COVERED BY LINKED ACCOUNT SWEEP' TO
                   WS-DECISION-REASON
               COMPUTE WS-RESULTING-BALANCE =
                   WS-LEDGER-BALANCE + WS-SWEEP-AMOUNT - WS-TXN-AMOUNT
           END-IF.

       2000-ATTEMPT-COURTESY-OVERDRAFT.
      *    DEBIT-CARD TRANSACTIONS CAN ONLY OVERDRAW IF THE CUSTOMER
      *    HAS OPTED IN TO DEBIT-CARD OVERDRAFT COVERAGE; CHECKS AND
      *    ACH ITEMS CAN USE THE COURTESY LIMIT REGARDLESS OF OPT-IN
           IF CHANNEL-DEBIT-CARD AND NOT DEBIT-CARD-OD-ENROLLED
               SET DECISION-RETURNED TO TRUE
               MOVE 'DEBIT CARD NOT ENROLLED IN OD COVERAGE' TO
                   WS-DECISION-REASON
           ELSE
               COMPUTE WS-RESULTING-BALANCE =
                   WS-LEDGER-BALANCE - WS-TXN-AMOUNT

               IF WS-RESULTING-BALANCE >=
                       (0 - WS-COURTESY-OD-LIMIT)
                   SET DECISION-PAID-COURTESY-OD TO TRUE
                   MOVE 'PAID INTO COURTESY OVERDRAFT LIMIT' TO
                       WS-DECISION-REASON
               ELSE
                   SET DECISION-RETURNED TO TRUE
                   MOVE 'EXCEEDS COURTESY OVERDRAFT LIMIT' TO
                       WS-DECISION-REASON
               END-IF
           END-IF.

       3000-ASSESS-OVERDRAFT-FEE.
      *    ONE FEE PER ITEM (PAID OR RETURNED), CAPPED AT THE DAILY
      *    MAXIMUM NUMBER OF FEES; A SUSTAINED-OVERDRAFT FEE IS ADDED
      *    IF THE ACCOUNT HAS BEEN NEGATIVE FOR 5+ CONSECUTIVE DAYS
           IF WS-OD-FEES-CHARGED-TODAY < WS-MAX-OD-FEES-PER-DAY
               IF DECISION-PAID-COURTESY-OD
                   MOVE WS-OD-FEE-PER-ITEM TO WS-OD-FEE-ASSESSED
               ELSE
                   MOVE WS-RETURNED-ITEM-FEE TO WS-OD-FEE-ASSESSED
               END-IF
               ADD 1 TO WS-OD-FEES-CHARGED-TODAY
           END-IF

           IF WS-CONSECUTIVE-OD-DAYS >= WS-SUSTAINED-OD-TRIGGER-DAYS
               ADD WS-SUSTAINED-OD-FEE TO WS-OD-FEE-ASSESSED
           END-IF.

       9000-WRITE-DECISION.
           DISPLAY 'ACCOUNT: ' WS-ACCOUNT-NUMBER
           DISPLAY 'DECISION: ' WS-DECISION-CODE
           DISPLAY 'REASON: ' WS-DECISION-REASON
           DISPLAY 'FEE ASSESSED: ' WS-OD-FEE-ASSESSED
           DISPLAY 'RESULTING BALANCE: ' WS-RESULTING-BALANCE
           IF DECISION-PAID-SWEEP
               DISPLAY 'SWEEP AMOUNT: ' WS-SWEEP-AMOUNT
           END-IF.
