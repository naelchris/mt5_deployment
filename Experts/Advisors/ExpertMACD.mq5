//+------------------------------------------------------------------+
//|                                              Nick_Shawn_DCA.mq5  |
//|                                                       René Balke |
//+------------------------------------------------------------------+
#property copyright "René Balke"
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Input Variables
input double Lots               = 0.01;
input int    DaysBack           = 30;
input int    ATR_Periods        = 14;
input ENUM_TIMEFRAMES ATR_TimeFrame = PERIOD_H1;
input int    ATR_Decline_Period = 5;
input int    MaxPositions         = 5;         // Max DCA layers before stopping
input double DCA_ATR_Step         = 1.5;       // Price must move X * ATR away from avg entry before next DCA
input double TP_ATR_Multi         = 2.0;       // Close all when bid >= avg entry + X * ATR
input double SL_ATR_Multi         = 4.0;       // Close all when bid <= first entry - X * ATR
input double MarginSafetyFactor   = 3.0;       // Require X * margin_needed as free margin before opening

//--- Global Variables
CTrade trade;

//--- Symbol Class definition to manage multiple pairs
class CSymbol
  {
public:
   string            symbol;
   int               handle_ATR;
   datetime          last_bar_time;
   double            first_entry_price;

                     CSymbol(string sym)
     {
      symbol            = sym;
      last_bar_time     = 0;
      first_entry_price = 0;
      handle_ATR        = iATR(symbol, ATR_TimeFrame, ATR_Periods);
     }
                    ~CSymbol()
     {
      IndicatorRelease(handle_ATR);
     }
  };

// (Assuming a list of CSymbol objects is created and managed here)
CSymbol *symbols[]; 

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   ArrayResize(symbols, 1);
   symbols[0] = new CSymbol("EURUSD");

   // Warn if account balance cannot support the worst-case lot exposure
   double maxTotalLots = 0;
   for(int layer = 0; layer < MaxPositions; layer++)
      maxTotalLots += Lots * MathPow(2.0, layer);

   double marginNeeded;
   string sym = symbols[0].symbol;
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   if(ask <= 0) ask = SymbolInfoDouble(sym, SYMBOL_BID); // fallback for strategy tester

   if(OrderCalcMargin(ORDER_TYPE_BUY, sym, maxTotalLots, ask, marginNeeded))
     {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(balance < marginNeeded * MarginSafetyFactor)
        {
         PrintFormat("WARNING: Account balance %.2f is too small. Max exposure %.2f lots needs %.2f margin (x%.1f safety = %.2f). Reduce Lots or MaxPositions.",
                     balance, maxTotalLots, marginNeeded, MarginSafetyFactor, marginNeeded * MarginSafetyFactor);
        }
     }

   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   for(int i = 0; i < ArraySize(symbols); i++)
      delete symbols[i];
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   for(int i = 0; i < ArraySize(symbols); i++)
     {
      CSymbol *cs = symbols[i];

      // -------------------------------------------------------
      // STEP 1 (every tick): Collect open positions for symbol
      // -------------------------------------------------------
      int    posCount  = 0;
      double totalLots = 0;
      double avgEntry  = 0;
      ulong  tickets[];

      for(int j = PositionsTotal() - 1; j >= 0; j--)
        {
         if(PositionGetSymbol(j) == cs.symbol)
           {
            double pLots = PositionGetDouble(POSITION_VOLUME);
            double pOpen = PositionGetDouble(POSITION_PRICE_OPEN);
            avgEntry  += pOpen * pLots;
            totalLots += pLots;
            posCount++;
            ArrayResize(tickets, posCount);
            tickets[posCount - 1] = PositionGetTicket(j);
           }
        }
      if(posCount > 0)
         avgEntry = avgEntry / totalLots;

      // -------------------------------------------------------
      // STEP 2 (every tick): Check TP / SL — react intrabar
      // -------------------------------------------------------
      if(posCount > 0)
        {
         double atr_tick[];
         ArraySetAsSeries(atr_tick, true);
         CopyBuffer(cs.handle_ATR, 0, 0, 1, atr_tick);
         double atr_now = atr_tick[0];

         double bid = SymbolInfoDouble(cs.symbol, SYMBOL_BID);

         bool closeAll = false;
         if(bid >= avgEntry + TP_ATR_Multi * atr_now)
            closeAll = true; // Take profit
         if(cs.first_entry_price > 0 && bid <= cs.first_entry_price - SL_ATR_Multi * atr_now)
            closeAll = true; // Stop loss

         if(closeAll)
           {
            for(int k = 0; k < ArraySize(tickets); k++)
               trade.PositionClose(tickets[k]);
            cs.first_entry_price = 0;
            continue; // Skip entry logic this tick
           }
        }

      // -------------------------------------------------------
      // STEP 3 (new bar only): Evaluate entry signals
      // -------------------------------------------------------
      datetime current_time = iTime(cs.symbol, ATR_TimeFrame, 0);
      if(current_time == cs.last_bar_time)
         continue;
      cs.last_bar_time = current_time;

      double ATR_array[];
      ArraySetAsSeries(ATR_array, true);
      if(CopyBuffer(cs.handle_ATR, 0, 1, ATR_Decline_Period, ATR_array) < ATR_Decline_Period)
         continue;

      double atr_current = ATR_array[0];
      bool   is_ATR_signal = (ATR_array[ATR_Decline_Period - 1] > ATR_array[0]);

      if(is_ATR_signal)
        {
         double ask = SymbolInfoDouble(cs.symbol, SYMBOL_ASK);

         if(posCount == 0)
           {
            if(HasEnoughMargin(cs.symbol, Lots, ask) && trade.Buy(Lots, cs.symbol))
               cs.first_entry_price = ask;
           }
         else if(posCount < MaxPositions)
           {
            // DCA only if price dropped enough from weighted avg entry
            if(ask <= avgEntry - DCA_ATR_Step * atr_current)
              {
               double lots = CalculateMartingaleLots(cs.symbol, posCount);
               if(HasEnoughMargin(cs.symbol, lots, ask))
                  trade.Buy(lots, cs.symbol);
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Example Placeholder for local lot calculation                    |
//+------------------------------------------------------------------+
bool HasEnoughMargin(string sym, double lots, double price)
  {
   double marginNeeded;
   if(!OrderCalcMargin(ORDER_TYPE_BUY, sym, lots, price, marginNeeded))
      return false;
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(freeMargin < marginNeeded * MarginSafetyFactor)
     {
      PrintFormat("Skipping trade on %s: free margin %.2f < required %.2f (x%.1f safety)",
                  sym, freeMargin, marginNeeded, MarginSafetyFactor);
      return false;
     }
   return true;
  }

double CalculateMartingaleLots(string sym, int posCount)
  {
   // Double lots with each DCA layer: 0.01, 0.02, 0.04, 0.08, ...
   double lots = Lots * MathPow(2.0, posCount);
   double minLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   lots = MathRound(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return lots;
  }
//+------------------------------------------------------------------+