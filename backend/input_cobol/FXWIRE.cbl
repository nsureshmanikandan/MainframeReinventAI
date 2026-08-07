       IDENTIFICATION DIVISION.
       PROGRAM-ID. FXWIRE.
       AUTHOR. ACCENTURE-MAINFRAME-REINVENTION.
      *****************************************************************
      * INTERNATIONAL WIRE / FOREIGN EXCHANGE CONVERSION ENGINE       *
      *                                                                *
      * CONVERTS A USD WIRE AMOUNT INTO THE DESTINATION CURRENCY,     *
      * APPLYING A MARGIN OVER THE MID-MARKET RATE, A TIERED WIRE     *
      * SERVICE FEE BASED ON AMOUNT, A CORRESPONDENT BANK FEE FOR     *
      * NON-DIRECT CURRENCY PAIRS, AND A SAME-DAY PROCESSING          *
      * SURCHARGE WHEN THE WIRE IS SUBMITTED AFTER THE DAILY CUTOFF.  *
      *****************************************************************
       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. IBM-Z17.
       OBJECT-COMPUTER. IBM-Z17.

       DATA DIVISION.
       WORKING-STORAGE SECTION.

      *---------------------------------------------------------------*
      * WIRE REQUEST                                                   *
      *---------------------------------------------------------------*
       01  WS-WIRE-REQUEST.
           05  WS-SENDER-ACCOUNT           PIC X(17).
           05  WS-USD-SEND-AMOUNT          PIC 9(8)V99 COMP-3.
           05  WS-DESTINATION-CURRENCY     PIC X(3).
               88  CURR-DIRECT-EUR           VALUE 'EUR'.
               88  CURR-DIRECT-GBP           VALUE 'GBP'.
               88  CURR-DIRECT-JPY           VALUE 'JPY'.
           05  WS-MID-MARKET-RATE          PIC 9(4)V999999 COMP-3.
           05  WS-REQUEST-TIME             PIC 9(4).
           05  WS-SAME-DAY-REQUESTED       PIC X(1)      VALUE 'N'.
               88  SAME-DAY-REQUESTED-YES    VALUE 'Y'.

      *---------------------------------------------------------------*
      * FX MARGIN / FEE SCHEDULE                                       *
      *---------------------------------------------------------------*
       01  WS-FEE-SCHEDULE.
           05  WS-FX-MARGIN-PCT            PIC 9V9999    COMP-3
                   VALUE 0.0250.
           05  WS-WIRE-CUTOFF-TIME         PIC 9(4)      VALUE 1400.
           05  WS-SAME-DAY-SURCHARGE       PIC 9(3)V99 COMP-3
                   VALUE 040.00.
           05  WS-CORRESPONDENT-BANK-FEE   PIC 9(3)V99 COMP-3
                   VALUE 018.00.
           05  WS-TIER1-CEILING            PIC 9(5)V99 COMP-3
                   VALUE 01000.00.
           05  WS-TIER1-FEE                PIC 9(3)V99 COMP-3
                   VALUE 025.00.
           05  WS-TIER2-CEILING            PIC 9(6)V99 COMP-3
                   VALUE 10000.00.
           05  WS-TIER2-FEE                PIC 9(3)V99 COMP-3
                   VALUE 045.00.
           05  WS-TIER3-FEE                PIC 9(3)V99 COMP-3
                   VALUE 065.00.

      *---------------------------------------------------------------*
      * CONVERSION / FEE CALCULATION RESULT                            *
      *---------------------------------------------------------------*
       01  WS-CONVERSION-RESULT.
           05  WS-CUSTOMER-RATE            PIC 9(4)V999999 COMP-3.
           05  WS-DESTINATION-AMOUNT       PIC 9(9)V99 COMP-3.
           05  WS-WIRE-SERVICE-FEE         PIC 9(3)V99 COMP-3.
           05  WS-TOTAL-FEES-USD           PIC 9(4)V99 COMP-3.
           05  WS-TOTAL-USD-DEBIT          PIC 9(9)V99 COMP-3.
           05  WS-FX-REVENUE-USD           PIC 9(6)V99 COMP-3.
           05  WS-IS-DIRECT-PAIR           PIC X(1)      VALUE 'Y'.
               88  DIRECT-CURRENCY-PAIR      VALUE 'Y'.

       PROCEDURE DIVISION.

       0000-MAIN-PROCESS.
           PERFORM 1000-DETERMINE-CURRENCY-PAIR-TYPE
           PERFORM 2000-CALCULATE-CUSTOMER-RATE
           PERFORM 3000-CONVERT-TO-DESTINATION-CURRENCY
           PERFORM 4000-CALCULATE-WIRE-SERVICE-FEE
           PERFORM 5000-CHECK-SAME-DAY-SURCHARGE
           PERFORM 6000-CALCULATE-TOTAL-DEBIT
           PERFORM 9000-WRITE-WIRE-CONFIRMATION
           STOP RUN.

       1000-DETERMINE-CURRENCY-PAIR-TYPE.
      *    EUR, GBP AND JPY ARE DIRECTLY QUOTED PAIRS; ANY OTHER
      *    DESTINATION CURRENCY REQUIRES ROUTING THROUGH A
      *    CORRESPONDENT BANK, ADDING AN ADDITIONAL FLAT FEE
           MOVE 'Y' TO WS-IS-DIRECT-PAIR
           IF NOT CURR-DIRECT-EUR
              AND NOT CURR-DIRECT-GBP
              AND NOT CURR-DIRECT-JPY
               MOVE 'N' TO WS-IS-DIRECT-PAIR
           END-IF.

       2000-CALCULATE-CUSTOMER-RATE.
      *    CUSTOMER RATE = MID-MARKET RATE LESS THE FX MARGIN (THE
      *    BANK SELLS FOREIGN CURRENCY AT A MARKUP BELOW MID-MARKET
      *    VALUE FOR THE CUSTOMER, KEEPING THE SPREAD AS REVENUE)
           COMPUTE WS-CUSTOMER-RATE ROUNDED =
               WS-MID-MARKET-RATE * (1 - WS-FX-MARGIN-PCT).

       3000-CONVERT-TO-DESTINATION-CURRENCY.
           COMPUTE WS-DESTINATION-AMOUNT ROUNDED =
               WS-USD-SEND-AMOUNT * WS-CUSTOMER-RATE

      *    FX SPREAD REVENUE IS THE DIFFERENCE BETWEEN WHAT THE BANK
      *    PAID AT MID-MARKET AND WHAT IT CHARGED THE CUSTOMER
           COMPUTE WS-FX-REVENUE-USD ROUNDED =
               WS-USD-SEND-AMOUNT * WS-FX-MARGIN-PCT.

       4000-CALCULATE-WIRE-SERVICE-FEE.
      *    TIERED FLAT FEE BASED ON THE USD SEND AMOUNT
           EVALUATE TRUE
               WHEN WS-USD-SEND-AMOUNT <= WS-TIER1-CEILING
                   MOVE WS-TIER1-FEE TO WS-WIRE-SERVICE-FEE
               WHEN WS-USD-SEND-AMOUNT <= WS-TIER2-CEILING
                   MOVE WS-TIER2-FEE TO WS-WIRE-SERVICE-FEE
               WHEN OTHER
                   MOVE WS-TIER3-FEE TO WS-WIRE-SERVICE-FEE
           END-EVALUATE

           IF NOT DIRECT-CURRENCY-PAIR
               ADD WS-CORRESPONDENT-BANK-FEE TO WS-WIRE-SERVICE-FEE
           END-IF.

       5000-CHECK-SAME-DAY-SURCHARGE.
      *    WIRES SUBMITTED AFTER THE 14:00 CUTOFF THAT STILL REQUEST
      *    SAME-DAY PROCESSING INCUR AN ADDITIONAL SURCHARGE
           MOVE 'N' TO WS-SAME-DAY-REQUESTED
           IF WS-REQUEST-TIME > WS-WIRE-CUTOFF-TIME
              AND SAME-DAY-REQUESTED-YES
               ADD WS-SAME-DAY-SURCHARGE TO WS-WIRE-SERVICE-FEE
           END-IF.

       6000-CALCULATE-TOTAL-DEBIT.
           MOVE WS-WIRE-SERVICE-FEE TO WS-TOTAL-FEES-USD
           COMPUTE WS-TOTAL-USD-DEBIT =
               WS-USD-SEND-AMOUNT + WS-TOTAL-FEES-USD.

       9000-WRITE-WIRE-CONFIRMATION.
           DISPLAY 'SENDER ACCOUNT: ' WS-SENDER-ACCOUNT
           DISPLAY 'DESTINATION CURRENCY: ' WS-DESTINATION-CURRENCY
           DISPLAY 'CUSTOMER RATE: ' WS-CUSTOMER-RATE
           DISPLAY 'DESTINATION AMOUNT: ' WS-DESTINATION-AMOUNT
           DISPLAY 'WIRE SERVICE FEE: ' WS-WIRE-SERVICE-FEE
           DISPLAY 'TOTAL USD DEBIT: ' WS-TOTAL-USD-DEBIT
           DISPLAY 'FX REVENUE: ' WS-FX-REVENUE-USD.
