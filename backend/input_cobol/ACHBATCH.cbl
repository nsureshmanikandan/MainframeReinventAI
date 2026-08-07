       IDENTIFICATION DIVISION.
       PROGRAM-ID. ACHBATCH.
       AUTHOR. ACCENTURE-MAINFRAME-REINVENTION.
      *****************************************************************
      * ACH / WIRE TRANSFER BATCH VALIDATION ENGINE                   *
      *                                                                *
      * VALIDATES AN INCOMING ACH DEBIT/CREDIT TRANSACTION: CHECKS    *
      * THE ABA ROUTING NUMBER CHECKSUM, ENFORCES THE DAILY ACH LIMIT,*
      * DETECTS DUPLICATE SAME-DAY TRANSACTIONS, FLAGS LARGE-DOLLAR   *
      * TRANSFERS FOR BSA/CTR REVIEW, SCREENS INTERNATIONAL WIRES     *
      * AGAINST A SANCTIONED-COUNTRY LIST, AND ASSIGNS AN NACHA-STYLE *
      * RETURN CODE WHEN A TRANSACTION IS REJECTED.                   *
      *****************************************************************
       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. IBM-Z17.
       OBJECT-COMPUTER. IBM-Z17.

       DATA DIVISION.
       WORKING-STORAGE SECTION.

      *---------------------------------------------------------------*
      * ORIGINATING ACCOUNT PROFILE                                   *
      *---------------------------------------------------------------*
       01  WS-ORIGINATING-ACCOUNT.
           05  WS-ACCOUNT-NUMBER           PIC X(17).
           05  WS-ACCOUNT-STATUS           PIC X(1).
               88  ACCT-STATUS-ACTIVE        VALUE 'A'.
               88  ACCT-STATUS-CLOSED        VALUE 'C'.
               88  ACCT-STATUS-FROZEN        VALUE 'F'.
           05  WS-AVAILABLE-BALANCE        PIC 9(9)V99 COMP-3.
           05  WS-DAILY-ACH-LIMIT          PIC 9(7)V99 COMP-3.
           05  WS-DAILY-ACH-USED-TODAY     PIC 9(7)V99 COMP-3.
           05  WS-LAST-BATCH-AMOUNT        PIC 9(7)V99 COMP-3.
           05  WS-LAST-BATCH-ACCOUNT       PIC X(17).
           05  WS-LAST-BATCH-EFFECTIVE-DT  PIC X(8).

      *---------------------------------------------------------------*
      * INCOMING ACH TRANSACTION RECORD                                *
      *---------------------------------------------------------------*
       01  WS-ACH-TRANSACTION.
           05  WS-ROUTING-NUMBER           PIC 9(9).
           05  WS-RECEIVING-ACCOUNT        PIC X(17).
           05  WS-TXN-AMOUNT               PIC 9(7)V99 COMP-3.
           05  WS-TXN-TYPE-CODE            PIC X(2).
               88  TXN-DEBIT                 VALUE 'DR'.
               88  TXN-CREDIT                VALUE 'CR'.
               88  TXN-INTL-WIRE             VALUE 'IW'.
           05  WS-EFFECTIVE-DATE           PIC X(8).
           05  WS-DESTINATION-COUNTRY      PIC X(3).

      *---------------------------------------------------------------*
      * ROUTING NUMBER CHECKSUM WORK AREAS                             *
      *---------------------------------------------------------------*
       01  WS-ROUTING-CHECK.
           05  WS-ROUTING-DIGITS           PIC 9(9).
           05  WS-CHECKSUM-TOTAL           PIC 9(4)      COMP-3.
           05  WS-CHECKSUM-REMAINDER       PIC 9(2)      COMP-3.
           05  WS-D1  PIC 9.  05  WS-D2  PIC 9.  05  WS-D3  PIC 9.
           05  WS-D4  PIC 9.  05  WS-D5  PIC 9.  05  WS-D6  PIC 9.
           05  WS-D7  PIC 9.  05  WS-D8  PIC 9.  05  WS-D9  PIC 9.

      *---------------------------------------------------------------*
      * COMPLIANCE / BSA WORK AREAS                                    *
      *---------------------------------------------------------------*
       01  WS-COMPLIANCE.
           05  WS-CTR-REPORTING-THRESHOLD  PIC 9(6)V99 COMP-3
                   VALUE 10000.00.
           05  WS-CTR-FLAG                 PIC X(1)      VALUE 'N'.
               88  CTR-FILING-REQUIRED       VALUE 'Y'.
           05  WS-SANCTIONED-COUNTRY-1     PIC X(3)      VALUE 'IRN'.
           05  WS-SANCTIONED-COUNTRY-2     PIC X(3)      VALUE 'PRK'.
           05  WS-OFAC-HOLD-FLAG           PIC X(1)      VALUE 'N'.
               88  OFAC-HOLD-REQUIRED        VALUE 'Y'.

      *---------------------------------------------------------------*
      * VALIDATION RESULT / RETURN CODE                                *
      *---------------------------------------------------------------*
       01  WS-VALIDATION-RESULT.
           05  WS-RETURN-CODE              PIC X(3).
               88  RETURN-ACCEPTED           VALUE 'ACK'.
               88  RETURN-NSF                VALUE 'R01'.
               88  RETURN-ACCOUNT-CLOSED     VALUE 'R02'.
               88  RETURN-NO-ACCOUNT         VALUE 'R03'.
               88  RETURN-INVALID-ROUTING    VALUE 'R04'.
               88  RETURN-DUPLICATE          VALUE 'R05'.
               88  RETURN-LIMIT-EXCEEDED     VALUE 'R06'.
               88  RETURN-OFAC-HOLD          VALUE 'R07'.
           05  WS-RETURN-REASON            PIC X(40).

       PROCEDURE DIVISION.

       0000-MAIN-PROCESS.
           PERFORM 1000-VALIDATE-ACCOUNT-STATUS
           IF WS-RETURN-CODE = SPACES
               PERFORM 2000-VALIDATE-ROUTING-NUMBER
           END-IF
           IF WS-RETURN-CODE = SPACES
               PERFORM 3000-CHECK-DUPLICATE-TRANSACTION
           END-IF
           IF WS-RETURN-CODE = SPACES
               PERFORM 4000-VALIDATE-DAILY-LIMIT-AND-BALANCE
           END-IF
           IF WS-RETURN-CODE = SPACES
               PERFORM 5000-SCREEN-INTERNATIONAL-WIRE
           END-IF
           IF WS-RETURN-CODE = SPACES
               PERFORM 6000-CHECK-CTR-THRESHOLD
               SET RETURN-ACCEPTED TO TRUE
               MOVE 'TRANSACTION ACCEPTED' TO WS-RETURN-REASON
           END-IF
           PERFORM 9000-WRITE-VALIDATION-RESULT
           STOP RUN.

       1000-VALIDATE-ACCOUNT-STATUS.
           IF ACCT-STATUS-CLOSED
               SET RETURN-ACCOUNT-CLOSED TO TRUE
               MOVE 'ORIGINATING ACCOUNT CLOSED' TO WS-RETURN-REASON
           END-IF
           IF ACCT-STATUS-FROZEN
               SET RETURN-NO-ACCOUNT TO TRUE
               MOVE 'ORIGINATING ACCOUNT FROZEN' TO WS-RETURN-REASON
           END-IF.

       2000-VALIDATE-ROUTING-NUMBER.
      *    ABA ROUTING NUMBER CHECKSUM:
      *    3*(D1+D4+D7) + 7*(D2+D5+D8) + 1*(D3+D6+D9) MUST BE
      *    EVENLY DIVISIBLE BY 10
           MOVE WS-ROUTING-NUMBER TO WS-ROUTING-DIGITS
           MOVE WS-ROUTING-DIGITS (1:1) TO WS-D1
           MOVE WS-ROUTING-DIGITS (2:1) TO WS-D2
           MOVE WS-ROUTING-DIGITS (3:1) TO WS-D3
           MOVE WS-ROUTING-DIGITS (4:1) TO WS-D4
           MOVE WS-ROUTING-DIGITS (5:1) TO WS-D5
           MOVE WS-ROUTING-DIGITS (6:1) TO WS-D6
           MOVE WS-ROUTING-DIGITS (7:1) TO WS-D7
           MOVE WS-ROUTING-DIGITS (8:1) TO WS-D8
           MOVE WS-ROUTING-DIGITS (9:1) TO WS-D9

           COMPUTE WS-CHECKSUM-TOTAL =
               3 * (WS-D1 + WS-D4 + WS-D7) +
               7 * (WS-D2 + WS-D5 + WS-D8) +
               1 * (WS-D3 + WS-D6 + WS-D9)

           COMPUTE WS-CHECKSUM-REMAINDER =
               FUNCTION MOD (WS-CHECKSUM-TOTAL, 10)

           IF WS-CHECKSUM-REMAINDER NOT = ZERO
               SET RETURN-INVALID-ROUTING TO TRUE
               MOVE 'ROUTING NUMBER FAILS CHECKSUM VALIDATION' TO
                   WS-RETURN-REASON
           END-IF.

       3000-CHECK-DUPLICATE-TRANSACTION.
      *    RULE: SAME RECEIVING ACCOUNT, SAME AMOUNT, SAME EFFECTIVE
      *    DATE AS THE LAST PROCESSED BATCH ITEM IS TREATED AS A
      *    LIKELY DUPLICATE SUBMISSION AND REJECTED
           IF WS-RECEIVING-ACCOUNT = WS-LAST-BATCH-ACCOUNT
              AND WS-TXN-AMOUNT = WS-LAST-BATCH-AMOUNT
              AND WS-EFFECTIVE-DATE = WS-LAST-BATCH-EFFECTIVE-DT
               SET RETURN-DUPLICATE TO TRUE
               MOVE 'DUPLICATE OF PRIOR BATCH TRANSACTION' TO
                   WS-RETURN-REASON
           END-IF.

       4000-VALIDATE-DAILY-LIMIT-AND-BALANCE.
           IF TXN-DEBIT OR TXN-INTL-WIRE
               IF (WS-DAILY-ACH-USED-TODAY + WS-TXN-AMOUNT)
                       > WS-DAILY-ACH-LIMIT
                   SET RETURN-LIMIT-EXCEEDED TO TRUE
                   MOVE 'DAILY ACH DEBIT LIMIT EXCEEDED' TO
                       WS-RETURN-REASON
               ELSE
                   IF WS-TXN-AMOUNT > WS-AVAILABLE-BALANCE
                       SET RETURN-NSF TO TRUE
                       MOVE 'INSUFFICIENT AVAILABLE BALANCE' TO
                           WS-RETURN-REASON
                   END-IF
               END-IF
           END-IF.

       5000-SCREEN-INTERNATIONAL-WIRE.
           MOVE 'N' TO WS-OFAC-HOLD-FLAG
           IF TXN-INTL-WIRE
               IF WS-DESTINATION-COUNTRY = WS-SANCTIONED-COUNTRY-1
                  OR WS-DESTINATION-COUNTRY = WS-SANCTIONED-COUNTRY-2
                   SET OFAC-HOLD-REQUIRED TO TRUE
                   SET RETURN-OFAC-HOLD TO TRUE
                   MOVE 'DESTINATION COUNTRY ON OFAC SANCTIONS LIST'
                       TO WS-RETURN-REASON
               END-IF
           END-IF.

       6000-CHECK-CTR-THRESHOLD.
      *    CURRENCY TRANSACTION REPORT FILING IS TRIGGERED FOR ANY
      *    SINGLE TRANSACTION AT OR ABOVE THE BSA REPORTING THRESHOLD
           MOVE 'N' TO WS-CTR-FLAG
           IF WS-TXN-AMOUNT >= WS-CTR-REPORTING-THRESHOLD
               SET CTR-FILING-REQUIRED TO TRUE
           END-IF.

       9000-WRITE-VALIDATION-RESULT.
           DISPLAY 'ACCOUNT: ' WS-ACCOUNT-NUMBER
           DISPLAY 'RETURN CODE: ' WS-RETURN-CODE
           DISPLAY 'REASON: ' WS-RETURN-REASON
           IF CTR-FILING-REQUIRED
               DISPLAY 'CTR FILING REQUIRED FOR THIS TRANSACTION'
           END-IF.
