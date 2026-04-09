//+------------------------------------------------------------------+
//|                                      GoldPeakBreakout_XAUUSD.mq5 |
//|  v3.0: Donchian su TF segnale (default M5), grafico resta M1.       |
//|  ADX/RSI/ATR sulla stessa TF segnale. Sessione oro stretta.       |
//|  TP/SL default più “trend”: TP largo / SL contenuto (ottimizzare). |
//+------------------------------------------------------------------+
#property copyright "User"
#property version   "3.00"
#property description "GoldPeak v3: TF segnale M5, filtri allineati, sessione 13–18"

#include <Trade/Trade.mqh>

bool MarginEnough(const ENUM_ORDER_TYPE order_type, const double volume, const double price);

input string   InpGeneral        = "=== General ===";
input long     InpMagic            = 96008801;
input double   InpLots             = 0.10;
input string   InpTradeComment     = "GoldPeak";

input string   InpSignal         = "=== Segnale Donchian (TF segnale) ===";
input ENUM_TIMEFRAMES InpSignalTf = PERIOD_M5;   // deve essere >= granularità strategica; M1 = troppo rumore
input int      InpDonchianPeriod   = 20;
input double   InpMinRangeUSD      = 3.0;
input double   InpEntryBufferUSD   = 0.12;
input double   InpMinBreakoutUsd   = 0.35;
input bool     InpRequireOpenInsideChannel = true;

input bool     InpAllowLong       = true;
input bool     InpAllowShort      = true;

input string   InpSmart          = "=== Filtri trend / contesto ===";
input bool     InpUseTrendFilter  = true;
input ENUM_TIMEFRAMES InpTrendTf  = PERIOD_H1;
input int      InpTrendMaPeriod    = 34;
input ENUM_MA_METHOD InpTrendMaMethod = MODE_EMA;

input bool     InpUseAdxFilter     = true;
input int      InpAdxPeriod        = 14;
input double   InpAdxMin           = 23.0;

input bool     InpUseDiFilter      = true;
input double   InpDiMinSeparation  = 4.0;

input bool     InpRequireMomentumBar = true;
input double   InpMinBodyRangePct = 0.40;

input double   InpMinSignalRangeAtrMult = 0.75;
input bool     InpUseRsiFilter    = true;
input int      InpRsiPeriod       = 14;
input double   InpRsiLongMin      = 56.0;
input double   InpRsiLongMax      = 66.0;
input double   InpRsiShortMax     = 47.0;
input double   InpRsiShortMin     = 30.0;

input string   InpExit             = "=== Uscite (USD) — target trend ===";
input double   InpTpUSD            = 10.0;
input double   InpSlUSD            = 3.5;
input int      InpMaxHoldBars      = 36;

input string   InpTrail          = "=== Trail / BE ===";
input bool     InpUseTrail        = false;
input double   InpTrailUsd        = 2.5;
input double   InpTrailStartUsd   = 2.0;
input bool     InpTrailOnNewBarOnly = false;

input bool     InpUseBreakEven     = true;
input double   InpBreakEvenAfterUsd = 2.2;
input double   InpBreakEvenOffsetUsd = 0.2;

input string   InpFilters         = "=== Spread / ATR ===";
input int      InpMaxSpreadPoints = 380;
input bool     InpUseAtrFilter    = true;
input int      InpAtrPeriod       = 14;
input double   InpMinAtrPoints    = 40;

input string   InpFreq            = "=== Frequenza (barre = TF) ===";
input int      InpMaxTradesPerDay = 0;
input int      InpMinBarsBetweenTrades = 2;
input bool     InpUseSessionFilter = true;
input int      InpSessionStartHour = 13;
input int      InpSessionEndHour  = 18;

input string   InpExec            = "=== Esecuzione ===";
input int      InpSlippagePoints  = 80;

input string   InpTester          = "=== OnTester ===";
input bool     InpUseCustomOnTester = true;
input bool     InpTesterPenalizeDd = true;
input int      InpTesterMinTrades  = 20;
input double   InpTesterMinPf     = 1.0;

CTrade   g_trade;
int      g_atrHandle     = INVALID_HANDLE;
int      g_adxHandle     = INVALID_HANDLE;
int      g_trendMaHandle = INVALID_HANDLE;
int      g_rsiHandle     = INVALID_HANDLE;
datetime g_lastSignalBarTime = 0;
int      g_dayKey            = -1;
int      g_tradesToday       = 0;
int      g_barsAtLastTrade   = -1;

int OnInit()
  {
   if(InpDonchianPeriod < 2)
     {
      Print("InpDonchianPeriod deve essere >= 2");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpLots <= 0.0 || InpTpUSD <= 0.0 || InpSlUSD <= 0.0)
     {
      Print("Lots, TP e SL devono essere > 0");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpMinBodyRangePct < 0.0 || InpMinBodyRangePct > 1.0)
     {
      Print("InpMinBodyRangePct tra 0 e 1");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(!InpAllowLong && !InpAllowShort)
     {
      Print("Abilita almeno una direzione");
      return INIT_PARAMETERS_INCORRECT;
     }

   g_trade.SetExpertMagicNumber((int)InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   SetFilling();

   const bool needAtr = InpUseAtrFilter || (InpMinSignalRangeAtrMult > 0.0);
   if(needAtr)
     {
      g_atrHandle = iATR(_Symbol, InpSignalTf, InpAtrPeriod);
      if(g_atrHandle == INVALID_HANDLE)
        {
         Print("Errore iATR su TF segnale");
         return INIT_FAILED;
        }
     }

   if(InpUseRsiFilter)
     {
      g_rsiHandle = iRSI(_Symbol, InpSignalTf, InpRsiPeriod, PRICE_CLOSE);
      if(g_rsiHandle == INVALID_HANDLE)
        {
         Print("Errore iRSI su TF segnale");
         return INIT_FAILED;
        }
     }

   if(InpUseAdxFilter)
     {
      g_adxHandle = iADX(_Symbol, InpSignalTf, InpAdxPeriod);
      if(g_adxHandle == INVALID_HANDLE)
        {
         Print("Errore iADX su TF segnale");
         return INIT_FAILED;
        }
     }

   if(InpUseTrendFilter)
     {
      g_trendMaHandle = iMA(_Symbol, InpTrendTf, InpTrendMaPeriod, 0, InpTrendMaMethod, PRICE_CLOSE);
      if(g_trendMaHandle == INVALID_HANDLE)
        {
         Print("Errore iMA trend");
         return INIT_FAILED;
        }
     }

   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   if(g_adxHandle != INVALID_HANDLE)
      IndicatorRelease(g_adxHandle);
   if(g_trendMaHandle != INVALID_HANDLE)
      IndicatorRelease(g_trendMaHandle);
   if(g_rsiHandle != INVALID_HANDLE)
      IndicatorRelease(g_rsiHandle);
  }

void OnTick()
  {
   UpdateDayCounter();

   const bool newSignalBar = IsNewSignalBar();

   ulong ticket = 0;
   int   dir = 0;
   const bool hasPos = HasOurPosition(ticket, dir);

   if(hasPos)
      ManagePosition(ticket, dir, newSignalBar);

   if(HasOurPosition(ticket, dir))
      return;

   if(!newSignalBar)
      return;

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
      return;

   const long tmode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(tmode == SYMBOL_TRADE_MODE_DISABLED)
      return;

   if(InpMaxTradesPerDay > 0 && g_tradesToday >= InpMaxTradesPerDay)
      return;

   if(!SessionAllows())
      return;

   if(!SpreadAllows())
      return;

   if(!AtrAllows())
      return;

   if(InpMinBarsBetweenTrades > 0 && g_barsAtLastTrade > 0)
     {
      const int barsNow = Bars(_Symbol, InpSignalTf);
      if(barsNow - g_barsAtLastTrade < InpMinBarsBetweenTrades)
         return;
     }

   double upper = 0.0, lower = 0.0, range = 0.0;
   if(!CalcDonchian(upper, lower, range))
      return;

   if(InpMinRangeUSD > 0.0 && range < InpMinRangeUSD)
      return;

   const double buf = InpEntryBufferUSD;
   const double thrBuy = upper + buf;
   const double thrSell = lower - buf;
   const double c1 = iClose(_Symbol, InpSignalTf, 1);

   const double extra = MathMax(0.0, InpMinBreakoutUsd);
   const bool sigBuy  = (c1 > thrBuy + extra);
   const bool sigSell = (c1 < thrSell - extra);

   if(sigBuy && sigSell)
      return;

   if(!SignalRangeAtrOk())
      return;

   if(sigBuy)
     {
      if(!InpAllowLong)
         return;
      if(tmode == SYMBOL_TRADE_MODE_SHORTONLY)
         return;
      if(InpRequireOpenInsideChannel)
        {
         const double op = iOpen(_Symbol, InpSignalTf, 1);
         if(op > thrBuy)
            return;
        }
      if(!TrendAllows(true))
         return;
      if(!AdxAllows(true))
         return;
      if(!MomentumBarOk(true))
         return;
      if(!RsiAllows(true))
         return;
      TryOpen(POSITION_TYPE_BUY);
     }
   else if(sigSell)
     {
      if(!InpAllowShort)
         return;
      if(tmode == SYMBOL_TRADE_MODE_LONGONLY)
         return;
      if(InpRequireOpenInsideChannel)
        {
         const double op = iOpen(_Symbol, InpSignalTf, 1);
         if(op < thrSell)
            return;
        }
      if(!TrendAllows(false))
         return;
      if(!AdxAllows(false))
         return;
      if(!MomentumBarOk(false))
         return;
      if(!RsiAllows(false))
         return;
      TryOpen(POSITION_TYPE_SELL);
     }
  }

double OnTester()
  {
   if(!InpUseCustomOnTester)
      return TesterStatistics(STAT_INITIAL_DEPOSIT) + TesterStatistics(STAT_PROFIT);

   const double trades = TesterStatistics(STAT_TRADES);
   const double pf = TesterStatistics(STAT_PROFIT_FACTOR);
   const double profit = TesterStatistics(STAT_PROFIT);

   if(trades < InpTesterMinTrades)
      return -1.0e9 + trades;

   if(InpTesterMinPf > 0.0 && pf < InpTesterMinPf)
      return -1.0e8 + profit * 0.01;

   double score = trades * MathMax(pf, 0.01);
   if(profit > 0.0)
      score *= MathLog(MathMax(1.0, profit));

   if(InpTesterPenalizeDd)
     {
      const double ddpct = TesterStatistics(STAT_BALANCE_DDREL_PERCENT);
      if(ddpct > 0.0)
         score /= (1.0 + ddpct / 25.0);
     }

   return score;
  }

void SetFilling()
  {
   const int filling = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
  }

bool IsNewSignalBar()
  {
   const datetime t = iTime(_Symbol, InpSignalTf, 0);
   if(t == 0)
      return false;
   if(t != g_lastSignalBarTime)
     {
      g_lastSignalBarTime = t;
      return true;
     }
   return false;
  }

void UpdateDayCounter()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   const int key = dt.year * 1000 + dt.day_of_year;
   if(g_dayKey != key)
     {
      g_dayKey = key;
      g_tradesToday = 0;
     }
  }

bool SessionAllows()
  {
   if(!InpUseSessionFilter)
      return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   const int h = dt.hour;
   if(InpSessionStartHour <= InpSessionEndHour)
      return (h >= InpSessionStartHour && h <= InpSessionEndHour);
   return (h >= InpSessionStartHour || h <= InpSessionEndHour);
  }

bool SpreadAllows()
  {
   if(InpMaxSpreadPoints <= 0)
      return true;
   const int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return spread <= InpMaxSpreadPoints;
  }

bool AtrAllows()
  {
   if(!InpUseAtrFilter)
      return true;
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(g_atrHandle, 0, 1, 1, atr) != 1)
      return false;
   return (atr[0] >= InpMinAtrPoints * _Point);
  }

bool TrendAllows(const bool wantLong)
  {
   if(!InpUseTrendFilter)
      return true;
   if(g_trendMaHandle == INVALID_HANDLE)
      return false;

   double ma[];
   ArraySetAsSeries(ma, true);
   if(CopyBuffer(g_trendMaHandle, 0, 1, 1, ma) != 1)
      return false;

   const double c = iClose(_Symbol, InpTrendTf, 1);
   if(c == 0.0)
      return false;

   if(wantLong)
      return (c > ma[0]);
   return (c < ma[0]);
  }

bool AdxAllows(const bool wantLong)
  {
   if(!InpUseAdxFilter)
      return true;
   if(g_adxHandle == INVALID_HANDLE)
      return false;

   double adx[];
   ArraySetAsSeries(adx, true);
   if(CopyBuffer(g_adxHandle, 0, 1, 1, adx) != 1)
      return false;
   if(adx[0] < InpAdxMin)
      return false;

   if(!InpUseDiFilter)
      return true;

   double pdi[], mdi[];
   ArraySetAsSeries(pdi, true);
   ArraySetAsSeries(mdi, true);
   if(CopyBuffer(g_adxHandle, 1, 1, 1, pdi) != 1)
      return false;
   if(CopyBuffer(g_adxHandle, 2, 1, 1, mdi) != 1)
      return false;

   if(wantLong)
     {
      if(pdi[0] <= mdi[0])
         return false;
      if(InpDiMinSeparation > 0.0 && (pdi[0] - mdi[0]) < InpDiMinSeparation)
         return false;
      return true;
     }
   if(mdi[0] <= pdi[0])
      return false;
   if(InpDiMinSeparation > 0.0 && (mdi[0] - pdi[0]) < InpDiMinSeparation)
      return false;
   return true;
  }

bool SignalRangeAtrOk()
  {
   if(InpMinSignalRangeAtrMult <= 0.0)
      return true;
   if(g_atrHandle == INVALID_HANDLE)
      return false;

   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(g_atrHandle, 0, 1, 1, atr) != 1)
      return false;

   const double h = iHigh(_Symbol, InpSignalTf, 1);
   const double l = iLow(_Symbol, InpSignalTf, 1);
   const double rng = h - l;
   return (rng >= atr[0] * InpMinSignalRangeAtrMult);
  }

bool RsiAllows(const bool wantLong)
  {
   if(!InpUseRsiFilter)
      return true;
   if(g_rsiHandle == INVALID_HANDLE)
      return false;

   double rsi[];
   ArraySetAsSeries(rsi, true);
   if(CopyBuffer(g_rsiHandle, 0, 1, 1, rsi) != 1)
      return false;

   if(wantLong)
      return (rsi[0] >= InpRsiLongMin && rsi[0] <= InpRsiLongMax);
   return (rsi[0] >= InpRsiShortMin && rsi[0] <= InpRsiShortMax);
  }

bool MomentumBarOk(const bool isBuy)
  {
   if(!InpRequireMomentumBar)
      return true;

   const double o = iOpen(_Symbol, InpSignalTf, 1);
   const double c = iClose(_Symbol, InpSignalTf, 1);
   const double h = iHigh(_Symbol, InpSignalTf, 1);
   const double l = iLow(_Symbol, InpSignalTf, 1);
   const double rng = h - l;
   if(rng < _Point * 3.0)
      return false;

   if(isBuy)
     {
      if(c <= o)
         return false;
      return ((c - o) >= rng * InpMinBodyRangePct);
     }

   if(c >= o)
      return false;
   return ((o - c) >= rng * InpMinBodyRangePct);
  }

bool CalcDonchian(double &upper, double &lower, double &range)
  {
   const int need = InpDonchianPeriod + 2;
   if(Bars(_Symbol, InpSignalTf) < need)
      return false;

   upper = -1.0e100;
   lower =  1.0e100;

   for(int i = 2; i <= InpDonchianPeriod + 1; i++)
     {
      upper = MathMax(upper, iHigh(_Symbol, InpSignalTf, i));
      lower = MathMin(lower, iLow(_Symbol, InpSignalTf, i));
     }
   range = upper - lower;
   return (range > 0.0);
  }

bool HasOurPosition(ulong &ticket, int &direction)
  {
   direction = 0;
   ticket = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      const ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;

      ticket = t;
      const ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      direction = (pt == POSITION_TYPE_BUY) ? 1 : -1;
      return true;
     }
   return false;
  }

void TryOpen(const ENUM_POSITION_TYPE type)
  {
   const double price = (type == POSITION_TYPE_BUY)
                        ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                        : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double sl = (type == POSITION_TYPE_BUY) ? (price - InpSlUSD) : (price + InpSlUSD);
   double tp = (type == POSITION_TYPE_BUY) ? (price + InpTpUSD) : (price - InpTpUSD);

   sl = NormalizePrice(sl);
   tp = NormalizePrice(tp);

   StopsNormalize(type, price, sl, tp);

   const double vol = NormalizeVolume(InpLots);
   if(vol <= 0.0)
      return;

   if(type == POSITION_TYPE_BUY)
     {
      if(!MarginEnough(ORDER_TYPE_BUY, vol, price))
         return;
     }
   else
     {
      if(!MarginEnough(ORDER_TYPE_SELL, vol, price))
         return;
     }

   const string cmt = InpTradeComment;
   bool ok = false;
   if(type == POSITION_TYPE_BUY)
      ok = g_trade.Buy(vol, _Symbol, 0.0, sl, tp, cmt);
   else
      ok = g_trade.Sell(vol, _Symbol, 0.0, sl, tp, cmt);

   if(!ok)
     {
      Print("Apertura fallita: ", g_trade.ResultRetcode());
      return;
     }

   g_tradesToday++;
   g_barsAtLastTrade = Bars(_Symbol, InpSignalTf);
  }

void ManagePosition(const ulong ticket, const int direction, const bool newBar)
  {
   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return;

   if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
      (long)PositionGetInteger(POSITION_MAGIC) != InpMagic)
      return;

   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(InpMaxHoldBars > 0)
     {
      const datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      const int shift = iBarShift(_Symbol, PERIOD_CURRENT, openTime, true);
      if(shift >= InpMaxHoldBars)
        {
         g_trade.PositionClose(ticket);
         return;
        }
     }

   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);

   if(InpUseBreakEven)
     {
      const double profitDist = (direction == 1) ? (bid - openPrice) : (openPrice - ask);
      if(profitDist >= InpBreakEvenAfterUsd)
        {
         const double minD = StopsMinDistance();
         if(direction == 1)
           {
            const double be = NormalizePrice(openPrice - InpBreakEvenOffsetUsd);
            if(be > 0.0 && be < bid - minD && (sl < be || sl == 0.0))
              {
               if(g_trade.PositionModify(ticket, be, tp) && PositionSelectByTicket(ticket))
                  sl = PositionGetDouble(POSITION_SL);
              }
           }
         else
           {
            const double be = NormalizePrice(openPrice + InpBreakEvenOffsetUsd);
            if(be > ask + minD && (sl == 0.0 || sl > be))
              {
               if(g_trade.PositionModify(ticket, be, tp) && PositionSelectByTicket(ticket))
                  sl = PositionGetDouble(POSITION_SL);
              }
           }
        }
     }

   if(!InpUseTrail)
      return;

   if(InpTrailOnNewBarOnly && !newBar)
      return;

   if(!PositionSelectByTicket(ticket))
      return;
   sl = PositionGetDouble(POSITION_SL);
   tp = PositionGetDouble(POSITION_TP);
   openPrice = PositionGetDouble(POSITION_PRICE_OPEN);

   const double profitForTrail = (direction == 1) ? (bid - openPrice) : (openPrice - ask);
   if(InpTrailStartUsd > 0.0 && profitForTrail < InpTrailStartUsd)
      return;

   const double minD = StopsMinDistance();
   double newSL = sl;

   if(direction == 1)
     {
      const double trail = NormalizePrice(bid - InpTrailUsd);
      if(trail > sl && trail < bid - minD)
         newSL = trail;
     }
   else
     {
      double trail = NormalizePrice(ask + InpTrailUsd);
      if(sl == 0.0)
        {
         if(trail > ask + minD)
            newSL = trail;
        }
      else if(trail < sl && trail > ask + minD)
         newSL = trail;
     }

   if(newSL != sl && MathAbs(newSL - sl) > (_Point * 0.1))
      g_trade.PositionModify(ticket, newSL, tp);
  }

double NormalizePrice(const double price)
  {
   const int dig = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return NormalizeDouble(price, dig);
  }

double NormalizeVolume(double vol)
  {
   const double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   const double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st = (step > 0.0) ? step : 0.01;

   vol = MathFloor(vol / st + 1e-12) * st;
   if(vol < vmin)
      vol = vmin;
   if(vol > vmax)
      vol = vmax;
   return vol;
  }

double StopsMinDistance()
  {
   const int stops = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const int freeze = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   const double m = (double)MathMax(stops, freeze) * _Point;
   return MathMax(m, _Point);
  }

void StopsNormalize(const ENUM_POSITION_TYPE type, const double price, double &sl, double &tp)
  {
   const double minDist = StopsMinDistance();

   if(type == POSITION_TYPE_BUY)
     {
      if(price - sl < minDist)
         sl = NormalizePrice(price - minDist);
      if(tp - price < minDist)
         tp = NormalizePrice(price + minDist);
     }
   else
     {
      if(sl - price < minDist)
         sl = NormalizePrice(price + minDist);
      if(price - tp < minDist)
         tp = NormalizePrice(price - minDist);
     }
  }

bool MarginEnough(const ENUM_ORDER_TYPE order_type, const double volume, const double price)
  {
   double margin = 0.0;
   if(!OrderCalcMargin(order_type, _Symbol, volume, price, margin))
      return false;
   const double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   return (free >= margin * 1.05);
  }

//+------------------------------------------------------------------+
