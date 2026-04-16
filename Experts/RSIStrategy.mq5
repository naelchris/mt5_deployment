//+------------------------------------------------------------------+
//|                                               rsiStrategy2.mq5   |
//|                          Copyright 2023, trustfultrading         |
//|                      https://www.trustfultrading.com             |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, trustfultrading"
#property link      "https://www.trustfultrading.com"
#property version   "1.00"

#include <Trade\Trade.mqh>

// inputs
static input long   InpMagicNumber   = 546812;       // magic number
static input double InpLotSize       = 0.01;         // lot size
input int           InpRSIPeriod     = 21;           // rsi period
input int           InpRSILevel      = 70;           // rsi level (upper)
input int           InpMAPeriod      = 200;          // ma period
input ENUM_TIMEFRAMES InpMaTimeframe = PERIOD_H1;    // ma timeframe
input int           InpStopLoss      = 0;            // stop loss in points (0=off)
input int           InpTakeProfit    = 150;          // take profit in points (0=off)
input bool          InpCloseSignal   = false;        // close trades by opposite signal
input double        InpRiskPercent   = 1.0;          // risk per trade (% of balance)
input int           InpATRPeriod     = 14;           // ATR period for stop distance
input double        InpATRMultiplier = 1.5;          // ATR multiplier for stop distance

// Global variables
int      handleRSI;
int      handleMA;
int      handleATR;
double   bufferRSI[];
double   bufferMA[];
double   bufferATR[];
MqlTick  currentTick;
CTrade   trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // check user inputs
   if(InpMagicNumber <= 0){
      Alert("MagicNumber <= 0");
   }
   if(InpLotSize <= 0 || InpLotSize > 10){
      Alert("Lot size <= 0 or > 10");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpRSIPeriod <= 1){
      Alert("RSI period <= 1");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpRSILevel >= 100 || InpRSILevel <= 50){
      Alert("RSI level >= 100 or <= 50");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpMAPeriod <= 1){
      Alert("MA period <= 1");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpStopLoss < 0){
      Alert("Stop Loss < 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpTakeProfit < 0){
      Alert("Take profit < 0");
      return INIT_PARAMETERS_INCORRECT;
   }

   // set magic number to trade object
   trade.SetExpertMagicNumber(InpMagicNumber);

   // create indicator handles
   handleRSI = iRSI(_Symbol, PERIOD_CURRENT, InpRSIPeriod, PRICE_OPEN);
   if(handleRSI == INVALID_HANDLE){
      Alert("Failed to create indicator handleRSI");
      return INIT_FAILED;
   }

   handleMA = iMA(_Symbol, InpMaTimeframe, InpMAPeriod, 0, MODE_EMA, PRICE_OPEN);
   if(handleMA == INVALID_HANDLE){
      Alert("Failed to create indicator handleMA");
      return INIT_FAILED;
   }

   handleATR = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   if(handleATR == INVALID_HANDLE){
      Alert("Failed to create indicator handleATR");
      return INIT_FAILED;
   }

   // set buffer as series
   ArraySetAsSeries(bufferRSI, true);
   ArraySetAsSeries(bufferMA,  true);
   ArraySetAsSeries(bufferATR, true);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // release indicator handles
   if(handleRSI != INVALID_HANDLE){IndicatorRelease(handleRSI);}
   if(handleMA  != INVALID_HANDLE){IndicatorRelease(handleMA);}
   if(handleATR != INVALID_HANDLE){IndicatorRelease(handleATR);}
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // check if current tick is a new bar open tick
   if(!IsNewBar()){return;}

   // get current tick
   if(!SymbolInfoTick(_Symbol, currentTick)){Print("Failed to get current tick"); return;}

   // get rsi values
   int values = CopyBuffer(handleRSI, 0, 1, 2, bufferRSI);
   if(values != 2){
      Print("Failed to get rsi values");
      return;
   }

   // get ma value
   values = CopyBuffer(handleMA, 0, 0, 1, bufferMA);
   if(values != 1){
      Print("Failed to get ma value");
      return;
   }

   Comment("bufferRSI[0]: ", bufferRSI[0],
           "\nbufferRSI[1]: ", bufferRSI[1],
           "\nbufferMA[0]:  ", bufferMA[0]);

   // count open positions
   int cntBuy, cntSell;
   if(!CountOpenPositions(cntBuy, cntSell)){return;}

   // minimum stop distance: broker stop level + spread buffer
   double minDist = (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) + 1) * _Point
                  + (currentTick.ask - currentTick.bid);

   // check for buy position
   if(cntBuy == 0
      && bufferRSI[1] >= (100 - InpRSILevel)
      && bufferRSI[0] <  (100 - InpRSILevel)
      && currentTick.ask > bufferMA[0])
   {
      if(InpCloseSignal){if(!ClosePositions(2)){return;}}
      double sl = InpStopLoss   == 0 ? 0 : currentTick.ask - MathMax(InpStopLoss   * _Point, minDist);
      double tp = InpTakeProfit == 0 ? 0 : currentTick.ask + MathMax(InpTakeProfit * _Point, minDist);
      if(!NormalizePrice(sl)){return;}
      if(!NormalizePrice(tp)){return;}
      trade.PositionOpen(_Symbol, ORDER_TYPE_BUY, positionSizeAnalyzer(), currentTick.ask, sl, tp, "RSI MA filter EA");
   }

   // check for sell position
   if(cntSell == 0
      && bufferRSI[1] >= InpRSILevel
      && bufferRSI[0] <  InpRSILevel
      && currentTick.bid < bufferMA[0])
   {
      if(InpCloseSignal){if(!ClosePositions(1)){return;}}
      double sl = InpStopLoss   == 0 ? 0 : currentTick.ask + MathMax(InpStopLoss   * _Point, minDist);
      double tp = InpTakeProfit == 0 ? 0 : currentTick.bid - MathMax(InpTakeProfit * _Point, minDist);
      if(!NormalizePrice(sl)){return;}
      if(!NormalizePrice(tp)){return;}
      trade.PositionOpen(_Symbol, ORDER_TYPE_SELL, positionSizeAnalyzer(), currentTick.bid, sl, tp, "RSI MA filter EA");
   }
}

//+------------------------------------------------------------------+
//| Custom functions                                                 |
//+------------------------------------------------------------------+

// check if we have a bar open tick
bool IsNewBar()
{
   static datetime previousTime = 0;
   datetime currentTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(previousTime == currentTime){
      return false;
   }
   previousTime = currentTime;
   return true;
}

// count open positions
bool CountOpenPositions(int &cntBuy, int &cntSell)
{
   cntBuy  = 0;
   cntSell = 0;
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--){
      long ticket = PositionGetTicket(i);
      if(ticket <= 0){Print("Failed to get position ticket"); return false;}
      if(!PositionSelectByTicket(ticket)){Print("Failed to select position"); return false;}
      long magic;
      if(!PositionGetInteger(POSITION_MAGIC, magic)){Print("Failed to get position magicnumber"); return false;}
      if(magic == InpMagicNumber){
         long type;
         if(!PositionGetInteger(POSITION_TYPE, type)){Print("Failed to get position type"); return false;}
         if(type == POSITION_TYPE_BUY) {cntBuy++;}
         if(type == POSITION_TYPE_SELL){cntSell++;}
      }
   }
   return true;
}

// normalize price
bool NormalizePrice(double &price)
{
   double tickSize = 0;
   if(!SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE, tickSize)){
      Print("Failed to get tick size");
      return false;
   }
   price = NormalizeDouble(MathRound(price / tickSize) * tickSize, _Digits);
   return true;
}

// close positions
// all_buy_sell: 0 = close all, 1 = close only buys (skip sells), 2 = close only sells (skip buys)
bool ClosePositions(int all_buy_sell)
{
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--){
      long ticket = PositionGetTicket(i);
      if(ticket <= 0){Print("Failed to get position ticket"); return false;}
      if(!PositionSelectByTicket(ticket)){Print("Failed to select position"); return false;}
      long magic;
      if(!PositionGetInteger(POSITION_MAGIC, magic)){Print("Failed to get position magicnumber"); return false;}
      if(magic == InpMagicNumber){
         long type;
         if(!PositionGetInteger(POSITION_TYPE, type)){Print("Failed to get position type"); return false;}
         if(all_buy_sell == 1 && type == POSITION_TYPE_SELL){continue;}
         if(all_buy_sell == 2 && type == POSITION_TYPE_BUY) {continue;}
         trade.PositionClose(ticket);
         if(trade.ResultRetcode() != TRADE_RETCODE_DONE){
            Print("Failed to close position ticket ", (string)ticket,
                  " result: ", (string)trade.ResultRetcode(),
                  " - ", trade.CheckResultRetcodeDescription());
         }
      }
   }
   return true;
}


// Dynamic position sizing based on three factors:
//  1. Fixed % account risk  — hard cap on how much we lose if stopped out
//  2. ATR stop distance      — wider volatility shrinks the lot size automatically
//  3. RSI signal depth       — deeper overbought/oversold = higher confidence = scale up
double positionSizeAnalyzer()
{
   // --- 1. risk amount in account currency ---
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * InpRiskPercent / 100.0;

   // --- 2. ATR-based stop distance ---
   if(CopyBuffer(handleATR, 0, 1, 1, bufferATR) != 1){
      Print("positionSizeAnalyzer: failed to get ATR");
      return InpLotSize;
   }
   double atrStop = bufferATR[0] * InpATRMultiplier;  // distance in price units
   if(atrStop <= 0){ return InpLotSize; }

   // convert stop distance to account currency per lot
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0){ return InpLotSize; }
   double stopCurrency = (atrStop / tickSize) * tickValue;  // loss in $ if 1 lot hits stop
   if(stopCurrency <= 0){ return InpLotSize; }

   // --- 3. RSI signal confidence (0.5 → 1.0) ---
   // bufferRSI[1] = the bar that crossed the threshold; deeper extreme = higher confidence
   double confidence;
   double upperLevel = (double)InpRSILevel;
   double lowerLevel = 100.0 - upperLevel;

   if(bufferRSI[1] >= upperLevel){
      // sell signal: RSI was in [70, 100] — normalize how deep above 70
      confidence = (bufferRSI[1] - upperLevel) / (100.0 - upperLevel);
   } else {
      // buy signal: RSI was in [0, 30] — normalize how deep below 30
      confidence = (lowerLevel - bufferRSI[1]) / lowerLevel;
   }
   confidence = 0.5 + 0.5 * MathMax(0.0, MathMin(1.0, confidence));  // clamp to [0.5, 1.0]

   // --- 4. calculate lot size ---
   double lotSize = (riskAmount * confidence) / stopCurrency;

   // --- 5. snap to broker constraints ---
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lotSize = MathRound(lotSize / lotStep) * lotStep;
   lotSize = MathMax(lotSize, minLot);
   lotSize = MathMin(lotSize, maxLot);

   return lotSize;
}