       IDENTIFICATION DIVISION.
       PROGRAM-ID. REWARDCALC.
       AUTHOR. ACCENTURE-MAINFRAME-REINVENTION.
      *****************************************************************
      * MEMBERSHIP REWARDS ENGINE                                     *
      *                                                                *
      * COMPUTES POINTS EARNED ON A PURCHASE USING CATEGORY-SPECIFIC  *
      * BONUS RATES WITH ANNUAL SPEND CAPS, APPLIES CARDMEMBER TIER   *
      * BONUSES, EVALUATES TIER UPGRADE/DOWNGRADE AT ANNIVERSARY,     *
      * CHECKS ANNUAL-FEE WAIVER ELIGIBILITY, AND PROCESSES POINTS   *
      * REDEMPTION REQUESTS (CASH BACK, TRAVEL, GIFT CARD, OR         *
      * AIRLINE PARTNER TRANSFER).                                    *
      *****************************************************************
       DATA DIVISION.
       WORKING-STORAGE SECTION.

      *---------------------------------------------------------------*
      * CARDMEMBER PROFILE                                            *
      *---------------------------------------------------------------*
       01  WS-CARDMEMBER.
           05  WS-CARD-NUMBER             PIC X(16).
           05  WS-CARDMEMBER-TIER         PIC X(10).
               88  TIER-GREEN               VALUE 'GREEN'.
               88  TIER-GOLD                VALUE 'GOLD'.
               88  TIER-PLATINUM            VALUE 'PLATINUM'.
               88  TIER-CENTURION           VALUE 'CENTURION'.
           05  WS-ENROLLMENT-DATE          PIC X(8).
           05  WS-ANNIVERSARY-DATE         PIC X(8).
           05  WS-CURRENT-DATE             PIC X(8).
           05  WS-YTD-SPEND                PIC 9(9)V99 COMP-3.
           05  WS-POINTS-BALANCE           PIC 9(9)      COMP-3.
           05  WS-ANNUAL-FEE-WAIVED-FLAG   PIC X(1)      VALUE 'N'.
               88  ANNUAL-FEE-WAIVED         VALUE 'Y'.

      *---------------------------------------------------------------*
      * PER-CATEGORY YEAR-TO-DATE SPEND, USED TO ENFORCE BONUS CAPS   *
      *---------------------------------------------------------------*
       01  WS-CATEGORY-YTD-SPEND.
           05  WS-YTD-GROCERY-SPEND        PIC 9(7)V99 COMP-3.
           05  WS-YTD-STREAMING-SPEND      PIC 9(7)V99 COMP-3.

       01  WS-CATEGORY-CAPS.
           05  WS-GROCERY-CAP              PIC 9(5)V99 COMP-3 VALUE 6000.00.
           05  WS-STREAMING-CAP            PIC 9(5)V99 COMP-3 VALUE 3000.00.

      *---------------------------------------------------------------*
      * INCOMING PURCHASE                                             *
      *---------------------------------------------------------------*
       01  WS-PURCHASE.
           05  WS-SPEND-AMOUNT             PIC 9(7)V99 COMP-3.
           05  WS-MERCHANT-CATEGORY        PIC X(4).
               88  MCC-TRAVEL                 VALUE '3000' THRU '3999'.
               88  MCC-DINING                 VALUE '5800' THRU '5899'.
               88  MCC-GROCERY                 VALUE '5411'.
               88  MCC-GAS-STATION             VALUE '5541'.
               88  MCC-STREAMING               VALUE '5815'.
               88  MCC-OFFICE-SUPPLY           VALUE '5943'.
           05  WS-TXN-DATE                 PIC X(8).
           05  WS-IS-FOREIGN-TXN           PIC X(1).
               88  FOREIGN-TXN                VALUE 'Y'.

      *---------------------------------------------------------------*
      * POINTS CALCULATION WORK AREAS                                 *
      *---------------------------------------------------------------*
       01  WS-POINTS-CALC.
           05  WS-MULTIPLIER               PIC 9V99      COMP-3.
           05  WS-BASE-POINTS               PIC 9(7)      COMP-3.
           05  WS-CATEGORY-BONUS-POINTS     PIC 9(7)      COMP-3 VALUE ZERO.
           05  WS-TIER-BONUS-POINTS         PIC 9(5)      COMP-3 VALUE ZERO.
           05  WS-TOTAL-POINTS-EARNED       PIC 9(7)      COMP-3.

       01  WS-TIER-SPEND-THRESHOLDS.
           05  WS-GOLD-BONUS-THRESHOLD      PIC 9(9)V99 COMP-3 VALUE 15000.00.
           05  WS-PLATINUM-BONUS-THRESHOLD  PIC 9(9)V99 COMP-3 VALUE 25000.00.
           05  WS-CENTURION-BONUS-THRESHOLD PIC 9(9)V99 COMP-3 VALUE 50000.00.
           05  WS-GOLD-BONUS-POINTS          PIC 9(5)      COMP-3 VALUE 00250.
           05  WS-PLATINUM-BONUS-POINTS      PIC 9(5)      COMP-3 VALUE 00500.
           05  WS-CENTURION-BONUS-POINTS     PIC 9(5)      COMP-3 VALUE 01000.

      *---------------------------------------------------------------*
      * TIER EVALUATION (RUN AT CARDMEMBER ANNIVERSARY)               *
      *---------------------------------------------------------------*
       01  WS-TIER-EVALUATION.
           05  WS-GOLD-UPGRADE-SPEND         PIC 9(9)V99 COMP-3 VALUE 10000.00.
           05  WS-PLATINUM-UPGRADE-SPEND     PIC 9(9)V99 COMP-3 VALUE 30000.00.
           05  WS-CENTURION-UPGRADE-SPEND    PIC 9(9)V99 COMP-3 VALUE 75000.00.
           05  WS-DOWNGRADE-SPEND-FLOOR      PIC 9(9)V99 COMP-3 VALUE 05000.00.
           05  WS-TIER-CHANGE-FLAG           PIC X(10)     VALUE SPACES.

      *---------------------------------------------------------------*
      * ANNUAL FEE WAIVER                                             *
      *---------------------------------------------------------------*
       01  WS-ANNUAL-FEE.
           05  WS-ANNUAL-FEE-AMOUNT          PIC 9(3)V99 COMP-3 VALUE 695.00.
           05  WS-FEE-WAIVER-SPEND-THRESHOLD PIC 9(7)V99 COMP-3 VALUE 40000.00.

      *---------------------------------------------------------------*
      * REDEMPTION REQUEST                                            *
      *---------------------------------------------------------------*
       01  WS-REDEMPTION.
           05  WS-REDEMPTION-REQUESTED     PIC X(1)      VALUE 'N'.
               88  REDEMPTION-REQUESTED       VALUE 'Y'.
           05  WS-REDEMPTION-POINTS        PIC 9(7)      COMP-3.
           05  WS-REDEMPTION-TYPE          PIC X(10).
               88  REDEEM-CASHBACK             VALUE 'CASHBACK'.
               88  REDEEM-TRAVEL               VALUE 'TRAVEL'.
               88  REDEEM-GIFT-CARD            VALUE 'GIFTCARD'.
               88  REDEEM-AIRLINE-TRANSFER     VALUE 'AIRLINE'.
           05  WS-CONVERSION-RATIO         PIC 9V9999    COMP-3.
           05  WS-REDEMPTION-VALUE         PIC 9(7)V99 COMP-3.
           05  WS-REDEMPTION-REJECT-REASON PIC X(40)     VALUE SPACES.

       PROCEDURE DIVISION.

       0000-MAIN-PROCESS.
           PERFORM 1000-DETERMINE-CATEGORY-RATE
           PERFORM 2000-CALCULATE-BASE-POINTS
           PERFORM 3000-APPLY-TIER-BONUS
           PERFORM 3100-EVALUATE-TIER-CHANGE
           PERFORM 4000-CHECK-ANNUAL-FEE-WAIVER
           PERFORM 5000-UPDATE-POINTS-BALANCE
           IF REDEMPTION-REQUESTED
               PERFORM 6000-PROCESS-REDEMPTION-REQUEST
           END-IF
           PERFORM 7000-WRITE-REWARDS-LEDGER-ENTRY
           STOP RUN.

       1000-DETERMINE-CATEGORY-RATE.
           EVALUATE TRUE
               WHEN MCC-TRAVEL
                   MOVE 3.00 TO WS-MULTIPLIER
               WHEN MCC-DINING
                   MOVE 2.00 TO WS-MULTIPLIER
               WHEN MCC-GROCERY
                   PERFORM 1100-APPLY-GROCERY-CAP
               WHEN MCC-STREAMING
                   PERFORM 1200-APPLY-STREAMING-CAP
               WHEN MCC-GAS-STATION
                   MOVE 2.00 TO WS-MULTIPLIER
               WHEN MCC-OFFICE-SUPPLY
                   MOVE 2.00 TO WS-MULTIPLIER
               WHEN OTHER
                   MOVE 1.00 TO WS-MULTIPLIER
           END-EVALUATE.

       1100-APPLY-GROCERY-CAP.
      *    6% BACK ON GROCERY SPEND UP TO THE ANNUAL CAP, THEN THE
      *    RATE DROPS TO 1% (STANDARD) FOR SPEND BEYOND THE CAP
           IF (WS-YTD-GROCERY-SPEND + WS-SPEND-AMOUNT) <= WS-GROCERY-CAP
               MOVE 6.00 TO WS-MULTIPLIER
           ELSE
               IF WS-YTD-GROCERY-SPEND < WS-GROCERY-CAP
                   MOVE 6.00 TO WS-MULTIPLIER
               ELSE
                   MOVE 1.00 TO WS-MULTIPLIER
               END-IF
           END-IF
           ADD WS-SPEND-AMOUNT TO WS-YTD-GROCERY-SPEND.

       1200-APPLY-STREAMING-CAP.
      *    6% BACK ON STREAMING SUBSCRIPTIONS UP TO THE ANNUAL CAP
           IF (WS-YTD-STREAMING-SPEND + WS-SPEND-AMOUNT)
                   <= WS-STREAMING-CAP
               MOVE 6.00 TO WS-MULTIPLIER
           ELSE
               MOVE 1.00 TO WS-MULTIPLIER
           END-IF
           ADD WS-SPEND-AMOUNT TO WS-YTD-STREAMING-SPEND.

       2000-CALCULATE-BASE-POINTS.
      *    1 POINT PER DOLLAR SPENT, TIMES CATEGORY MULTIPLIER
           COMPUTE WS-BASE-POINTS =
               WS-SPEND-AMOUNT * WS-MULTIPLIER

           ADD WS-SPEND-AMOUNT TO WS-YTD-SPEND.

       3000-APPLY-TIER-BONUS.
           MOVE ZERO TO WS-TIER-BONUS-POINTS
           EVALUATE TRUE
               WHEN TIER-CENTURION
                   AND WS-YTD-SPEND >= WS-CENTURION-BONUS-THRESHOLD
                   MOVE WS-CENTURION-BONUS-POINTS TO WS-TIER-BONUS-POINTS
               WHEN TIER-PLATINUM
                   AND WS-YTD-SPEND >= WS-PLATINUM-BONUS-THRESHOLD
                   MOVE WS-PLATINUM-BONUS-POINTS TO WS-TIER-BONUS-POINTS
               WHEN TIER-GOLD
                   AND WS-YTD-SPEND >= WS-GOLD-BONUS-THRESHOLD
                   MOVE WS-GOLD-BONUS-POINTS TO WS-TIER-BONUS-POINTS
               WHEN OTHER
                   CONTINUE
           END-EVALUATE.

       3100-EVALUATE-TIER-CHANGE.
      *    RUN ONLY ON THE CARDMEMBER'S ANNIVERSARY DATE; COMPARES
      *    TRAILING YTD SPEND AGAINST UPGRADE/DOWNGRADE THRESHOLDS
           MOVE SPACES TO WS-TIER-CHANGE-FLAG
           IF WS-CURRENT-DATE = WS-ANNIVERSARY-DATE
               EVALUATE TRUE
                   WHEN WS-YTD-SPEND >= WS-CENTURION-UPGRADE-SPEND
                       AND NOT TIER-CENTURION
                       MOVE 'CENTURION' TO WS-CARDMEMBER-TIER
                       MOVE 'UPGRADE' TO WS-TIER-CHANGE-FLAG
                   WHEN WS-YTD-SPEND >= WS-PLATINUM-UPGRADE-SPEND
                       AND (TIER-GREEN OR TIER-GOLD)
                       MOVE 'PLATINUM' TO WS-CARDMEMBER-TIER
                       MOVE 'UPGRADE' TO WS-TIER-CHANGE-FLAG
                   WHEN WS-YTD-SPEND >= WS-GOLD-UPGRADE-SPEND
                       AND TIER-GREEN
                       MOVE 'GOLD' TO WS-CARDMEMBER-TIER
                       MOVE 'UPGRADE' TO WS-TIER-CHANGE-FLAG
                   WHEN WS-YTD-SPEND < WS-DOWNGRADE-SPEND-FLOOR
                       AND NOT TIER-GREEN
                       MOVE 'GREEN' TO WS-CARDMEMBER-TIER
                       MOVE 'DOWNGRADE' TO WS-TIER-CHANGE-FLAG
                   WHEN OTHER
                       CONTINUE
               END-EVALUATE
               MOVE ZERO TO WS-YTD-SPEND
               MOVE ZERO TO WS-YTD-GROCERY-SPEND
               MOVE ZERO TO WS-YTD-STREAMING-SPEND
           END-IF.

       4000-CHECK-ANNUAL-FEE-WAIVER.
      *    SPEND ABOVE THE WAIVER THRESHOLD IN THE MEMBERSHIP YEAR
      *    WAIVES THE FOLLOWING YEAR'S ANNUAL FEE
           IF WS-YTD-SPEND >= WS-FEE-WAIVER-SPEND-THRESHOLD
               MOVE 'Y' TO WS-ANNUAL-FEE-WAIVED-FLAG
           END-IF.

       5000-UPDATE-POINTS-BALANCE.
           COMPUTE WS-TOTAL-POINTS-EARNED =
               WS-BASE-POINTS + WS-TIER-BONUS-POINTS

           ADD WS-TOTAL-POINTS-EARNED TO WS-POINTS-BALANCE.

       6000-PROCESS-REDEMPTION-REQUEST.
           MOVE SPACES TO WS-REDEMPTION-REJECT-REASON

           IF WS-REDEMPTION-POINTS > WS-POINTS-BALANCE
               MOVE 'INSUFFICIENT POINTS BALANCE' TO
                   WS-REDEMPTION-REJECT-REASON
           ELSE
               EVALUATE TRUE
                   WHEN REDEEM-CASHBACK
      *                100 POINTS = $1.00 CASH BACK
                       MOVE 0.0100 TO WS-CONVERSION-RATIO
                   WHEN REDEEM-TRAVEL
      *                100 POINTS = $1.25 WHEN BOOKED THROUGH THE
      *                TRAVEL PORTAL (25% BONUS VALUE)
                       MOVE 0.0125 TO WS-CONVERSION-RATIO
                   WHEN REDEEM-GIFT-CARD
                       MOVE 0.0100 TO WS-CONVERSION-RATIO
                   WHEN REDEEM-AIRLINE-TRANSFER
      *                1:1 TRANSFER TO PARTNER AIRLINE MILES PROGRAMS
                       MOVE 0.0100 TO WS-CONVERSION-RATIO
                   WHEN OTHER
                       MOVE 'INVALID REDEMPTION TYPE' TO
                           WS-REDEMPTION-REJECT-REASON
               END-EVALUATE

               IF WS-REDEMPTION-REJECT-REASON = SPACES
                   COMPUTE WS-REDEMPTION-VALUE ROUNDED =
                       WS-REDEMPTION-POINTS * WS-CONVERSION-RATIO
                   SUBTRACT WS-REDEMPTION-POINTS FROM WS-POINTS-BALANCE
               END-IF
           END-IF.

       7000-WRITE-REWARDS-LEDGER-ENTRY.
           DISPLAY 'CARD: ' WS-CARD-NUMBER
           DISPLAY 'TIER: ' WS-CARDMEMBER-TIER
           DISPLAY 'POINTS EARNED THIS TXN: ' WS-TOTAL-POINTS-EARNED
           DISPLAY 'NEW POINTS BALANCE: ' WS-POINTS-BALANCE
           IF WS-TIER-CHANGE-FLAG NOT = SPACES
               DISPLAY 'TIER CHANGE: ' WS-TIER-CHANGE-FLAG
           END-IF
           IF ANNUAL-FEE-WAIVED
               DISPLAY 'ANNUAL FEE WAIVED FOR NEXT MEMBERSHIP YEAR'
           END-IF
           IF REDEMPTION-REQUESTED
               IF WS-REDEMPTION-REJECT-REASON = SPACES
                   DISPLAY 'REDEMPTION VALUE: ' WS-REDEMPTION-VALUE
               ELSE
                   DISPLAY 'REDEMPTION REJECTED: ' WS-REDEMPTION-REJECT-REASON
               END-IF
           END-IF.
