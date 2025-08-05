//+------------------------------------------------------------------+
//|                                                ChartPatterns.mq5 |
//|                                     Expert Advisor by Jules      |
//|                          Trades Bullish and Bearish Pennants     |
//+------------------------------------------------------------------+
#property copyright "Jules"
#property link      ""
#property version   "1.00"
#property strict

//--- include
#include <Trade\Trade.mqh>

//--- input parameters
enum ENUM_PATTERN_TO_TRADE
  {
   BULLISH_PENNANT,
   BEARISH_PENNANT,
   DESCENDING_BROADENING_WEDGE,
   BOTH
  };

input ENUM_PATTERN_TO_TRADE PatternToTrade    = BOTH;         // Pattern to trade
input double                Lots              = 0.01;         // Lot size
input ulong                 MagicNumber       = 12345;        // Magic number for orders
input int                   StopLossPips      = 50;           // Stop loss in pips
input int                   FlagpoleMinHeight = 200;          // Min flagpole height in points
input int                   PennantMaxBars    = 25;           // Max bars for pennant
input int                   LookbackBars      = 100;          // Bars to look back for pattern

//--- global variables
CTrade trade;
int    fractals_handle;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   trade.SetExpertMagicNumber(MagicNumber);
   fractals_handle = iFractals(_Symbol, _Period);
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---

  }
//+------------------------------------------------------------------+
//| Data Handling Functions                                          |
//+------------------------------------------------------------------+
bool GetHistory(int bars, double &high[], double &low[], double &close[], datetime &time[], long &volume[])
  {
   if(CopyHigh(_Symbol, _Period, 0, bars, high) < bars ||
      CopyLow(_Symbol, _Period, 0, bars, low) < bars ||
      CopyClose(_Symbol, _Period, 0, bars, close) < bars ||
      CopyTime(_Symbol, _Period, 0, bars, time) < bars ||
      CopyTickVolume(_Symbol, _Period, 0, bars, volume) < bars)
     {
      Print("Error copying history!");
      return(false);
     }
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(volume, true);
   return(true);
  }
//+------------------------------------------------------------------+
//| Bullish Pennant Detection                                        |
//+------------------------------------------------------------------+
bool IsBullishPennant(const double &high[], const double &low[], const long &volume[],
                      int &flagpoleStartIndex, double &flagpoleHigh, double &flagpoleLow, int &flagpoleBars,
                      double &pennantLow, int &pennantLowIndex, double &breakoutPrice)
{
    // 1. Find the Flagpole
    for(int i = 1; i < LookbackBars - 10; i++)
    {
        if(high[i] > high[i+1] && low[i] > low[i+1] && (high[i] - low[i+10]) > FlagpoleMinHeight * _Point)
        {
            flagpoleStartIndex = i;
            flagpoleHigh = high[i];
            flagpoleLow = low[i+10];
            flagpoleBars = 10;
            break;
        }
    }

    if(flagpoleStartIndex == -1)
        return false;

    // 2. Find the Pennant
    int pennantStartShift = flagpoleStartIndex - flagpoleBars;
    double upper_fractals_buffer[], lower_fractals_buffer[];
    CopyBuffer(fractals_handle, 0, pennantStartShift, PennantMaxBars, upper_fractals_buffer);
    CopyBuffer(fractals_handle, 1, pennantStartShift, PennantMaxBars, lower_fractals_buffer);

    ArraySetAsSeries(upper_fractals_buffer, true);
    ArraySetAsSeries(lower_fractals_buffer, true);

    double upFractal1 = 0, upFractal2 = 0;
    int upFractalIndex1 = 0, upFractalIndex2 = 0;
    double lowFractal1 = 0, lowFractal2 = 0;
    int lowFractalIndex1 = 0, lowFractalIndex2 = 0;

    for (int i = 0; i < PennantMaxBars; i++) {
        if (upper_fractals_buffer[i] > 0) {
            if (upFractal1 == 0) {
                upFractal1 = upper_fractals_buffer[i];
                upFractalIndex1 = i;
            } else {
                upFractal2 = upper_fractals_buffer[i];
                upFractalIndex2 = i;
                break;
            }
        }
    }

    for (int i = 0; i < PennantMaxBars; i++) {
        if (lower_fractals_buffer[i] > 0) {
            if (lowFractal1 == 0) {
                lowFractal1 = lower_fractals_buffer[i];
                lowFractalIndex1 = i;
            } else {
                lowFractal2 = lower_fractals_buffer[i];
                lowFractalIndex2 = i;
                break;
            }
        }
    }

    if(upFractal1 < upFractal2 && lowFractal1 > lowFractal2)
    {
        // 3. Volume Confirmation
        long flagpoleVolume = 0;
        for(int i = flagpoleStartIndex; i > pennantStartShift; i--)
            flagpoleVolume += volume[i];

        long pennantVolume = 0;
        for(int i = pennantStartShift; i > 1; i--)
            pennantVolume += volume[i];

        if(flagpoleVolume > pennantVolume)
        {
            pennantLow = lowFractal1;
            pennantLowIndex = lowFractalIndex1;
            return true;
        }
    }

    return false;
}
//+------------------------------------------------------------------+
//| Bearish Pennant Detection                                        |
//+------------------------------------------------------------------+
bool IsBearishPennant(const double &high[], const double &low[], const long &volume[],
                      int &flagpoleStartIndex, double &flagpoleHigh, double &flagpoleLow, int &flagpoleBars,
                      double &pennantHigh, int &pennantHighIndex, double &breakdownPrice)
{
    // 1. Find the Flagpole
    for(int i = 1; i < LookbackBars - 10; i++)
    {
        if(low[i] < low[i+1] && high[i] < high[i+1] && (high[i+10] - low[i]) > FlagpoleMinHeight * _Point)
        {
            flagpoleStartIndex = i;
            flagpoleHigh = high[i+10];
            flagpoleLow = low[i];
            flagpoleBars = 10;
            break;
        }
    }

    if(flagpoleStartIndex == -1)
        return false;

    // 2. Find the Pennant
    int pennantStartShift = flagpoleStartIndex - flagpoleBars;
    double upper_fractals_buffer[], lower_fractals_buffer[];
    CopyBuffer(fractals_handle, 0, pennantStartShift, PennantMaxBars, upper_fractals_buffer);
    CopyBuffer(fractals_handle, 1, pennantStartShift, PennantMaxBars, lower_fractals_buffer);

    ArraySetAsSeries(upper_fractals_buffer, true);
    ArraySetAsSeries(lower_fractals_buffer, true);

    double upFractal1 = 0, upFractal2 = 0;
    int upFractalIndex1 = 0, upFractalIndex2 = 0;
    double lowFractal1 = 0, lowFractal2 = 0;
    int lowFractalIndex1 = 0, lowFractalIndex2 = 0;

    for (int i = 0; i < PennantMaxBars; i++) {
        if (upper_fractals_buffer[i] > 0) {
            if (upFractal1 == 0) {
                upFractal1 = upper_fractals_buffer[i];
                upFractalIndex1 = i;
            } else {
                upFractal2 = upper_fractals_buffer[i];
                upFractalIndex2 = i;
                break;
            }
        }
    }

    for (int i = 0; i < PennantMaxBars; i++) {
        if (lower_fractals_buffer[i] > 0) {
            if (lowFractal1 == 0) {
                lowFractal1 = lower_fractals_buffer[i];
                lowFractalIndex1 = i;
            } else {
                lowFractal2 = lower_fractals_buffer[i];
                lowFractalIndex2 = i;
                break;
            }
        }
    }

    if(upFractal1 < upFractal2 && lowFractal1 > lowFractal2)
    {
        // 3. Volume Confirmation
        long flagpoleVolume = 0;
        for(int i = flagpoleStartIndex; i > pennantStartShift; i--)
            flagpoleVolume += volume[i];

        long pennantVolume = 0;
        for(int i = pennantStartShift; i > 1; i--)
            pennantVolume += volume[i];

        if(flagpoleVolume > pennantVolume)
        {
            pennantHigh = upFractal1;
            pennantHighIndex = upFractalIndex1;
            return true;
        }
    }

    return false;
}
//+------------------------------------------------------------------+
//| Trading Functions                                                |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, double sl, double tp, string comment)
{
    if(PositionsTotal() > 0)
        return;

    if(type == ORDER_TYPE_BUY)
        trade.Buy(Lots, NULL, 0, sl, tp, comment);
    else if(type == ORDER_TYPE_SELL)
        trade.Sell(Lots, NULL, 0, sl, tp, comment);
}
//+------------------------------------------------------------------+
//| Descending Broadening Wedge Detection                            |
//+------------------------------------------------------------------+
bool IsDescendingBroadeningWedge(const double &high[], const double &low[],
                                 double &breakoutPrice, double &stopLoss, double &takeProfit)
{
    // Find at least 3 lower highs and 3 lower lows
    double upper_fractals[], lower_fractals[];
    int upper_fractal_indices[], lower_fractal_indices[];
    int upper_fractal_count = 0, lower_fractal_count = 0;

    double upper_fractals_buffer[], lower_fractals_buffer[];
    CopyBuffer(fractals_handle, 0, 0, LookbackBars, upper_fractals_buffer);
    CopyBuffer(fractals_handle, 1, 0, LookbackBars, lower_fractals_buffer);

    for(int i = 0; i < LookbackBars; i++)
    {
        if(upper_fractals_buffer[i] > 0)
        {
            ArrayResize(upper_fractals, upper_fractal_count + 1);
            ArrayResize(upper_fractal_indices, upper_fractal_count + 1);
            upper_fractals[upper_fractal_count] = upper_fractals_buffer[i];
            upper_fractal_indices[upper_fractal_count] = i;
            upper_fractal_count++;
        }
        if(lower_fractals_buffer[i] > 0)
        {
            ArrayResize(lower_fractals, lower_fractal_count + 1);
            ArrayResize(lower_fractal_indices, lower_fractal_count + 1);
            lower_fractals[lower_fractal_count] = lower_fractals_buffer[i];
            lower_fractal_indices[lower_fractal_count] = i;
            lower_fractal_count++;
        }
    }

    if(upper_fractal_count < 3 || lower_fractal_count < 3)
        return false;

    // Check for lower highs and lower lows
    if(upper_fractals[0] < upper_fractals[1] && upper_fractals[1] < upper_fractals[2] &&
       low[lower_fractal_indices[0]] < low[lower_fractal_indices[1]] && low[lower_fractal_indices[1]] < low[lower_fractal_indices[2]])
    {
        // Check for divergence
        double upper_slope = (upper_fractals[0] - upper_fractals[2]) / (upper_fractal_indices[0] - upper_fractal_indices[2]);
        double lower_slope = (lower_fractals[0] - lower_fractals[2]) / (lower_fractal_indices[0] - lower_fractal_indices[2]);

        if(upper_slope < 0 && lower_slope < 0 && lower_slope < upper_slope)
        {
            breakoutPrice = upper_fractals[0];
            stopLoss = lower_fractals[0] - StopLossPips * _Point;
            takeProfit = high[upper_fractal_indices[2]]; // Method 1: Highest point of the wedge
            return true;
        }
    }

    return false;
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // We use a static variable to ensure the expert only runs once per bar.
    static datetime lastBarTime = 0;
    if(lastBarTime == TimeCurrent())
        return;
    lastBarTime = TimeCurrent();

    // Get historical data
    double high[], low[], close[];
    datetime time[];
    long volume[];
    if(!GetHistory(LookbackBars, high, low, close, time, volume))
        return;

    // --- Pattern Detection ---
    // --- Pattern Detection ---
    if(PatternToTrade == BULLISH_PENNANT || PatternToTrade == BOTH)
    {
        int flagpoleStartIndex = -1;
        double flagpoleHigh = 0, flagpoleLow = 0;
        int flagpoleBars = 0;
        double pennantLow = 0;
        int pennantLowIndex = 0;
        double breakoutPrice = 0;

        if(IsBullishPennant(high, low, volume, flagpoleStartIndex, flagpoleHigh, flagpoleLow, flagpoleBars, pennantLow, pennantLowIndex, breakoutPrice))
        {
            // Breakout check
            if(close[1] > breakoutPrice)
            {
                double sl = pennantLow - StopLossPips * _Point;
                double tp = close[1] + (flagpoleHigh - flagpoleLow);
                ExecuteTrade(ORDER_TYPE_BUY, sl, tp, "Bullish Pennant");
            }
        }
    }

    if(PatternToTrade == BEARISH_PENNANT || PatternToTrade == BOTH)
    {
        int flagpoleStartIndex = -1;
        double flagpoleHigh = 0, flagpoleLow = 0;
        int flagpoleBars = 0;
        double pennantHigh = 0;
        int pennantHighIndex = 0;
        double breakdownPrice = 0;

        if(IsBearishPennant(high, low, volume, flagpoleStartIndex, flagpoleHigh, flagpoleLow, flagpoleBars, pennantHigh, pennantHighIndex, breakdownPrice))
        {
            // Breakdown check
            if(close[1] < breakdownPrice)
            {
                double sl = pennantHigh + StopLossPips * _Point;
                double tp = close[1] - (flagpoleHigh - flagpoleLow);
                ExecuteTrade(ORDER_TYPE_SELL, sl, tp, "Bearish Pennant");
            }
        }
    }

    if(PatternToTrade == DESCENDING_BROADENING_WEDGE || PatternToTrade == BOTH)
    {
        double breakoutPrice = 0, stopLoss = 0, takeProfit = 0;
        if(IsDescendingBroadeningWedge(high, low, breakoutPrice, stopLoss, takeProfit))
        {
            if(close[1] > breakoutPrice)
            {
                ExecuteTrade(ORDER_TYPE_BUY, stopLoss, takeProfit, "Descending Broadening Wedge");
            }
        }
    }
}
//+------------------------------------------------------------------+
