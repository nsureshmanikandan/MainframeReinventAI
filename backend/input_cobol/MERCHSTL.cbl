       IDENTIFICATION DIVISION.
       PROGRAM-ID. MERCHSTL.
       AUTHOR. ACCENTURE-MAINFRAME-REINVENTION.
      *****************************************************************
      * MERCHANT SETTLEMENT / INTERCHANGE FEE ENGINE                  *
      *                                                                *
      * COMPUTES THE INTERCHANGE FEE OWED BY AN ACQUIRING MERCHANT ON *
      * A CARD TRANSACTION, BASED ON CARD TYPE (CONSUMER, REWARDS,    *
      * CORPORATE) AND ENTRY MODE (CARD-PRESENT VS CARD-NOT-PRESENT), *
      * ADDS THE ACQUIRER ASSESSMENT FEE, WITHHOLDS A CHARGEBACK      *
      * RESERVE FOR HIGH-RISK MERCHANT CATEGORIES, AND CALCULATES THE *
      * NET AMOUNT DUE TO THE MERCHANT AT NEXT-DAY SETTLEMENT.        *
      *****************************************************************
       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. IBM-Z17.
       OBJECT-COMPUTER. IBM-Z17.

       DATA DIVISION.
       WORKING-STORAGE SECTION.

      *---------------------------------------------------------------*
      * MERCHANT PROFILE                                               *
      *---------------------------------------------------------------*
       01  WS-MERCHANT.
           05  WS-MERCHANT-ID              PIC X(12).
           05  WS-MERCHANT-CATEGORY-CODE   PIC X(4).
               88  MCC-HIGH-RISK-TRAVEL      VALUE '4511' '4722'.
               88  MCC-HIGH-RISK-SUBSCRIPTION VALUE '5968'.
           05  WS-ROLLING-CHARGEBACK-RATE  PIC 9V9999    COMP-3.
           05  WS-MERCHANT-RESERVE-BALANCE PIC 9(7)V99 COMP-3.

      *---------------------------------------------------------------*
      * TRANSACTION BATCH ITEM                                         *
      *---------------------------------------------------------------*
       01  WS-TRANSACTION.
           05  WS-TXN-AMOUNT               PIC 9(7)V99 COMP-3.
           05  WS-CARD-TYPE                PIC X(2).
               88  CARD-TYPE-CONSUMER        VALUE 'CS'.
               88  CARD-TYPE-REWARDS         VALUE 'RW'.
               88  CARD-TYPE-CORPORATE       VALUE 'CP'.
           05  WS-ENTRY-MODE                PIC X(2).
               88  ENTRY-CARD-PRESENT         VALUE 'CP'.
               88  ENTRY-CARD-NOT-PRESENT     VALUE 'CN'.

      *---------------------------------------------------------------*
      * INTERCHANGE RATE TABLE                                         *
      *---------------------------------------------------------------*
       01  WS-INTERCHANGE-RATES.
           05  WS-CONSUMER-CP-PCT           PIC 9V9999    COMP-3
                   VALUE 0.0150.
           05  WS-CONSUMER-CNP-PCT          PIC 9V9999    COMP-3
                   VALUE 0.0195.
           05  WS-REWARDS-CP-PCT            PIC 9V9999    COMP-3
                   VALUE 0.0210.
           05  WS-REWARDS-CNP-PCT           PIC 9V9999    COMP-3
                   VALUE 0.0255.
           05  WS-CORPORATE-CP-PCT          PIC 9V9999    COMP-3
                   VALUE 0.0265.
           05  WS-CORPORATE-CNP-PCT         PIC 9V9999    COMP-3
                   VALUE 0.0310.
           05  WS-PER-ITEM-FEE              PIC 9V99      COMP-3
                   VALUE 0.10.
           05  WS-ACQUIRER-ASSESSMENT-PCT   PIC 9V9999    COMP-3
                   VALUE 0.0013.

      *---------------------------------------------------------------*
      * CHARGEBACK RESERVE RULES                                       *
      *---------------------------------------------------------------*
       01  WS-RESERVE-RULES.
           05  WS-HIGH-CHARGEBACK-THRESHOLD PIC 9V9999   COMP-3
                   VALUE 0.0100.
           05  WS-RESERVE-WITHHOLD-PCT      PIC 9V999    COMP-3
                   VALUE 0.100.

      *---------------------------------------------------------------*
      * SETTLEMENT CALCULATION RESULT                                  *
      *---------------------------------------------------------------*
       01  WS-SETTLEMENT-RESULT.
           05  WS-INTERCHANGE-RATE-USED     PIC 9V9999    COMP-3.
           05  WS-INTERCHANGE-FEE           PIC 9(6)V99 COMP-3.
           05  WS-ACQUIRER-ASSESSMENT-FEE   PIC 9(6)V99 COMP-3.
           05  WS-TOTAL-FEES                PIC 9(6)V99 COMP-3.
           05  WS-RESERVE-WITHHELD          PIC 9(6)V99 COMP-3
                   VALUE ZERO.
           05  WS-NET-SETTLEMENT-AMOUNT     PIC 9(7)V99 COMP-3.
           05  WS-IS-HIGH-RISK-MCC          PIC X(1)      VALUE 'N'.
               88  HIGH-RISK-MCC-YES           VALUE 'Y'.

       PROCEDURE DIVISION.

       0000-MAIN-PROCESS.
           PERFORM 1000-DETERMINE-INTERCHANGE-RATE
           PERFORM 2000-CALCULATE-INTERCHANGE-FEE
           PERFORM 3000-CALCULATE-ACQUIRER-ASSESSMENT
           PERFORM 4000-CHECK-CHARGEBACK-RESERVE
           PERFORM 5000-CALCULATE-NET-SETTLEMENT
           PERFORM 9000-WRITE-SETTLEMENT-RECORD
           STOP RUN.

       1000-DETERMINE-INTERCHANGE-RATE.
      *    RATE DEPENDS ON BOTH CARD TYPE AND ENTRY MODE; CARD-NOT-
      *    PRESENT TRANSACTIONS ALWAYS CARRY A HIGHER RATE THAN
      *    CARD-PRESENT FOR THE SAME CARD TYPE DUE TO FRAUD RISK
           EVALUATE TRUE
               WHEN CARD-TYPE-CONSUMER AND ENTRY-CARD-PRESENT
                   MOVE WS-CONSUMER-CP-PCT TO WS-INTERCHANGE-RATE-USED
               WHEN CARD-TYPE-CONSUMER AND ENTRY-CARD-NOT-PRESENT
                   MOVE WS-CONSUMER-CNP-PCT TO WS-INTERCHANGE-RATE-USED
               WHEN CARD-TYPE-REWARDS AND ENTRY-CARD-PRESENT
                   MOVE WS-REWARDS-CP-PCT TO WS-INTERCHANGE-RATE-USED
               WHEN CARD-TYPE-REWARDS AND ENTRY-CARD-NOT-PRESENT
                   MOVE WS-REWARDS-CNP-PCT TO WS-INTERCHANGE-RATE-USED
               WHEN CARD-TYPE-CORPORATE AND ENTRY-CARD-PRESENT
                   MOVE WS-CORPORATE-CP-PCT TO WS-INTERCHANGE-RATE-USED
               WHEN CARD-TYPE-CORPORATE AND ENTRY-CARD-NOT-PRESENT
                   MOVE WS-CORPORATE-CNP-PCT TO WS-INTERCHANGE-RATE-USED
           END-EVALUATE.

       2000-CALCULATE-INTERCHANGE-FEE.
      *    PERCENTAGE COMPONENT PLUS A FLAT PER-ITEM FEE
           COMPUTE WS-INTERCHANGE-FEE ROUNDED =
               (WS-TXN-AMOUNT * WS-INTERCHANGE-RATE-USED) +
               WS-PER-ITEM-FEE.

       3000-CALCULATE-ACQUIRER-ASSESSMENT.
           COMPUTE WS-ACQUIRER-ASSESSMENT-FEE ROUNDED =
               WS-TXN-AMOUNT * WS-ACQUIRER-ASSESSMENT-PCT

           COMPUTE WS-TOTAL-FEES =
               WS-INTERCHANGE-FEE + WS-ACQUIRER-ASSESSMENT-FEE.

       4000-CHECK-CHARGEBACK-RESERVE.
      *    HIGH-RISK MERCHANT CATEGORIES, OR ANY MERCHANT WHOSE
      *    ROLLING CHARGEBACK RATE EXCEEDS 1%, HAVE 10% OF THE NET
      *    SETTLEMENT AMOUNT WITHHELD INTO A RESERVE
           MOVE 'N' TO WS-IS-HIGH-RISK-MCC
           IF MCC-HIGH-RISK-TRAVEL OR MCC-HIGH-RISK-SUBSCRIPTION
               SET HIGH-RISK-MCC-YES TO TRUE
           END-IF

           IF HIGH-RISK-MCC-YES
              OR WS-ROLLING-CHARGEBACK-RATE > WS-HIGH-CHARGEBACK-THRESHOLD
               COMPUTE WS-RESERVE-WITHHELD ROUNDED =
                   (WS-TXN-AMOUNT - WS-TOTAL-FEES) *
                   WS-RESERVE-WITHHOLD-PCT
           END-IF.

       5000-CALCULATE-NET-SETTLEMENT.
           COMPUTE WS-NET-SETTLEMENT-AMOUNT =
               WS-TXN-AMOUNT - WS-TOTAL-FEES - WS-RESERVE-WITHHELD.

       9000-WRITE-SETTLEMENT-RECORD.
           DISPLAY 'MERCHANT: ' WS-MERCHANT-ID
           DISPLAY 'INTERCHANGE FEE: ' WS-INTERCHANGE-FEE
           DISPLAY 'ACQUIRER ASSESSMENT: ' WS-ACQUIRER-ASSESSMENT-FEE
           DISPLAY 'RESERVE WITHHELD: ' WS-RESERVE-WITHHELD
           DISPLAY 'NET SETTLEMENT AMOUNT: ' WS-NET-SETTLEMENT-AMOUNT.
