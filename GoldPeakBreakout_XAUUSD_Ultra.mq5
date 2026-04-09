//+------------------------------------------------------------------+
//|                                    GoldPeakBreakout_XAUUSD_Profit.mq5 |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade g_trade;

// Input parameters
input int      InpMagicNumber         = 12345;       // Magic number
input double   InpLotSize            = 0.01;        // Fixed lot size
input int      InpDonchianPeriod     = 15;          // Donchian channel period (more responsive)
input double   InpMinRange           = 1.5;         // Minimum range for breakout (lower for more signals)
input double   InpEntryBuffer        = 0.08;        // Entry buffer in USD (tighter entry)
input double   InpMinBreakout        = 0.15;        // Minimum breakout size in USD (smaller for sensitivity)
input double   InpStopLossMultiplier = 1.2;         // SL multiplier based on ATR (tight stop)
input double   InpTakeProfitMultiplier = 3.0;       // TP multiplier based on ATR (capture large moves)
input bool     InpUseTrailingStop    = true;        // Enable aggressive trailing
input double   InpTrailStart         = 0.8;         // Trail start distance in ATRs (early activation)
input double   InpTrailStep          = 1.0;         // Trail step in ATRs (aggressive trail)
input double   InpBreakEvenOffset    = 0.15;        // Break-even offset in USD (quick break-even)
input int      InpMaxHoldBars        = 50;          // Maximum bars to hold position
input int      InpMinBarsBetween     = 1;           // Minimum bars between trades (increase frequency)
input int      InpMaxTradesPerDay    = 0;           // Max trades per day (0 = unlimited)
input int      InpMaxSpread          = 500;         // Maximum spread in points (higher tolerance)
input bool     InpUseTrendFilter     = false;       // Disable all filters for maximum signals
input bool     InpUseAdxFilter       = false;
input bool     InpUseRsiFilter       = false;
input bool     InpRequireMomentumBar = false;
input bool     InpUseSessionFilter   = false;

// Global variables
double donchianHigh[], donchianLow[];
datetime lastTradeTime[2]; // [BUY][SELL]
int dailyTradeCount = 0;
datetime currentDay = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   if(CopyBuffer(Symbol(), PERIOD_CURRENT, 0, InpDonchianPeriod + 100, donchianHigh) <= 0 ||
      CopyBuffer(Symbol(), PERIOD_CURRENT, 1, InpDonchianPeriod + 100, donchianLow) <= 0)
   {
      Print("Failed to copy buffers");
      return INIT_FAILED;
   }
   
   ArraySetAsSeries(donchianHigh, true);
   ArraySetAsSeries(donchianLow, true);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check spread
   if(Ask - Bid > InpMaxSpread * Point)
      return;
      
   // Reset daily counter
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(IntegerToString(dt.year) + "." + 
                                IntegerToString(dt.mon) + "." + 
                                IntegerToString(dt.day));
   
   if(today != currentDay)
   {
      currentDay = today;
      dailyTradeCount = 0;
   }
   
   // Calculate ATR
   double atr = iATR(Symbol(), PERIOD_CURRENT, 14, 1)[0];
   if(atr == 0) return;
   
   // Calculate Donchian channels
   CalculateDonchian();
   
   // Get current prices
   double currentHigh = High[0];
   double currentLow = Low[0];
   double currentClose = Close[0];
   
   // Check for new bar
   static datetime prevTime = 0;
   if(prevTime != Time[0])
   {
      prevTime = Time[0];
      dailyTradeCount = 0; // Reset on new bar
   }
   
   // Check for exit conditions and trailing
   CheckExits(atr);
   
   // Check for new trades only if we haven't exceeded daily limit
   if(InpMaxTradesPerDay == 0 || dailyTradeCount < InpMaxTradesPerDay)
   {
      // Check BUY signal
      if(CanEnterLong() && ShouldEnterLong(currentHigh, currentClose))
      {
         if(OpenPosition(ORDER_TYPE_BUY, InpLotSize))
         {
            lastTradeTime[0] = Time[0];
            dailyTradeCount++;
         }
      }
      
      // Check SELL signal  
      if(CanEnterShort() && ShouldEnterShort(currentLow, currentClose))
      {
         if(OpenPosition(ORDER_TYPE_SELL, InpLotSize))
         {
            lastTradeTime[1] = Time[0];
            dailyTradeCount++;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Donchian Channels                                      |
//+------------------------------------------------------------------+
void CalculateDonchian()
{
   int copied = CopyHighest(Symbol(), PERIOD_CURRENT, MODE_HIGH, InpDonchianPeriod, 0, donchianHigh);
   int copied2 = CopyLowest(Symbol(), PERIOD_CURRENT, MODE_LOW, InpDonchianPeriod, 0, donchianLow);
   
   if(copied != InpDonchianPeriod || copied2 != InpDonchianPeriod)
      return;
}

//+------------------------------------------------------------------+
//| Check if we can enter long                                       |
//+------------------------------------------------------------------+
bool CanEnterLong()
{
   if(PositionSelect(Symbol()) && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      return false;
      
   if(lastTradeTime[0] != 0 && MathAbs(Time[0] - lastTradeTime[0]) / PeriodSeconds(PERIOD_M1) < InpMinBarsBetween * PeriodSeconds(PeriodCurrent()) / 60)
      return false;
      
   return true;
}

//+------------------------------------------------------------------+
//| Check if we can enter short                                      |
//+------------------------------------------------------------------+
bool CanEnterShort()
{
   if(PositionSelect(Symbol()) && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
      return false;
      
   if(lastTradeTime[1] != 0 && MathAbs(Time[0] - lastTradeTime[1]) / PeriodSeconds(PERIOD_M1) < InpMinBarsBetween * PeriodSeconds(PeriodCurrent()) / 60)
      return false;
      
   return true;
}

//+------------------------------------------------------------------+
//| Check long entry conditions                                      |
//+------------------------------------------------------------------+
bool ShouldEnterLong(double high, double close)
{
   if(high > donchianHigh[1] + InpEntryBuffer)
   {
      double range = donchianHigh[1] - donchianLow[1];
      if(range >= InpMinRange)
      {
         double breakoutSize = high - donchianHigh[1];
         if(breakoutSize >= InpMinBreakout)
         {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check short entry conditions                                     |
//+------------------------------------------------------------------+
bool ShouldEnterShort(double low, double close)
{
   if(low < donchianLow[1] - InpEntryBuffer)
   {
      double range = donchianHigh[1] - donchianLow[1];
      if(range >= InpMinRange)
      {
         double breakoutSize = donchianLow[1] - low;
         if(breakoutSize >= InpMinBreakout)
         {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Open position                                                    |
//+------------------------------------------------------------------+
bool OpenPosition(ENUM_ORDER_TYPE type, double volume)
{
   double price = (type == ORDER_TYPE_BUY) ? Ask : Bid;
   double sl = 0, tp = 0;
   
   // Calculate ATR-based SL and TP
   double atr = iATR(Symbol(), PERIOD_CURRENT, 14, 1)[0];
   if(atr == 0) return false;
   
   if(type == ORDER_TYPE_BUY)
   {
      sl = price - InpStopLossMultiplier * atr;
      tp = price + InpTakeProfitMultiplier * atr;
   }
   else
   {
      sl = price + InpStopLossMultiplier * atr;
      tp = price - InpTakeProfitMultiplier * atr;
   }
   
   return g_trade.PositionOpen(Symbol(), type, volume, price, sl, tp, "GoldPeakBreakout");
}

//+------------------------------------------------------------------+
//| Check exits and trailing                                         |
//+------------------------------------------------------------------+
void CheckExits(double atr)
{
   if(!PositionSelect(Symbol()))
      return;
      
   if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
      return;
      
   ulong ticket = PositionGetInteger(POSITION_TICKET);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentPrice = (posType == POSITION_TYPE_BUY) ? Bid : Ask;
   double profit = (posType == POSITION_TYPE_BUY) ? 
                   (currentPrice - openPrice) * PositionGetDouble(POSITION_VOLUME) / Point :
                   (openPrice - currentPrice) * PositionGetDouble(POSITION_VOLUME) / Point;
   
   // Calculate P/L in points
   double plPoints = (posType == POSITION_TYPE_BUY) ? 
                     (currentPrice - openPrice) / Point :
                     (openPrice - currentPrice) / Point;
   
   // Trailing stop
   if(InpUseTrailingStop && MathAbs(plPoints) > InpTrailStart * atr / Point)
   {
      double newSL = 0;
      if(posType == POSITION_TYPE_BUY)
      {
         newSL = currentPrice - InpTrailStep * atr;
         if(newSL > PositionGetDouble(POSITION_PRICE_SL))
         {
            g_trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_PRICE_TP));
         }
      }
      else
      {
         newSL = currentPrice + InpTrailStep * atr;
         if(newSL < PositionGetDouble(POSITION_PRICE_SL))
         {
            g_trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_PRICE_TP));
         }
      }
   }
   
   // Break-even
   if(MathAbs(plPoints) > InpBreakEvenOffset / Point)
   {
      double newSL = (posType == POSITION_TYPE_BUY) ? 
                     openPrice + InpBreakEvenOffset : 
                     openPrice - InpBreakEvenOffset;
                     
      if((posType == POSITION_TYPE_BUY && newSL > PositionGetDouble(POSITION_PRICE_SL)) ||
         (posType == POSITION_TYPE_SELL && newSL < PositionGetDouble(POSITION_PRICE_SL)))
      {
         g_trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_PRICE_TP));
      }
   }
   
   // Max hold bars check
   datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
   if(Time[0] - openTime > InpMaxHoldBars * PeriodSeconds(PeriodCurrent()))
   {
      g_trade.PositionClose(ticket);
   }
}
