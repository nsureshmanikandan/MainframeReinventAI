       IDENTIFICATION DIVISION.
       PROGRAM-ID. CARDAUTH.
       AUTHOR. ACCENTURE-MAINFRAME-REINVENTION.
      *****************************************************************
      * REAL-TIME CREDIT CARD TRANSACTION AUTHORIZATION               *
      *                                                                *
      * RECEIVES AN INCOMING AUTHORIZATION REQUEST FROM THE MERCHANT  *
      * NETWORK, VALIDATES CARD STATUS, CVV/PIN, AVAILABLE CREDIT,    *
      * TRANSACTION VELOCITY, AND A WEIGHTED FRAUD SCORE, THEN        *
      * RETURNS AN APPROVE / DECLINE / REFER-TO-FRAUD RESPONSE.       *
      * MIRRORS A REAL-TIME OLTP AUTHORIZATION PROGRAM RUNNING UNDER  *
      * CICS AGAINST DB2 CUSTOMER AND ACCOUNT TABLES.                 *
      *****************************************************************
       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. IBM-Z17.
       OBJECT-COMPUTER. IBM-Z17.

       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT TRANS-IN-FILE   ASSIGN TO TRANSIN
               ORGANIZATION IS SEQUENTIAL.
           SELECT RESP-OUT-FILE   ASSIGN TO RESPOUT
               ORGANIZATION IS SEQUENTIAL.
           SELECT FRAUD-LOG-FILE  ASSIGN TO FRAUDLOG
               ORGANIZATION IS SEQUENTIAL.

       DATA DIVISION.
       FILE SECTION.
       FD  TRANS-IN-FILE.
       01  TRANS-IN-RECORD             PIC X(120).

       FD  RESP-OUT-FILE.
       01  RESP-OUT-RECORD             PIC X(80).

       FD  FRAUD-LOG-FILE.
       01  FRAUD-LOG-RECORD            PIC X(100).

       WORKING-STORAGE SECTION.

      *---------------------------------------------------------------*
      * CARDMEMBER ACCOUNT PROFILE (NORMALLY A DB2 ROW FETCHED VIA    *
      * EXEC SQL SELECT ... FROM ACCT.CARD_ACCOUNT WHERE ...)         *
      *---------------------------------------------------------------*
       01  WS-CARD-ACCOUNT.
           05  WS-CARD-NUMBER            PIC X(16).
           05  WS-CARD-EXPIRY-DATE       PIC X(6).
           05  WS-CVV-ON-FILE            PIC X(3).
           05  WS-PIN-RETRY-COUNT        PIC 9.
           05  WS-CARDMEMBER-TIER        PIC X(10).
               88  TIER-GREEN              VALUE 'GREEN'.
               88  TIER-GOLD               VALUE 'GOLD'.
               88  TIER-PLATINUM           VALUE 'PLATINUM'.
               88  TIER-CENTURION          VALUE 'CENTURION'.
           05  WS-ACCOUNT-STATUS         PIC X(1).
               88  STATUS-ACTIVE           VALUE 'A'.
               88  STATUS-SUSPENDED        VALUE 'S'.
               88  STATUS-CLOSED           VALUE 'C'.
               88  STATUS-LOST-STOLEN      VALUE 'L'.
           05  WS-CREDIT-LIMIT           PIC 9(9)V99 COMP-3.
           05  WS-CURRENT-BALANCE        PIC 9(9)V99 COMP-3.
           05  WS-AVAILABLE-CREDIT       PIC 9(9)V99 COMP-3.
           05  WS-CASH-ADVANCE-LIMIT     PIC 9(7)V99 COMP-3.
           05  WS-CASH-ADVANCE-BALANCE   PIC 9(7)V99 COMP-3.
           05  WS-AVG-TXN-AMOUNT         PIC 9(7)V99 COMP-3.
           05  WS-DAILY-SPEND-LIMIT      PIC 9(7)V99 COMP-3.
           05  WS-TXN-COUNT-ROLLING-1HR  PIC 9(3)      COMP-3.
           05  WS-TXN-AMT-ROLLING-24HR   PIC 9(9)V99 COMP-3.

      *---------------------------------------------------------------*
      * INCOMING AUTHORIZATION REQUEST                                *
      *---------------------------------------------------------------*
       01  WS-INCOMING-TRANSACTION.
           05  WS-TXN-AMOUNT             PIC 9(7)V99 COMP-3.
           05  WS-TXN-TYPE               PIC X(2).
               88  TXN-PURCHASE            VALUE 'PU'.
               88  TXN-CASH-ADVANCE        VALUE 'CA'.
               88  TXN-BALANCE-TRANSFER    VALUE 'BT'.
               88  TXN-REFUND               VALUE 'RF'.
           05  WS-MERCHANT-CODE          PIC X(4).
           05  WS-MERCHANT-CATEGORY-CODE PIC X(4).
           05  WS-MERCHANT-COUNTRY       PIC X(3).
           05  WS-CVV-ENTERED            PIC X(3).
           05  WS-PIN-ENTERED            PIC X(4).
           05  WS-IS-CARD-PRESENT        PIC X(1).
               88  CARD-PRESENT             VALUE 'Y'.
               88  CARD-NOT-PRESENT         VALUE 'N'.
           05  WS-TXN-TIMESTAMP          PIC X(14).

      *---------------------------------------------------------------*
      * FEE CALCULATION WORK AREAS                                    *
      *---------------------------------------------------------------*
       01  WS-FEE-CALC.
           05  WS-INTL-TXN-FEE-PCT       PIC 9V999   COMP-3 VALUE 0.030.
           05  WS-CASH-ADV-FEE-PCT       PIC 9V999   COMP-3 VALUE 0.050.
           05  WS-CASH-ADV-FEE-FLOOR     PIC 9(3)V99 COMP-3 VALUE 010.00.
           05  WS-CALCULATED-FEE         PIC 9(5)V99 COMP-3 VALUE ZERO.

      *---------------------------------------------------------------*
      * FRAUD SCORING WORK AREAS                                      *
      *---------------------------------------------------------------*
       01  WS-FRAUD-SCORE                PIC 9(3)      VALUE ZERO.
       01  WS-FRAUD-THRESHOLD            PIC 9(3)      VALUE 070.
       01  WS-FRAUD-REASON-CODES         PIC X(40)     VALUE SPACES.
       01  WS-BLACKLISTED-MCC            PIC X(4)      VALUE '7995'.
       01  WS-BLACKLISTED-COUNTRY        PIC X(3)      VALUE 'NGA'.

      *---------------------------------------------------------------*
      * AUTHORIZATION RESPONSE                                        *
      *---------------------------------------------------------------*
       01  WS-AUTH-RESPONSE.
           05  WS-RESPONSE-CODE          PIC X(2).
               88  RESP-APPROVED           VALUE '00'.
               88  RESP-DECLINED-CREDIT    VALUE '05'.
               88  RESP-EXPIRED-CARD       VALUE '54'.
               88  RESP-INVALID-CVV        VALUE '82'.
               88  RESP-PIN-RETRIES-EXCD   VALUE '75'.
               88  RESP-CARD-SUSPENDED     VALUE '62'.
               88  RESP-CARD-LOST-STOLEN   VALUE '41'.
               88  RESP-VELOCITY-EXCEEDED  VALUE '61'.
               88  RESP-REFER-TO-FRAUD     VALUE '59'.
           05  WS-RESPONSE-REASON        PIC X(40).
           05  WS-AUTHORIZATION-CODE     PIC X(6).

       PROCEDURE DIVISION.

       0000-MAIN-PROCESS.
           PERFORM 1000-VALIDATE-CARD-STATUS
           IF WS-RESPONSE-CODE = SPACES
               PERFORM 1100-VALIDATE-CVV-AND-PIN
           END-IF
           IF WS-RESPONSE-CODE = SPACES
               PERFORM 2000-VALIDATE-CREDIT-LIMIT
           END-IF
           IF WS-RESPONSE-CODE = SPACES
               PERFORM 2100-CALCULATE-TRANSACTION-FEES
               PERFORM 3000-CHECK-VELOCITY-LIMITS
           END-IF
           IF WS-RESPONSE-CODE = SPACES
               PERFORM 4000-CALCULATE-FRAUD-SCORE
               PERFORM 5000-DETERMINE-AUTH-RESPONSE
           END-IF
           PERFORM 7000-WRITE-AUTH-RESPONSE
           IF RESP-REFER-TO-FRAUD
               PERFORM 8000-WRITE-FRAUD-LOG
           END-IF
           STOP RUN.

       1000-VALIDATE-CARD-STATUS.
           IF STATUS-CLOSED
               SET RESP-DECLINED-CREDIT TO TRUE
               MOVE 'ACCOUNT CLOSED' TO WS-RESPONSE-REASON
           END-IF
           IF STATUS-SUSPENDED
               SET RESP-CARD-SUSPENDED TO TRUE
               MOVE 'ACCOUNT SUSPENDED' TO WS-RESPONSE-REASON
           END-IF
           IF STATUS-LOST-STOLEN
               SET RESP-CARD-LOST-STOLEN TO TRUE
               MOVE 'CARD REPORTED LOST OR STOLEN' TO WS-RESPONSE-REASON
           END-IF
           IF WS-CARD-EXPIRY-DATE < WS-TXN-TIMESTAMP (1:6)
               SET RESP-EXPIRED-CARD TO TRUE
               MOVE 'CARD EXPIRED' TO WS-RESPONSE-REASON
           END-IF.

       1100-VALIDATE-CVV-AND-PIN.
           IF WS-CVV-ENTERED NOT = WS-CVV-ON-FILE
               SET RESP-INVALID-CVV TO TRUE
               MOVE 'CVV MISMATCH' TO WS-RESPONSE-REASON
           END-IF
           IF TXN-CASH-ADVANCE
               IF WS-PIN-RETRY-COUNT >= 3
                   SET RESP-PIN-RETRIES-EXCD TO TRUE
                   MOVE 'PIN RETRY LIMIT EXCEEDED' TO WS-RESPONSE-REASON
               END-IF
           END-IF.

       2000-VALIDATE-CREDIT-LIMIT.
           COMPUTE WS-AVAILABLE-CREDIT =
               WS-CREDIT-LIMIT - WS-CURRENT-BALANCE

           IF TXN-CASH-ADVANCE
               IF (WS-CASH-ADVANCE-BALANCE + WS-TXN-AMOUNT)
                       > WS-CASH-ADVANCE-LIMIT
                   SET RESP-DECLINED-CREDIT TO TRUE
                   MOVE 'CASH ADVANCE LIMIT EXCEEDED' TO WS-RESPONSE-REASON
               END-IF
           ELSE
               IF (WS-CURRENT-BALANCE + WS-TXN-AMOUNT) > WS-CREDIT-LIMIT
                   SET RESP-DECLINED-CREDIT TO TRUE
                   MOVE 'INSUFFICIENT AVAILABLE CREDIT' TO
                       WS-RESPONSE-REASON
               END-IF
           END-IF.

       2100-CALCULATE-TRANSACTION-FEES.
           MOVE ZERO TO WS-CALCULATED-FEE

           IF WS-MERCHANT-COUNTRY NOT = 'USA'
               COMPUTE WS-CALCULATED-FEE ROUNDED =
                   WS-TXN-AMOUNT * WS-INTL-TXN-FEE-PCT
           END-IF

           IF TXN-CASH-ADVANCE
               COMPUTE WS-CALCULATED-FEE ROUNDED =
                   WS-CALCULATED-FEE +
                   FUNCTION MAX(
                       (WS-TXN-AMOUNT * WS-CASH-ADV-FEE-PCT),
                       WS-CASH-ADV-FEE-FLOOR)
           END-IF.

       3000-CHECK-VELOCITY-LIMITS.
      *    RULE: MORE THAN 5 TRANSACTIONS IN A ROLLING 1-HOUR WINDOW
      *    IS TREATED AS A VELOCITY BREACH REQUIRING DECLINE
           IF WS-TXN-COUNT-ROLLING-1HR > 5
               SET RESP-VELOCITY-EXCEEDED TO TRUE
               MOVE 'TRANSACTION VELOCITY LIMIT EXCEEDED' TO
                   WS-RESPONSE-REASON
           END-IF

      *    RULE: ROLLING 24-HOUR SPEND CANNOT EXCEED THE ACCOUNT'S
      *    CONFIGURED DAILY SPEND LIMIT (INDEPENDENT OF CREDIT LIMIT)
           IF (WS-TXN-AMT-ROLLING-24HR + WS-TXN-AMOUNT)
                   > WS-DAILY-SPEND-LIMIT
               SET RESP-VELOCITY-EXCEEDED TO TRUE
               MOVE 'DAILY SPEND LIMIT EXCEEDED' TO WS-RESPONSE-REASON
           END-IF.

       4000-CALCULATE-FRAUD-SCORE.
           MOVE ZERO TO WS-FRAUD-SCORE
           MOVE SPACES TO WS-FRAUD-REASON-CODES

      *    RULE 1: TRANSACTION MORE THAN 3X THE CARDMEMBER'S
      *    AVERAGE TRANSACTION AMOUNT ADDS 40 POINTS
           IF WS-TXN-AMOUNT > (WS-AVG-TXN-AMOUNT * 3)
               ADD 40 TO WS-FRAUD-SCORE
               STRING WS-FRAUD-REASON-CODES DELIMITED BY SPACE
                   'HIGH-AMOUNT ' DELIMITED BY SIZE
                   INTO WS-FRAUD-REASON-CODES
           END-IF

      *    RULE 2: FOREIGN MERCHANT COUNTRY ADDS 25 POINTS
           IF WS-MERCHANT-COUNTRY NOT = 'USA'
               ADD 25 TO WS-FRAUD-SCORE
           END-IF

      *    RULE 3: TRANSACTION OVER $2,000 ADDS 20 POINTS
           IF WS-TXN-AMOUNT > 2000.00
               ADD 20 TO WS-FRAUD-SCORE
           END-IF

      *    RULE 4: CARD-NOT-PRESENT COMBINED WITH A HIGH-VALUE
      *    TRANSACTION (OVER $500) ADDS 15 POINTS
           IF CARD-NOT-PRESENT AND WS-TXN-AMOUNT > 500.00
               ADD 15 TO WS-FRAUD-SCORE
           END-IF

      *    RULE 5: KNOWN HIGH-RISK MERCHANT CATEGORY / COUNTRY
      *    COMBINATION ADDS 50 POINTS (E.G. GAMBLING MCC FROM A
      *    SANCTIONED-RISK COUNTRY)
           IF WS-MERCHANT-CATEGORY-CODE = WS-BLACKLISTED-MCC
              AND WS-MERCHANT-COUNTRY = WS-BLACKLISTED-COUNTRY
               ADD 50 TO WS-FRAUD-SCORE
           END-IF.

       5000-DETERMINE-AUTH-RESPONSE.
           IF WS-FRAUD-SCORE >= WS-FRAUD-THRESHOLD
               SET RESP-REFER-TO-FRAUD TO TRUE
               MOVE 'FRAUD SCORE EXCEEDS THRESHOLD' TO WS-RESPONSE-REASON
           ELSE
               SET RESP-APPROVED TO TRUE
               MOVE 'TRANSACTION APPROVED' TO WS-RESPONSE-REASON
               PERFORM 6000-GENERATE-AUTHORIZATION-CODE
           END-IF.

       6000-GENERATE-AUTHORIZATION-CODE.
      *    SIMPLE DETERMINISTIC CODE DERIVED FROM LAST 4 OF CARD
      *    NUMBER AND THE TRANSACTION TIMESTAMP SECONDS
           MOVE WS-CARD-NUMBER (13:4) TO WS-AUTHORIZATION-CODE (1:4)
           MOVE WS-TXN-TIMESTAMP (13:2) TO WS-AUTHORIZATION-CODE (5:2).

       7000-WRITE-AUTH-RESPONSE.
           DISPLAY 'CARD: ' WS-CARD-NUMBER
           DISPLAY 'RESPONSE CODE: ' WS-RESPONSE-CODE
           DISPLAY 'REASON: ' WS-RESPONSE-REASON
           DISPLAY 'AUTH CODE: ' WS-AUTHORIZATION-CODE
           DISPLAY 'FEE ASSESSED: ' WS-CALCULATED-FEE.

       8000-WRITE-FRAUD-LOG.
           DISPLAY 'FRAUD REVIEW QUEUED FOR CARD: ' WS-CARD-NUMBER
           DISPLAY 'SCORE: ' WS-FRAUD-SCORE
           DISPLAY 'REASON CODES: ' WS-FRAUD-REASON-CODES.
