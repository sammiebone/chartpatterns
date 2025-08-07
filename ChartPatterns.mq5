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
   ASCENDING_BROADENING_WEDGE,
   BULLISH_RECTANGLE,
   BEARISH_RECTANGLE,
   BULLISH_FLAG,
   BEARISH_FLAG,
   HEAD_AND_SHOULDERS,
   INVERTED_HEAD_AND_SHOULDERS,
   FALLING_WEDGE,
   SYMMETRICAL_TRIANGLE,
   BROADENING_TRIANGLE,
   ASCENDING_TRIANGLE,
   DESCENDING_TRIANGLE,
   DOUBLE_TOP,
   DOUBLE_BOTTOM,
   ALL
  };

input ENUM_PATTERN_TO_TRADE PatternToTrade    = ALL;         // Pattern to trade
input double                Lots              = 0.01;         // Lot size
input ulong                 MagicNumber       = 12345;        // Magic number for orders
input int                   StopLossPips      = 50;           // Stop loss in pips
input int                   FlagpoleMinHeight = 200;          // Min flagpole height in points
input int                   PennantMaxBars    = 25;           // Max bars for pennant
input int                   LookbackBars      = 100;          // Bars to look back for pattern
input int                   UptrendMinHeight  = 300;          // Minimum height of the preceding uptrend for Ascending Wedge
input bool                  TradeFailedWedgeBreakouts = true; // Trade bullish breakouts from Ascending Wedges
input int                   RsiPeriod         = 14;           // RSI Period
input int                   RsiDivergenceLookback = 30;       // Lookback for RSI Divergence
input int                   DowntrendMinHeight = 300;         // Minimum height of the preceding downtrend for Descending Wedge
input int                   MacdFastEmaPeriod = 12;         // MACD Fast EMA Period
input int                   MacdSlowEmaPeriod = 26;         // MACD Slow EMA Period
input int                   MacdSignalPeriod  = 9;            // MACD Signal Period
input int                   LongTermMaPeriod  = 200;          // Long-Term Moving Average Period
input int                   TP1_Pips = 20;                    // Take Profit 1 in pips
input int                   TP2_Pips = 50;                    // Take Profit 2 in pips
input int                   TP3_Pips = 100;                   // Take Profit 3 in pips
input bool                  EnableTrailingStop = true;        // Enable Trailing Stop to TP1
input int                   TrailingStopPlusPips = 10;        // Pips to add to SL when trailing
input int                   RectangleMinDuration = 10;        // Minimum duration of a rectangle in bars
input int                   RectangleMaxDuration = 50;        // Maximum duration of a rectangle in bars
input int                   FlagMaxDuration   = 20;           // Maximum duration of a flag in bars
input double                SymmetryTolerance = 0.2;          // Tolerance for H&S symmetry (0-1)
input double                ApexRatio         = 0.75;         // Apex ratio for triangles (0-1)
input int                   MinPeakDistance   = 10;           // Min bars between Double Top/Bottom peaks
input int                   MaxPeakDistance   = 50;           // Max bars between Double Top/Bottom peaks

//--- global variables
CTrade trade;
int    fractals_handle;
int    rsi_handle;
int    macd_handle;
int    ma_handle;
int    scaled_FlagpoleMinHeight;
int    scaled_DowntrendMinHeight;
int    scaled_UptrendMinHeight;

//+------------------------------------------------------------------+
//| Timeframe Parameter Scaling                                      |
//+------------------------------------------------------------------+
void ScaleParametersByTimeframe()
{
    scaled_FlagpoleMinHeight = FlagpoleMinHeight;
    scaled_DowntrendMinHeight = DowntrendMinHeight;
    scaled_UptrendMinHeight = UptrendMinHeight;

    switch((int)_Period)
    {
        case PERIOD_M1:
            scaled_FlagpoleMinHeight /= 4;
            scaled_DowntrendMinHeight /= 4;
            scaled_UptrendMinHeight /= 4;
            break;
        case PERIOD_M5:
            scaled_FlagpoleMinHeight /= 2;
            scaled_DowntrendMinHeight /= 2;
            scaled_UptrendMinHeight /= 2;
            break;
        case PERIOD_H1:
            scaled_FlagpoleMinHeight *= 2;
            scaled_DowntrendMinHeight *= 2;
            scaled_UptrendMinHeight *= 2;
            break;
        case PERIOD_D1:
            scaled_FlagpoleMinHeight *= 4;
            scaled_DowntrendMinHeight *= 4;
            scaled_UptrendMinHeight *= 4;
            break;
    }
}
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   trade.SetExpertMagicNumber(MagicNumber);
   fractals_handle = iFractals(_Symbol, _Period);
   if(fractals_handle == INVALID_HANDLE)
   {
       Print("Error creating Fractals indicator handle - error: ", GetLastError());
       return(INIT_FAILED);
   }
   rsi_handle = iRSI(_Symbol, _Period, RsiPeriod, PRICE_CLOSE);
   if(rsi_handle == INVALID_HANDLE)
   {
       Print("Error creating RSI indicator handle - error: ", GetLastError());
       return(INIT_FAILED);
   }
   macd_handle = iMACD(_Symbol, _Period, MacdFastEmaPeriod, MacdSlowEmaPeriod, MacdSignalPeriod, PRICE_CLOSE);
   if(macd_handle == INVALID_HANDLE)
   {
       Print("Error creating MACD indicator handle - error: ", GetLastError());
       return(INIT_FAILED);
   }
   ma_handle = iMA(_Symbol, _Period, LongTermMaPeriod, 0, MODE_SMA, PRICE_CLOSE);
   if(ma_handle == INVALID_HANDLE)
   {
       Print("Error creating MA indicator handle - error: ", GetLastError());
       return(INIT_FAILED);
   }
   ScaleParametersByTimeframe();
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
    Print("Analyzing for Bullish Pennant...");
    // 1. Find the Flagpole
    flagpoleStartIndex = -1;
    for(int i = 1; i < LookbackBars - 20; i++)
    {
        if(high[i] > high[i+1] && low[i] > low[i+1] && (high[i] - low[i+10]) > scaled_FlagpoleMinHeight * _Point)
        {
            // Confirm preceding uptrend
            if(i + 20 >= LookbackBars)
            {
                Print("Bullish Pennant: Not enough historical data for preceding trend check.");
                continue;
            }
            double price_at_flagpole_start = low[i+10];
            double price_before_flagpole = low[i + 20]; // 10 bars before flagpole
            if(price_at_flagpole_start - price_before_flagpole > scaled_UptrendMinHeight * _Point)
            {
                flagpoleStartIndex = i;
                flagpoleHigh = high[i];
                flagpoleLow = low[i+10];
                flagpoleBars = 10;
                break;
            }
        }
    }

    if(flagpoleStartIndex == -1)
    {
        Print("Bullish Pennant: Flagpole not found.");
        return false;
    }
    else
    {
        Print("Bullish Pennant: Flagpole found at index ", flagpoleStartIndex);
    }

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

    // Check for converging trendlines
    double upper_slope = (upFractal1 - upFractal2) / (upFractalIndex1 - upFractalIndex2);
    double lower_slope = (lowFractal1 - lowFractal2) / (lowFractalIndex1 - lowFractalIndex2);

    if(upper_slope < 0 && lower_slope > 0)
    {
        Print("Bullish Pennant: Converging trendlines found.");
        // 3. Volume Confirmation
        long flagpoleVolume = 0;
        for(int i = flagpoleStartIndex; i > pennantStartShift; i--)
            flagpoleVolume += volume[i];

        long pennantVolume = 0;
        for(int i = pennantStartShift; i > 1; i--)
            pennantVolume += volume[i];

        if(flagpoleVolume > pennantVolume)
        {
            Print("Bullish Pennant: Volume confirmed.");
            if(CheckLongTermTrend(low))
            {
                Print("Bullish Pennant: Long-term trend confirmed.");
                if(CheckMACDConfirmation(BULLISH_CROSS))
                {
                    Print("Bullish Pennant: MACD confirmed.");
                    Print("Bullish Pennant confirmed.");
                    pennantLow = lowFractal1;
                    pennantLowIndex = lowFractalIndex1;
                    breakoutPrice = upFractal1;
                    return true;
                }
                 else { Print("Bullish Pennant: MACD not confirmed."); }
            }
             else { Print("Bullish Pennant: Long-term trend not confirmed."); }
        }
         else { Print("Bullish Pennant: Volume not confirmed."); }
    }
     else { Print("Bullish Pennant: Converging trendlines not found."); }

    return false;
}
//+------------------------------------------------------------------+
//| Double Bottom Detection                                          |
//+------------------------------------------------------------------+
bool IsDoubleBottom(const double &high[], const double &low[], const long &volume[],
                    double &breakoutPrice, double &stopLoss, double &takeProfit)
{
    Print("Analyzing for Double Bottom...");
    // Find at least 2 troughs and 1 peak
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

    if(lower_fractal_count < 2 || upper_fractal_count < 1)
    {
        Print("Double Bottom: Not enough fractals.");
        return false;
    }

    double trough1 = low[lower_fractal_indices[1]];
    int trough1_index = lower_fractal_indices[1];
    double trough2 = low[lower_fractal_indices[0]];
    int trough2_index = lower_fractal_indices[0];
    double peak = upper_fractals[0];
    int peak_index = upper_fractal_indices[0];

    // Basic structure: peak must be between the two troughs
    if(peak_index < trough1_index && peak_index > trough2_index)
    {
        // Prior Trend Confirmation
        if(trough1_index + 20 >= LookbackBars)
        {
            Print("Double Bottom: Not enough historical data for preceding trend check.");
            return false;
        }
        double price_before_pattern = high[trough1_index + 20];
        if(price_before_pattern - trough1 > scaled_DowntrendMinHeight * _Point)
        {
            Print("Double Bottom: Preceding downtrend confirmed.");

            // Trough Alignment Check
            double tolerance = 15 * _Point;
            if(MathAbs(trough1 - trough2) < tolerance)
            {
                Print("Double Bottom: Troughs are aligned.");

                // Time Between Troughs Check
                int trough_distance = trough1_index - trough2_index;
                if(trough_distance >= MinPeakDistance && trough_distance <= MaxPeakDistance)
                {
                    Print("Double Bottom: Trough distance is valid.");

                    // Volume Confirmation
                    long trough1_volume = 0;
                    long trough2_volume = 0;
                    for(int i = trough1_index; i > peak_index; i--) trough1_volume += volume[i];
                    for(int i = peak_index; i > trough2_index; i--) trough2_volume += volume[i];

                    if(trough2_volume < trough1_volume)
                    {
                        Print("Double Bottom: Volume confirmed.");
                        breakoutPrice = peak;
                        stopLoss = MathMin(trough1, trough2) - StopLossPips * _Point;
                        takeProfit = breakoutPrice + (peak - MathMin(trough1, trough2));
                        return true;
                    }
                    else { Print("Double Bottom: Volume not confirmed."); }
                }
                else { Print("Double Bottom: Trough distance is not valid."); }
            }
            else { Print("Double Bottom: Troughs are not aligned."); }
        }
        else { Print("Double Bottom: Preceding downtrend not confirmed."); }
    }

    return false;
}
//+------------------------------------------------------------------+
//| Double Top Detection                                             |
//+------------------------------------------------------------------+
bool IsDoubleTop(const double &high[], const double &low[], const long &volume[],
                 double &breakdownPrice, double &stopLoss, double &takeProfit)
{
    Print("Analyzing for Double Top...");
    // Find at least 2 peaks and 1 trough
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

    if(upper_fractal_count < 2 || lower_fractal_count < 1)
    {
        Print("Double Top: Not enough fractals.");
        return false;
    }

    double peak1 = upper_fractals[1];
    int peak1_index = upper_fractal_indices[1];
    double peak2 = upper_fractals[0];
    int peak2_index = upper_fractal_indices[0];
    double trough = low[lower_fractal_indices[0]];
    int trough_index = lower_fractal_indices[0];

    // Basic structure: trough must be between the two peaks
    if(trough_index < peak1_index && trough_index > peak2_index)
    {
        // Prior Trend Confirmation
        if(peak1_index + 20 >= LookbackBars)
        {
            Print("Double Top: Not enough historical data for preceding trend check.");
            return false;
        }
        double price_before_pattern = low[peak1_index + 20];
        if(peak1 - price_before_pattern > scaled_UptrendMinHeight * _Point)
        {
            Print("Double Top: Preceding uptrend confirmed.");

            // Peak Alignment Check
            double tolerance = 15 * _Point;
            if(MathAbs(peak1 - peak2) < tolerance)
            {
                Print("Double Top: Peaks are aligned.");

                // Time Between Peaks Check
                int peak_distance = peak1_index - peak2_index;
                if(peak_distance >= MinPeakDistance && peak_distance <= MaxPeakDistance)
                {
                    Print("Double Top: Peak distance is valid.");

                    // Volume Confirmation
                    long peak1_volume = 0;
                    long peak2_volume = 0;
                    for(int i = peak1_index; i > trough_index; i--) peak1_volume += volume[i];
                    for(int i = trough_index; i > peak2_index; i--) peak2_volume += volume[i];

                    if(peak2_volume < peak1_volume)
                    {
                        Print("Double Top: Volume confirmed.");
                        breakdownPrice = trough;
                        stopLoss = MathMax(peak1, peak2) + StopLossPips * _Point;
                        takeProfit = breakdownPrice - (MathMax(peak1, peak2) - trough);
                        return true;
                    }
                    else { Print("Double Top: Volume not confirmed."); }
                }
                else { Print("Double Top: Peak distance is not valid."); }
            }
            else { Print("Double Top: Peaks are not aligned."); }
        }
        else { Print("Double Top: Preceding uptrend not confirmed."); }
    }

    return false;
}
//+------------------------------------------------------------------+
//| Descending Triangle Detection                                    |
//+------------------------------------------------------------------+
bool IsDescendingTriangle(const double &high[], const double &low[], const long &volume[],
                          double &breakdownPrice, double &stopLoss, double &takeProfit)
{
    Print("Analyzing for Descending Triangle...");
    // Find at least 2 lower highs and 2 flat lows
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

    if(upper_fractal_count < 2 || lower_fractal_count < 2)
    {
        Print("Descending Triangle: Not enough fractals.");
        return false;
    }

    // Check for flat support and lower highs
    double support_level = (low[lower_fractal_indices[0]] + low[lower_fractal_indices[1]]) / 2;
    double tolerance = 10 * _Point;
    if(MathAbs(low[lower_fractal_indices[0]] - support_level) < tolerance && MathAbs(low[lower_fractal_indices[1]] - support_level) < tolerance &&
       upper_fractals[0] < upper_fractals[1])
    {
        Print("Descending Triangle: Flat support and lower highs found.");

        // Prior Trend Confirmation
        int pattern_start_index = MathMax(upper_fractal_indices[1], lower_fractal_indices[1]);
        if(pattern_start_index + 20 >= LookbackBars)
        {
            Print("Descending Triangle: Not enough historical data for preceding trend check.");
            return false;
        }
        double price_at_pattern_start = high[pattern_start_index];
        double price_before_pattern = high[pattern_start_index + 20];
        if(price_before_pattern - price_at_pattern_start > scaled_DowntrendMinHeight * _Point)
        {
            Print("Descending Triangle: Preceding downtrend confirmed.");

            // Volume Confirmation
            long pattern_volume = 0;
            for(int i = pattern_start_index; i > 1; i--)
                pattern_volume += volume[i];

            if(volume[1] < (pattern_volume / (pattern_start_index - 1)))
            {
                Print("Descending Triangle: Diminishing volume confirmed.");
                breakdownPrice = support_level;
                stopLoss = upper_fractals[0] + StopLossPips * _Point;
                takeProfit = breakdownPrice - (upper_fractals[1] - support_level);
                return true;
            }
            else { Print("Descending Triangle: Diminishing volume not confirmed."); }
        }
        else { Print("Descending Triangle: Preceding downtrend not confirmed."); }
    }
    else { Print("Descending Triangle: Flat support and lower highs not found."); }

    return false;
}
//+------------------------------------------------------------------+
//| Falling Wedge Detection                                          |
//+------------------------------------------------------------------+
bool IsFallingWedge(const double &high[], const double &low[], const long &volume[],
                    double &breakoutPrice, double &stopLoss, double &takeProfit)
{
    Print("Analyzing for Falling Wedge...");
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
    {
        Print("Falling Wedge: Not enough fractals.");
        return false;
    }

    // Check for lower highs and lower lows
    if(upper_fractals[0] < upper_fractals[1] && upper_fractals[1] < upper_fractals[2] &&
       low[lower_fractal_indices[0]] < low[lower_fractal_indices[1]] && low[lower_fractal_indices[1]] < low[lower_fractal_indices[2]])
    {
        Print("Falling Wedge: Lower highs and lower lows found.");
        // Check for converging trendlines
        double upper_slope = (upper_fractals[0] - upper_fractals[2]) / (upper_fractal_indices[0] - upper_fractal_indices[2]);
        double lower_slope = (low[lower_fractal_indices[0]] - low[lower_fractal_indices[2]]) / (lower_fractal_indices[0] - lower_fractal_indices[2]);

        if(upper_slope < 0 && lower_slope < 0 && upper_slope < lower_slope)
        {
            Print("Falling Wedge: Converging trendlines found.");
            // Volume Confirmation
            long wedgeVolume = 0;
            for(int i = upper_fractal_indices[2]; i > 1; i--)
                wedgeVolume += volume[i];

            if(volume[1] > wedgeVolume / (upper_fractal_indices[2] - 1))
            {
                Print("Falling Wedge: Volume confirmed.");
                // RSI Divergence Confirmation
                if(CheckRSIDivergence(low, lower_fractal_indices[0], lower_fractal_indices[2], BULLISH_DIVERGENCE))
                {
                    Print("Falling Wedge: RSI divergence confirmed.");
                    breakoutPrice = upper_fractals[0];
                    stopLoss = lower_fractals[0] - StopLossPips * _Point;
                    takeProfit = breakoutPrice + (upper_fractals[2] - low[lower_fractal_indices[2]]);
                    return true;
                }
                 else { Print("Falling Wedge: RSI divergence not confirmed."); }
            }
             else { Print("Falling Wedge: Volume not confirmed."); }
        }
         else { Print("Falling Wedge: Converging trendlines not found."); }
    }
     else { Print("Falling Wedge: Lower highs and lower lows not found."); }

    return false;
}
//+------------------------------------------------------------------+
//| Inverted Head and Shoulders Detection                            |
//+------------------------------------------------------------------+
bool IsInvertedHeadAndShoulders(const double &high[], const double &low[], const long &volume[],
                                double &breakoutPrice, double &stopLoss, double &takeProfit)
{
    Print("Analyzing for Inverted Head and Shoulders...");
    // Find 3 troughs (fractals)
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

    if(lower_fractal_count < 3 || upper_fractal_count < 2)
    {
        Print("Inverted Head and Shoulders: Not enough fractals.");
        return false;
    }

    // Identify Left Shoulder, Head, and Right Shoulder
    double leftShoulder = lower_fractals[2];
    int leftShoulderIndex = lower_fractal_indices[2];
    double head = lower_fractals[1];
    int headIndex = lower_fractal_indices[1];
    double rightShoulder = lower_fractals[0];
    int rightShoulderIndex = lower_fractal_indices[0];

    if(head < leftShoulder && head < rightShoulder)
    {
        Print("Inverted Head and Shoulders: Head and shoulders structure found.");
        // Symmetry Check
        double shoulderHeightDifference = MathAbs(leftShoulder - rightShoulder);
        if(shoulderHeightDifference > (MathMax(leftShoulder, rightShoulder) - head) * SymmetryTolerance)
        {
            Print("Inverted Head and Shoulders: Symmetry check failed (height).");
            return false;
        }

        int leftDuration = headIndex - leftShoulderIndex;
        int rightDuration = rightShoulderIndex - headIndex;
        double durationDifference = MathAbs(leftDuration - rightDuration);
        if(durationDifference > MathMin(leftDuration, rightDuration) * SymmetryTolerance)
        {
            Print("Inverted Head and Shoulders: Symmetry check failed (duration).");
            return false;
        }
        Print("Inverted Head and Shoulders: Symmetry confirmed.");

        // Identify Neckline
        double necklineHigh1 = upper_fractals[1];
        int necklineHighIndex1 = upper_fractal_indices[1];
        double necklineHigh2 = upper_fractals[0];
        int necklineHighIndex2 = upper_fractal_indices[0];

        // Neckline Slope Analysis
        double necklineSlope = (necklineHigh1 - necklineHigh2) / (necklineHighIndex1 - necklineHighIndex2);
        if(necklineSlope < 0)
        {
            Print("Inverted Head and Shoulders: Neckline slope is downward.");
            return false;
        }
        Print("Inverted Head and Shoulders: Neckline slope confirmed.");

        // Confirm preceding downtrend
        if(leftShoulderIndex + 20 >= LookbackBars)
        {
            Print("Inverted Head and Shoulders: Not enough historical data for preceding trend check.");
            return false;
        }
        double price_at_pattern_start = high[leftShoulderIndex];
        double price_before_pattern = high[leftShoulderIndex + 20]; // 20 bars before pattern
        if(price_before_pattern - price_at_pattern_start > scaled_DowntrendMinHeight * _Point)
        {
            Print("Inverted Head and Shoulders: Preceding downtrend confirmed.");
            // Volume Confirmation
            long leftShoulderVolume = 0;
            for(int i = leftShoulderIndex; i > headIndex; i--)
                leftShoulderVolume += volume[i];

            long headVolume = 0;
            for(int i = headIndex; i > rightShoulderIndex; i--)
                headVolume += volume[i];

            long rightShoulderVolume = 0;
            for(int i = rightShoulderIndex; i > 1; i--)
                rightShoulderVolume += volume[i];

            if(leftShoulderVolume > headVolume && headVolume > rightShoulderVolume)
            {
                Print("Inverted Head and Shoulders: Volume confirmed.");
                breakoutPrice = necklineHigh2;
                stopLoss = rightShoulder - StopLossPips * _Point;
                takeProfit = breakoutPrice + (necklineHigh1 - head);
                return true;
            }
             else { Print("Inverted Head and Shoulders: Volume not confirmed."); }
        }
         else { Print("Inverted Head and Shoulders: Preceding downtrend not confirmed."); }
    }
     else { Print("Inverted Head and Shoulders: Head and shoulders structure not found."); }

    return false;
}
//+------------------------------------------------------------------+
//| Head and Shoulders Detection                                     |
//+------------------------------------------------------------------+
bool IsHeadAndShoulders(const double &high[], const double &low[], const long &volume[],
                        double &breakdownPrice, double &stopLoss, double &takeProfit)
{
    Print("Analyzing for Head and Shoulders...");
    // Find 3 peaks (fractals)
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

    if(upper_fractal_count < 3 || lower_fractal_count < 2)
    {
        Print("Head and Shoulders: Not enough fractals.");
        return false;
    }

    // Identify Left Shoulder, Head, and Right Shoulder
    double leftShoulder = upper_fractals[2];
    int leftShoulderIndex = upper_fractal_indices[2];
    double head = upper_fractals[1];
    int headIndex = upper_fractal_indices[1];
    double rightShoulder = upper_fractals[0];
    int rightShoulderIndex = upper_fractal_indices[0];

    if(head > leftShoulder && head > rightShoulder)
    {
        Print("Head and Shoulders: Head and shoulders structure found.");
        // Symmetry Check
        double shoulderHeightDifference = MathAbs(leftShoulder - rightShoulder);
        if(shoulderHeightDifference > (head - MathMin(leftShoulder, rightShoulder)) * SymmetryTolerance)
        {
            Print("Head and Shoulders: Symmetry check failed (height).");
            return false;
        }

        int leftDuration = headIndex - leftShoulderIndex;
        int rightDuration = rightShoulderIndex - headIndex;
        double durationDifference = MathAbs(leftDuration - rightDuration);
        if(durationDifference > MathMin(leftDuration, rightDuration) * SymmetryTolerance)
        {
            Print("Head and Shoulders: Symmetry check failed (duration).");
            return false;
        }
        Print("Head and Shoulders: Symmetry confirmed.");

        // Identify Neckline
        double necklineLow1 = lower_fractals[1];
        int necklineLowIndex1 = lower_fractal_indices[1];
        double necklineLow2 = lower_fractals[0];
        int necklineLowIndex2 = lower_fractal_indices[0];

        // Neckline Slope Analysis
        double necklineSlope = (necklineLow1 - necklineLow2) / (necklineLowIndex1 - necklineLowIndex2);
        if(necklineSlope > 0)
        {
            Print("Head and Shoulders: Neckline slope is upward.");
            return false;
        }
        Print("Head and Shoulders: Neckline slope confirmed.");

        // Confirm preceding uptrend
        if(leftShoulderIndex + 20 >= LookbackBars)
        {
            Print("Head and Shoulders: Not enough historical data for preceding trend check.");
            return false;
        }
        double price_at_pattern_start = low[leftShoulderIndex];
        double price_before_pattern = low[leftShoulderIndex + 20]; // 20 bars before pattern
        if(price_at_pattern_start - price_before_pattern > scaled_UptrendMinHeight * _Point)
        {
            Print("Head and Shoulders: Preceding uptrend confirmed.");
            // Volume Confirmation
            long leftShoulderVolume = 0;
            for(int i = leftShoulderIndex; i > headIndex; i--)
                leftShoulderVolume += volume[i];

            long headVolume = 0;
            for(int i = headIndex; i > rightShoulderIndex; i--)
                headVolume += volume[i];

            long rightShoulderVolume = 0;
            for(int i = rightShoulderIndex; i > 1; i--)
                rightShoulderVolume += volume[i];

            if(leftShoulderVolume > headVolume && headVolume > rightShoulderVolume)
            {
                Print("Head and Shoulders: Volume confirmed.");
                breakdownPrice = necklineLow2;
                stopLoss = rightShoulder + StopLossPips * _Point;
                takeProfit = breakdownPrice - (head - necklineLow1);
                return true;
            }
             else { Print("Head and Shoulders: Volume not confirmed."); }
        }
         else { Print("Head and Shoulders: Preceding uptrend not confirmed."); }
    }
     else { Print("Head and Shoulders: Head and shoulders structure not found."); }

    return false;
}
//+------------------------------------------------------------------+
//| Bearish Flag Detection                                           |
//+------------------------------------------------------------------+
bool IsBearishFlag(const double &high[], const double &low[], const long &volume[],
                   double &breakdownPrice, double &stopLoss, double &takeProfit)
{
    Print("Analyzing for Bearish Flag...");
    // 1. Find the Flagpole
    int flagpoleStartIndex = -1;
    double flagpoleHigh = 0, flagpoleLow = 0;
    for(int i = 1; i < LookbackBars - 20; i++)
    {
        if(low[i] < low[i+1] && high[i] < high[i+1] && (high[i+10] - low[i]) > scaled_FlagpoleMinHeight * _Point)
        {
            // Confirm preceding downtrend
            if(i + 20 >= LookbackBars)
            {
                Print("Bearish Flag: Not enough historical data for preceding trend check.");
                continue;
            }
            double price_at_flagpole_start = high[i+10];
            double price_before_flagpole = high[i + 20]; // 10 bars before flagpole
            if(price_before_flagpole - price_at_flagpole_start > scaled_DowntrendMinHeight * _Point)
            {
                flagpoleStartIndex = i;
                flagpoleHigh = high[i+10];
                flagpoleLow = low[i];
                break;
            }
        }
    }

    if(flagpoleStartIndex == -1)
    {
        Print("Bearish Flag: Flagpole not found.");
        return false;
    }
    else
    {
        Print("Bearish Flag: Flagpole found at index ", flagpoleStartIndex);
    }

    // 2. Find the Flag
    int flagStartShift = flagpoleStartIndex - 10;
    double upper_fractals[], lower_fractals[];
    int upper_fractal_indices[], lower_fractal_indices[];
    int upper_fractal_count = 0, lower_fractal_count = 0;

    double upper_fractals_buffer[], lower_fractals_buffer[];
    CopyBuffer(fractals_handle, 0, flagStartShift, 20, upper_fractals_buffer);
    CopyBuffer(fractals_handle, 1, flagStartShift, 20, lower_fractals_buffer);

    for(int i = 0; i < 20; i++)
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

    if(upper_fractal_count < 2 || lower_fractal_count < 2)
    {
        Print("Bearish Flag: Not enough fractals.");
        return false;
    }

    // Check for upward sloping channel
    double upper_slope = (upper_fractals[0] - upper_fractals[1]) / (upper_fractal_indices[0] - upper_fractal_indices[1]);
    double lower_slope = (lower_fractals[0] - lower_fractals[1]) / (lower_fractal_indices[0] - lower_fractal_indices[1]);

    if(upper_slope > 0 && lower_slope > 0 && MathAbs(upper_slope - lower_slope) < 0.1)
    {
        Print("Bearish Flag: Upward sloping channel found.");
        // Check duration
        int duration = MathAbs(upper_fractal_indices[0] - lower_fractal_indices[0]);
        if(duration > FlagMaxDuration)
        {
            Print("Bearish Flag: Duration check failed.");
            return false;
        }
        Print("Bearish Flag: Duration confirmed.");

        // 3. Volume Confirmation
        long flagpoleVolume = 0;
        for(int i = flagpoleStartIndex; i > flagStartShift; i--)
            flagpoleVolume += volume[i];

        long flagVolume = 0;
        for(int i = flagStartShift; i > 1; i--)
            flagVolume += volume[i];

        if(flagpoleVolume > flagVolume)
        {
            Print("Bearish Flag: Volume confirmed.");
            // RSI Confirmation
            double rsi_buffer[];
            CopyBuffer(rsi_handle, 0, 0, RsiDivergenceLookback, rsi_buffer);
            ArraySetAsSeries(rsi_buffer, true);
            if(rsi_buffer[1] < 30) // Check if RSI was oversold
            {
                for(int i = 1; i < duration; i++)
                {
                    if(rsi_buffer[i] > 30) // Check if RSI has recovered
                    {
                        // MACD Confirmation
                        if(CheckMACDConfirmation(BEARISH_CROSS))
                        {
                            Print("Bearish Flag: MACD confirmed.");
                            breakdownPrice = lower_fractals[0];
                            stopLoss = upper_fractals[0] + StopLossPips * _Point;
                            takeProfit = breakdownPrice - (flagpoleHigh - flagpoleLow);
                            return true;
                        }
                    }
                }
            }
        }
         else { Print("Bearish Flag: Volume not confirmed."); }
    }
     else { Print("Bearish Flag: Upward sloping channel not found."); }

    return false;
}
//+------------------------------------------------------------------+
//| Bearish Pennant Detection                                        |
//+------------------------------------------------------------------+
bool IsBearishPennant(const double &high[], const double &low[], const long &volume[],
                      int &flagpoleStartIndex, double &flagpoleHigh, double &flagpoleLow, int &flagpoleBars,
                      double &pennantHigh, int &pennantHighIndex, double &breakdownPrice)
{
    Print("Analyzing for Bearish Pennant...");
    // 1. Find the Flagpole
    flagpoleStartIndex = -1;
    for(int i = 1; i < LookbackBars - 10; i++)
    {
        if(low[i] < low[i+1] && high[i] < high[i+1] && (high[i+10] - low[i]) > scaled_FlagpoleMinHeight * _Point)
        {
            flagpoleStartIndex = i;
            flagpoleHigh = high[i+10];
            flagpoleLow = low[i];
            flagpoleBars = 10;
            break;
        }
    }

    if(flagpoleStartIndex == -1)
    {
        Print("Bearish Pennant: Flagpole not found.");
        return false;
    }
    else
    {
        Print("Bearish Pennant: Flagpole found at index ", flagpoleStartIndex);
    }

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

    // Check for converging trendlines
    double upper_slope = (upFractal1 - upFractal2) / (upFractalIndex1 - upFractalIndex2);
    double lower_slope = (lowFractal1 - lowFractal2) / (lowFractalIndex1 - lowFractalIndex2);

    if(upper_slope < 0 && lower_slope > 0)
    {
        Print("Bearish Pennant: Converging trendlines found.");
        // 3. Volume Confirmation
        long flagpoleVolume = 0;
        for(int i = flagpoleStartIndex; i > pennantStartShift; i--)
            flagpoleVolume += volume[i];

        long pennantVolume = 0;
        for(int i = pennantStartShift; i > 1; i--)
            pennantVolume += volume[i];

        if(flagpoleVolume > pennantVolume)
        {
            Print("Bearish Pennant: Volume confirmed.");
            // Confirm preceding downtrend
            if(upFractalIndex2 + 20 >= LookbackBars)
            {
                Print("Bearish Pennant: Not enough historical data for preceding trend check.");
                return false;
            }
            int pennant_start_index = upFractalIndex2;
            double price_at_pennant_start = high[pennant_start_index];
            double price_before_pennant = high[pennant_start_index + 20]; // 20 bars before pennant
            if(price_before_pennant - price_at_pennant_start > DowntrendMinHeight * _Point)
            {
                Print("Bearish Pennant: Preceding downtrend confirmed.");
                // Check for MACD confirmation
                if(CheckMACDConfirmation(BEARISH_CROSS))
                {
                    Print("Bearish Pennant: MACD confirmed.");
                    Print("Bearish Pennant confirmed.");
                    pennantHigh = upFractal1;
                    pennantHighIndex = upFractalIndex1;
                    breakdownPrice = lowFractal1;
                    return true;
                }
                 else { Print("Bearish Pennant: MACD not confirmed."); }
            }
             else { Print("Bearish Pennant: Preceding downtrend not confirmed."); }
        }
         else { Print("Bearish Pennant: Volume not confirmed."); }
    }
     else { Print("Bearish Pennant: Converging trendlines not found."); }

    return false;
}
//+------------------------------------------------------------------+
//| Trading Functions                                                |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, double sl, string comment)
{
    if(PositionsTotal() > 0)
    {
        Print("ExecuteTrade: An order already exists.");
        return;
    }

    double lot_size = Lots / 3.0;
    double tp1, tp2, tp3;

    if(type == ORDER_TYPE_BUY)
    {
        tp1 = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + TP1_Pips * _Point;
        tp2 = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + TP2_Pips * _Point;
        tp3 = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + TP3_Pips * _Point;
        Print("Placing BUY order for ", _Symbol, " with Lot Size: ", lot_size, ", SL: ", sl, ", TP1: ", tp1, ", TP2: ", tp2, ", TP3: ", tp3);
        trade.Buy(lot_size, NULL, 0, sl, tp1, comment + " TP1");
        trade.Buy(lot_size, NULL, 0, sl, tp2, comment + " TP2");
        trade.Buy(lot_size, NULL, 0, sl, tp3, comment + " TP3");
    }
    else if(type == ORDER_TYPE_SELL)
    {
        tp1 = SymbolInfoDouble(_Symbol, SYMBOL_BID) - TP1_Pips * _Point;
        tp2 = SymbolInfoDouble(_Symbol, SYMBOL_BID) - TP2_Pips * _Point;
        tp3 = SymbolInfoDouble(_Symbol, SYMBOL_BID) - TP3_Pips * _Point;
        Print("Placing SELL order for ", _Symbol, " with Lot Size: ", lot_size, ", SL: ", sl, ", TP1: ", tp1, ", TP2: ", tp2, ", TP3: ", tp3);
        trade.Sell(lot_size, NULL, 0, sl, tp1, comment + " TP1");
        trade.Sell(lot_size, NULL, 0, sl, tp2, comment + " TP2");
        trade.Sell(lot_size, NULL, 0, sl, tp3, comment + " TP3");
    }
}
//+------------------------------------------------------------------+
//| Descending Broadening Wedge Detection                            |
//+------------------------------------------------------------------+
int IsDescendingBroadeningWedge(const double &high[], const double &low[],
                                 double &breakoutPrice, double &breakdownPrice, double &stopLoss, double &takeProfit)
{
    Print("Analyzing for Descending Broadening Wedge...");
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
    {
        Print("Descending Broadening Wedge: Not enough fractals.");
        return 0;
    }

    // Check for lower highs and lower lows
    if(upper_fractals[0] < upper_fractals[1] && upper_fractals[1] < upper_fractals[2] &&
       low[lower_fractal_indices[0]] < low[lower_fractal_indices[1]] && low[lower_fractal_indices[1]] < low[lower_fractal_indices[2]])
    {
        Print("Descending Broadening Wedge: Lower highs and lower lows found.");
        // Check for divergence
        double upper_slope = (upper_fractals[0] - upper_fractals[2]) / (upper_fractal_indices[0] - upper_fractal_indices[2]);
        double lower_slope = (lower_fractals[0] - lower_fractals[2]) / (lower_fractal_indices[0] - lower_fractal_indices[2]);

        if(upper_slope < 0 && lower_slope < 0 && lower_slope < upper_slope)
        {
            Print("Descending Broadening Wedge: Diverging trendlines found.");
            // Confirm preceding downtrend
            int wedge_start_index = lower_fractal_indices[2];
            if(wedge_start_index + 20 >= LookbackBars)
            {
                Print("Descending Broadening Wedge: Not enough historical data for preceding trend check.");
                return 0;
            }
            double price_at_wedge_start = high[wedge_start_index];
            double price_before_wedge = high[wedge_start_index + 20]; // 20 bars before wedge
            if(price_before_wedge - price_at_wedge_start > scaled_DowntrendMinHeight * _Point)
            {
                Print("Descending Broadening Wedge: Preceding downtrend confirmed.");
                // Check for RSI divergence
                if(CheckRSIDivergence(low, lower_fractal_indices[0], lower_fractal_indices[2], BULLISH_DIVERGENCE))
                {
                    Print("Descending Broadening Wedge: RSI divergence confirmed.");
                    Print("Descending Broadening Wedge confirmed.");
                    breakoutPrice = upper_fractals[0];
                    breakdownPrice = lower_fractals[0];
                    stopLoss = lower_fractals[0] - StopLossPips * _Point;
                    takeProfit = high[upper_fractal_indices[2]]; // Method 1: Highest point of the wedge
                    return 1; // Bullish breakout
                }
                else
                {
                    Print("Descending Broadening Wedge: RSI divergence not confirmed.");
                    return 2; // Bearish breakout
                }
            }
             else { Print("Descending Broadening Wedge: Preceding downtrend not confirmed."); }
        }
         else { Print("Descending Broadening Wedge: Diverging trendlines not found."); }
    }
     else { Print("Descending Broadening Wedge: Lower highs and lower lows not found."); }

    return 0;
}
//+------------------------------------------------------------------+
//| Ascending Broadening Wedge Detection                             |
//+------------------------------------------------------------------+
int IsAscendingBroadeningWedge(const double &high[], const double &low[],
                                double &breakdownPrice, double &breakoutPrice, double &stopLoss, double &takeProfit)
{
    Print("Analyzing for Ascending Broadening Wedge...");
    // Find at least 3 higher highs and 3 higher lows
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
    {
        Print("Ascending Broadening Wedge: Not enough fractals.");
        return 0;
    }

    // Check for higher highs and higher lows
    if(upper_fractals[0] > upper_fractals[1] && upper_fractals[1] > upper_fractals[2] &&
       low[lower_fractal_indices[0]] > low[lower_fractal_indices[1]] && low[lower_fractal_indices[1]] > low[lower_fractal_indices[2]])
    {
        Print("Ascending Broadening Wedge: Higher highs and higher lows found.");
        // Check for divergence
        double upper_slope = (upper_fractals[0] - upper_fractals[2]) / (upper_fractal_indices[0] - upper_fractal_indices[2]);
        double lower_slope = (lower_fractals[0] - lower_fractals[2]) / (lower_fractal_indices[0] - lower_fractal_indices[2]);

        if(upper_slope > 0 && lower_slope > 0 && upper_slope > lower_slope)
        {
            Print("Ascending Broadening Wedge: Diverging trendlines found.");
            // Confirm preceding uptrend
            int wedge_start_index = upper_fractal_indices[2];
            if(wedge_start_index + 20 >= LookbackBars)
            {
                Print("Ascending Broadening Wedge: Not enough historical data for preceding trend check.");
                return 0;
            }
            double price_at_wedge_start = low[wedge_start_index];
            double price_before_wedge = low[wedge_start_index + 20]; // 20 bars before wedge
            if(price_at_wedge_start - price_before_wedge > scaled_UptrendMinHeight * _Point)
            {
                Print("Ascending Broadening Wedge: Preceding uptrend confirmed.");
                // Check for RSI divergence
                if(CheckRSIDivergence(high, upper_fractal_indices[0], upper_fractal_indices[2], BEARISH_DIVERGENCE))
                {
                    Print("Ascending Broadening Wedge: RSI divergence confirmed.");
                    Print("Ascending Broadening Wedge confirmed.");
                    breakdownPrice = lower_fractals[0];
                    breakoutPrice = upper_fractals[0];
                    stopLoss = upper_fractals[0] + StopLossPips * _Point;
                    takeProfit = low[lower_fractal_indices[2]]; // Method 1: Lowest point of the wedge
                    return 1; // Bearish breakout
                }
                else
                {
                    Print("Ascending Broadening Wedge: RSI divergence not confirmed.");
                    return 2; // Bullish breakout
                }
            }
             else { Print("Ascending Broadening Wedge: Preceding uptrend not confirmed."); }
        }
         else { Print("Ascending Broadening Wedge: Diverging trendlines not found."); }
    }
     else { Print("Ascending Broadening Wedge: Higher highs and higher lows not found."); }

    return 0;
}
//+------------------------------------------------------------------+
//| RSI Divergence Check                                             |
//+------------------------------------------------------------------+
enum ENUM_DIVERGENCE_TYPE
{
    BULLISH_DIVERGENCE,
    BEARISH_DIVERGENCE
};

bool CheckRSIDivergence(const double &price[], const int index1, const int index2, ENUM_DIVERGENCE_TYPE type)
{
    double rsi_buffer[];
    CopyBuffer(rsi_handle, 0, 0, RsiDivergenceLookback, rsi_buffer);
    ArraySetAsSeries(rsi_buffer, true);

    double rsi1 = rsi_buffer[index1];
    double rsi2 = rsi_buffer[index2];

    if(type == BEARISH_DIVERGENCE)
    {
        if(price[index1] > price[index2] && rsi1 < rsi2)
            return true;
    }
    else if(type == BULLISH_DIVERGENCE)
    {
        if(price[index1] < price[index2] && rsi1 > rsi2)
            return true;
    }

    return false;
}
//+------------------------------------------------------------------+
//| MACD Confirmation Check                                          |
//+------------------------------------------------------------------+
enum ENUM_MACD_SIGNAL_TYPE
{
    BULLISH_CROSS,
    BEARISH_CROSS
};

bool CheckMACDConfirmation(ENUM_MACD_SIGNAL_TYPE type)
{
    double macd_main_buffer[], macd_signal_buffer[];
    CopyBuffer(macd_handle, 0, 0, 3, macd_main_buffer);
    CopyBuffer(macd_handle, 1, 0, 3, macd_signal_buffer);
    ArraySetAsSeries(macd_main_buffer, true);
    ArraySetAsSeries(macd_signal_buffer, true);

    if(type == BEARISH_CROSS)
    {
        // Check for bearish cross
        if(macd_main_buffer[1] > macd_signal_buffer[1] && macd_main_buffer[2] < macd_signal_buffer[2])
            return true;
    }
    else if(type == BULLISH_CROSS)
    {
        // Check for bullish cross
        if(macd_main_buffer[1] < macd_signal_buffer[1] && macd_main_buffer[2] > macd_signal_buffer[2])
            return true;
    }

    return false;
}
//+------------------------------------------------------------------+
//| Long-Term Trend Check                                            |
//+------------------------------------------------------------------+
bool CheckLongTermTrend(const double &close[])
{
    double ma_buffer[];
    CopyBuffer(ma_handle, 0, 0, 1, ma_buffer);

    if(close[1] > ma_buffer[0])
        return true;

    return false;
}
//+------------------------------------------------------------------+
//| Trailing Stop Management                                         |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
    if(!EnableTrailingStop)
        return;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
            {
                if(PositionGetDouble(POSITION_TP) > 0) // TP is set
                {
                    if(PositionGetDouble(POSITION_PROFIT) > 0) // Position is in profit
                    {
                        string comment = PositionGetString(POSITION_COMMENT);
                        if(StringFind(comment, "TP2") != -1)
                        {
                            double tp1_price = 0;
                            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                                tp1_price = PositionGetDouble(POSITION_PRICE_OPEN) + TP1_Pips * _Point;
                            else
                                tp1_price = PositionGetDouble(POSITION_PRICE_OPEN) - TP1_Pips * _Point;

                            if(PositionGetDouble(POSITION_SL) < tp1_price)
                                trade.PositionModify(ticket, tp1_price + TrailingStopPlusPips * _Point, PositionGetDouble(POSITION_TP));
                        }
                        else if(StringFind(comment, "TP3") != -1)
                        {
                            double tp2_price = 0;
                            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                                tp2_price = PositionGetDouble(POSITION_PRICE_OPEN) + TP2_Pips * _Point;
                            else
                                tp2_price = PositionGetDouble(POSITION_PRICE_OPEN) - TP2_Pips * _Point;

                            if(PositionGetDouble(POSITION_SL) < tp2_price)
                                trade.PositionModify(ticket, tp2_price + TrailingStopPlusPips * _Point, PositionGetDouble(POSITION_TP));
                        }
                    }
                }
            }
        }
    }

    if(PatternToTrade == SYMMETRICAL_TRIANGLE || PatternToTrade == ALL)
    {
        Print("OnTick: Analyzing for Symmetrical Triangle...");
        double breakoutPrice = 0, breakdownPrice = 0, stopLoss = 0, takeProfit = 0;
        int breakout_type = IsSymmetricalTriangle(high, low, volume, breakoutPrice, breakdownPrice, stopLoss, takeProfit);

        if(breakout_type == 3) // Bullish breakout with prior uptrend
        {
            if(close[1] > breakoutPrice)
            {
                ExecuteTrade(ORDER_TYPE_BUY, stopLoss, "Symmetrical Triangle (Continuation)");
            }
        }
        else if(breakout_type == 4) // Bearish breakdown with prior downtrend
        {
            if(close[1] < breakdownPrice)
            {
                ExecuteTrade(ORDER_TYPE_SELL, stopLoss, "Symmetrical Triangle (Continuation)");
            }
        }
        else if(breakout_type == 1) // Bullish breakout
        {
            if(close[1] > breakoutPrice)
            {
                ExecuteTrade(ORDER_TYPE_BUY, stopLoss, "Symmetrical Triangle");
            }
        }
        else if(breakout_type == 2) // Bearish breakout
        {
            if(close[1] < breakdownPrice)
            {
                ExecuteTrade(ORDER_TYPE_SELL, stopLoss, "Symmetrical Triangle");
            }
        }
    }

    if(PatternToTrade == BROADENING_TRIANGLE || PatternToTrade == ALL)
    {
        Print("OnTick: Analyzing for Broadening Triangle...");
        double breakoutPrice = 0, breakdownPrice = 0, patternHeight = 0;
        int breakout_type = IsBroadeningTriangle(high, low, volume, breakoutPrice, breakdownPrice, patternHeight);

        if(breakout_type == 3) // Bearish Reversal
        {
            if(close[1] < breakdownPrice)
            {
                double sl = breakoutPrice;
                ExecuteTrade(ORDER_TYPE_SELL, sl, "Broadening Triangle (Reversal)");
            }
        }
        else if(breakout_type == 4) // Bullish Reversal
        {
            if(close[1] > breakoutPrice)
            {
                double sl = breakdownPrice;
                ExecuteTrade(ORDER_TYPE_BUY, sl, "Broadening Triangle (Reversal)");
            }
        }
        else if(breakout_type == 1) // Bullish breakout
        {
            if(close[1] > breakoutPrice)
            {
                double sl = breakdownPrice;
                ExecuteTrade(ORDER_TYPE_BUY, sl, "Broadening Triangle");
            }
        }
        else if(breakout_type == 2) // Bearish breakout
        {
            if(close[1] < breakdownPrice)
            {
                double sl = breakoutPrice;
                ExecuteTrade(ORDER_TYPE_SELL, sl, "Broadening Triangle");
            }
        }
    }

    if(PatternToTrade == ASCENDING_TRIANGLE || PatternToTrade == ALL)
    {
        Print("OnTick: Analyzing for Ascending Triangle...");
        double breakoutPrice = 0, stopLoss = 0, takeProfit = 0;
        if(IsAscendingTriangle(high, low, volume, breakoutPrice, stopLoss, takeProfit))
        {
            if(close[1] > breakoutPrice)
            {
                ExecuteTrade(ORDER_TYPE_BUY, stopLoss, "Ascending Triangle");
            }
        }
    }

    if(PatternToTrade == DESCENDING_TRIANGLE || PatternToTrade == ALL)
    {
        Print("OnTick: Analyzing for Descending Triangle...");
        double breakdownPrice = 0, stopLoss = 0, takeProfit = 0;
        if(IsDescendingTriangle(high, low, volume, breakdownPrice, stopLoss, takeProfit))
        {
            if(close[1] < breakdownPrice)
            {
                ExecuteTrade(ORDER_TYPE_SELL, stopLoss, "Descending Triangle");
            }
        }
    }

    if(PatternToTrade == DOUBLE_TOP || PatternToTrade == ALL)
    {
        Print("OnTick: Analyzing for Double Top...");
        double breakdownPrice = 0, stopLoss = 0, takeProfit = 0;
        if(IsDoubleTop(high, low, volume, breakdownPrice, stopLoss, takeProfit))
        {
            if(close[1] < breakdownPrice)
            {
                ExecuteTrade(ORDER_TYPE_SELL, stopLoss, "Double Top");
            }
        }
    }

    if(PatternToTrade == DOUBLE_BOTTOM || PatternToTrade == ALL)
    {
        Print("OnTick: Analyzing for Double Bottom...");
        double breakoutPrice = 0, stopLoss = 0, takeProfit = 0;
        if(IsDoubleBottom(high, low, volume, breakoutPrice, stopLoss, takeProfit))
        {
            if(close[1] > breakoutPrice)
            {
                ExecuteTrade(ORDER_TYPE_BUY, stopLoss, "Double Bottom");
            }
        }
    }
}
//+------------------------------------------------------------------+
//| Bullish Rectangle Detection                                      |
//+------------------------------------------------------------------+
bool IsBullishRectangle(const double &high[], const double &low[],
                        double &breakoutPrice, double &stopLoss, double &takeProfit)
{
    Print("Analyzing for Bullish Rectangle...");
    // Find at least 2 comparable highs and 2 comparable lows
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

    if(upper_fractal_count < 2 || lower_fractal_count < 2)
    {
        Print("Bullish Rectangle: Not enough fractals.");
        return false;
    }

    // Check for horizontal trendlines
    double upper_level = (upper_fractals[0] + upper_fractals[1]) / 2;
    double lower_level = (lower_fractals[0] + lower_fractals[1]) / 2;
    double tolerance = 10 * _Point;

    if(MathAbs(upper_fractals[0] - upper_level) < tolerance && MathAbs(upper_fractals[1] - upper_level) < tolerance &&
       MathAbs(lower_fractals[0] - lower_level) < tolerance && MathAbs(lower_fractals[1] - lower_level) < tolerance)
    {
        Print("Bullish Rectangle: Horizontal trendlines found.");
        // Check duration
        int duration = MathAbs(upper_fractal_indices[0] - lower_fractal_indices[0]);
        if(duration >= RectangleMinDuration && duration <= RectangleMaxDuration)
        {
            Print("Bullish Rectangle: Duration confirmed.");
            // Confirm preceding uptrend
            int rectangle_start_index = MathMax(upper_fractal_indices[1], lower_fractal_indices[1]);
            if(rectangle_start_index + 20 >= LookbackBars)
            {
                Print("Bullish Rectangle: Not enough historical data for preceding trend check.");
                return false;
            }
            double price_at_rectangle_start = low[rectangle_start_index];
            double price_before_rectangle = low[rectangle_start_index + 20]; // 20 bars before rectangle
            if(price_at_rectangle_start - price_before_rectangle > scaled_UptrendMinHeight * _Point)
            {
                Print("Bullish Rectangle: Preceding uptrend confirmed.");
                if(CheckMACDConfirmation(BULLISH_CROSS))
                {
                    Print("Bullish Rectangle: MACD confirmed.");
                    Print("Bullish Rectangle confirmed.");
                    breakoutPrice = upper_level;
                    stopLoss = lower_level - StopLossPips * _Point;
                    takeProfit = breakoutPrice + (upper_level - lower_level);
                    return true;
                }
                 else { Print("Bullish Rectangle: MACD not confirmed."); }
            }
             else { Print("Bullish Rectangle: Preceding uptrend not confirmed."); }
        }
         else { Print("Bullish Rectangle: Duration not confirmed."); }
    }
     else { Print("Bullish Rectangle: Horizontal trendlines not found."); }

    return false;
}
//+------------------------------------------------------------------+
//| Bearish Rectangle Detection                                      |
//+------------------------------------------------------------------+
bool IsBearishRectangle(const double &high[], const double &low[],
                        double &breakdownPrice, double &stopLoss, double &takeProfit)
{
    Print("Analyzing for Bearish Rectangle...");
    // Find at least 2 comparable highs and 2 comparable lows
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

    if(upper_fractal_count < 2 || lower_fractal_count < 2)
    {
        Print("Bearish Rectangle: Not enough fractals.");
        return false;
    }

    // Check for horizontal trendlines
    double upper_level = (upper_fractals[0] + upper_fractals[1]) / 2;
    double lower_level = (lower_fractals[0] + lower_fractals[1]) / 2;
    double tolerance = 10 * _Point;

    if(MathAbs(upper_fractals[0] - upper_level) < tolerance && MathAbs(upper_fractals[1] - upper_level) < tolerance &&
       MathAbs(lower_fractals[0] - lower_level) < tolerance && MathAbs(lower_fractals[1] - lower_level) < tolerance)
    {
        Print("Bearish Rectangle: Horizontal trendlines found.");
        // Check duration
        int duration = MathAbs(upper_fractal_indices[0] - lower_fractal_indices[0]);
        if(duration >= RectangleMinDuration && duration <= RectangleMaxDuration)
        {
            Print("Bearish Rectangle: Duration confirmed.");
            // Confirm preceding downtrend
            int rectangle_start_index = MathMax(upper_fractal_indices[1], lower_fractal_indices[1]);
            if(rectangle_start_index + 20 >= LookbackBars)
            {
                Print("Bearish Rectangle: Not enough historical data for preceding trend check.");
                return false;
            }
            double price_at_rectangle_start = high[rectangle_start_index];
            double price_before_rectangle = high[rectangle_start_index + 20]; // 20 bars before rectangle
            if(price_before_rectangle - price_at_rectangle_start > scaled_DowntrendMinHeight * _Point)
            {
                Print("Bearish Rectangle: Preceding downtrend confirmed.");
                if(CheckMACDConfirmation(BEARISH_CROSS))
                {
                    Print("Bearish Rectangle: MACD confirmed.");
                    Print("Bearish Rectangle confirmed.");
                    breakdownPrice = lower_level;
                    stopLoss = upper_level + StopLossPips * _Point;
                    takeProfit = breakdownPrice - (upper_level - lower_level);
                    return true;
                }
                 else { Print("Bearish Rectangle: MACD not confirmed."); }
            }
             else { Print("Bearish Rectangle: Preceding downtrend not confirmed."); }
        }
         else { Print("Bearish Rectangle: Duration not confirmed."); }
    }
     else { Print("Bearish Rectangle: Horizontal trendlines not found."); }

    return false;
}
//+------------------------------------------------------------------+
//| Bullish Flag Detection                                           |
//+------------------------------------------------------------------+
bool IsBullishFlag(const double &high[], const double &low[], const long &volume[],
                   double &breakoutPrice, double &stopLoss, double &takeProfit)
{
    Print("Analyzing for Bullish Flag...");
    // 1. Find the Flagpole
    int flagpoleStartIndex = -1;
    double flagpoleHigh = 0, flagpoleLow = 0;
    for(int i = 1; i < LookbackBars - 20; i++)
    {
        if(high[i] > high[i+1] && low[i] > low[i+1] && (high[i] - low[i+10]) > scaled_FlagpoleMinHeight * _Point)
        {
            // Confirm preceding uptrend
            if(i + 20 >= LookbackBars)
            {
                Print("Bullish Flag: Not enough historical data for preceding trend check.");
                continue;
            }
            double price_at_flagpole_start = low[i+10];
            double price_before_flagpole = low[i + 20]; // 10 bars before flagpole
            if(price_at_flagpole_start - price_before_flagpole > scaled_UptrendMinHeight * _Point)
            {
                flagpoleStartIndex = i;
                flagpoleHigh = high[i];
                flagpoleLow = low[i+10];
                break;
            }
        }
    }

    if(flagpoleStartIndex == -1)
    {
        Print("Bullish Flag: Flagpole not found.");
        return false;
    }
    else
    {
        Print("Bullish Flag: Flagpole found at index ", flagpoleStartIndex);
    }

    // 2. Find the Flag
    int flagStartShift = flagpoleStartIndex - 10;
    double upper_fractals[], lower_fractals[];
    int upper_fractal_indices[], lower_fractal_indices[];
    int upper_fractal_count = 0, lower_fractal_count = 0;

    double upper_fractals_buffer[], lower_fractals_buffer[];
    CopyBuffer(fractals_handle, 0, flagStartShift, 20, upper_fractals_buffer);
    CopyBuffer(fractals_handle, 1, flagStartShift, 20, lower_fractals_buffer);

    for(int i = 0; i < 20; i++)
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

    if(upper_fractal_count < 2 || lower_fractal_count < 2)
    {
        Print("Bullish Flag: Not enough fractals.");
        return false;
    }

    // Check for downward sloping channel
    double upper_slope = (upper_fractals[0] - upper_fractals[1]) / (upper_fractal_indices[0] - upper_fractal_indices[1]);
    double lower_slope = (lower_fractals[0] - lower_fractals[1]) / (lower_fractal_indices[0] - lower_fractal_indices[1]);

    if(upper_slope < 0 && lower_slope < 0 && MathAbs(upper_slope - lower_slope) < 0.1)
    {
        Print("Bullish Flag: Downward sloping channel found.");
        // Check duration
        int duration = MathAbs(upper_fractal_indices[0] - lower_fractal_indices[0]);
        if(duration > FlagMaxDuration)
        {
            Print("Bullish Flag: Duration check failed.");
            return false;
        }
        Print("Bullish Flag: Duration confirmed.");

        // 3. Volume Confirmation
        long flagpoleVolume = 0;
        for(int i = flagpoleStartIndex; i > flagStartShift; i--)
            flagpoleVolume += volume[i];

        long flagVolume = 0;
        for(int i = flagStartShift; i > 1; i--)
            flagVolume += volume[i];

        if(flagpoleVolume > flagVolume)
        {
            Print("Bullish Flag: Volume confirmed.");
            // RSI Confirmation
            double rsi_buffer[];
            CopyBuffer(rsi_handle, 0, 0, RsiDivergenceLookback, rsi_buffer);
            ArraySetAsSeries(rsi_buffer, true);
            if(rsi_buffer[1] > 70) // Check if RSI was overbought
            {
                for(int i = 1; i < duration; i++)
                {
                    if(rsi_buffer[i] < 70) // Check if RSI has cooled off
                    {
                        // MACD Confirmation
                        if(CheckMACDConfirmation(BULLISH_CROSS))
                        {
                            Print("Bullish Flag: MACD confirmed.");
                            breakoutPrice = upper_fractals[0];
                            stopLoss = lower_fractals[0] - StopLossPips * _Point;
                            takeProfit = breakoutPrice + (flagpoleHigh - flagpoleLow);
                            return true;
                        }
                    }
                }
            }
        }
         else { Print("Bullish Flag: Volume not confirmed."); }
    }
     else { Print("Bullish Flag: Downward sloping channel not found."); }

    return false;
}
//+------------------------------------------------------------------+
//| Broadening Triangle Detection                                    |
//+------------------------------------------------------------------+
int IsBroadeningTriangle(const double &high[], const double &low[], const long &volume[],
                         double &breakoutPrice, double &breakdownPrice, double &patternHeight)
{
    Print("Analyzing for Broadening Triangle...");
    // Find at least 3 higher highs and 3 lower lows
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
    {
        Print("Broadening Triangle: Not enough fractals.");
        return 0;
    }

    // Check for higher highs and lower lows
    if(upper_fractals[0] > upper_fractals[1] && upper_fractals[1] > upper_fractals[2] &&
       low[lower_fractal_indices[0]] < low[lower_fractal_indices[1]] && low[lower_fractal_indices[1]] < low[lower_fractal_indices[2]])
    {
        Print("Broadening Triangle: Higher highs and lower lows found.");
        // Check for diverging trendlines
        double upper_slope = (upper_fractals[0] - upper_fractals[2]) / (upper_fractal_indices[0] - upper_fractal_indices[2]);
        double lower_slope = (low[lower_fractal_indices[0]] - low[lower_fractal_indices[2]]) / (lower_fractal_indices[0] - lower_fractal_indices[2]);

        if(upper_slope > 0 && lower_slope < 0)
        {
            Print("Broadening Triangle: Diverging trendlines found.");

            // Prior Trend Analysis
            int pattern_start_index = MathMax(upper_fractal_indices[2], lower_fractal_indices[2]);
            if(pattern_start_index + 20 >= LookbackBars)
            {
                Print("Broadening Triangle: Not enough historical data for preceding trend check.");
                return 0;
            }
            double price_at_pattern_start_high = high[pattern_start_index];
            double price_before_pattern_high = high[pattern_start_index + 20];
            double price_at_pattern_start_low = low[pattern_start_index];
            double price_before_pattern_low = low[pattern_start_index + 20];

            bool is_uptrend = price_at_pattern_start_low - price_before_pattern_low > scaled_UptrendMinHeight * _Point;
            bool is_downtrend = price_before_pattern_high - price_at_pattern_start_high > scaled_DowntrendMinHeight * _Point;

            // Volume Confirmation
            long first_half_volume = 0;
            long second_half_volume = 0;
            int pattern_start_index = MathMax(upper_fractal_indices[2], lower_fractal_indices[2]);
            int pattern_end_index = MathMin(upper_fractal_indices[0], lower_fractal_indices[0]);
            int pattern_duration = pattern_start_index - pattern_end_index;
            int midpoint = pattern_end_index + pattern_duration / 2;

            for(int i = pattern_start_index; i > midpoint; i--)
                first_half_volume += volume[i];
            for(int i = midpoint; i > pattern_end_index; i--)
                second_half_volume += volume[i];

            if(second_half_volume > first_half_volume)
            {
                Print("Broadening Triangle: Increasing volume confirmed.");
                patternHeight = upper_fractals[2] - low[lower_fractal_indices[2]];
                breakoutPrice = upper_fractals[0];
                breakdownPrice = low[lower_fractal_indices[0]];

                if(is_uptrend && low[1] < breakdownPrice) return 3; // Bearish Reversal
                if(is_downtrend && high[1] > breakoutPrice) return 4; // Bullish Reversal

                if(high[1] > breakoutPrice) return 1; // Bullish Breakout
                if(low[1] < breakdownPrice) return 2; // Bearish Breakdown
            }
            else { Print("Broadening Triangle: Increasing volume not confirmed."); }
        }
        else { Print("Broadening Triangle: Diverging trendlines not found."); }
    }
    else { Print("Broadening Triangle: Higher highs and lower lows not found."); }

    return 0;
}
//+------------------------------------------------------------------+
//| Ascending Triangle Detection                                     |
//+------------------------------------------------------------------+
bool IsAscendingTriangle(const double &high[], const double &low[], const long &volume[],
                         double &breakoutPrice, double &stopLoss, double &takeProfit)
{
    Print("Analyzing for Ascending Triangle...");
    // Find at least 2 higher lows and 2 flat highs
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

    if(upper_fractal_count < 2 || lower_fractal_count < 2)
    {
        Print("Ascending Triangle: Not enough fractals.");
        return false;
    }

    // Check for flat resistance and higher lows
    double resistance_level = (upper_fractals[0] + upper_fractals[1]) / 2;
    double tolerance = 10 * _Point;
    if(MathAbs(upper_fractals[0] - resistance_level) < tolerance && MathAbs(upper_fractals[1] - resistance_level) < tolerance &&
       low[lower_fractal_indices[0]] > low[lower_fractal_indices[1]])
    {
        Print("Ascending Triangle: Flat resistance and higher lows found.");

        // Prior Trend Confirmation
        int pattern_start_index = MathMax(upper_fractal_indices[1], lower_fractal_indices[1]);
        if(pattern_start_index + 20 >= LookbackBars)
        {
            Print("Ascending Triangle: Not enough historical data for preceding trend check.");
            return false;
        }
        double price_at_pattern_start = low[pattern_start_index];
        double price_before_pattern = low[pattern_start_index + 20];
        if(price_at_pattern_start - price_before_pattern > scaled_UptrendMinHeight * _Point)
        {
            Print("Ascending Triangle: Preceding uptrend confirmed.");

            // Volume Confirmation
            long pattern_volume = 0;
            for(int i = pattern_start_index; i > 1; i--)
                pattern_volume += volume[i];

            if(volume[1] < (pattern_volume / (pattern_start_index - 1)))
            {
                Print("Ascending Triangle: Diminishing volume confirmed.");
                breakoutPrice = resistance_level;
                stopLoss = low[lower_fractal_indices[0]] - StopLossPips * _Point;
                takeProfit = breakoutPrice + (resistance_level - low[lower_fractal_indices[1]]);
                return true;
            }
            else { Print("Ascending Triangle: Diminishing volume not confirmed."); }
        }
        else { Print("Ascending Triangle: Preceding uptrend not confirmed."); }
    }
    else { Print("Ascending Triangle: Flat resistance and higher lows not found."); }

    return false;
}
//+------------------------------------------------------------------+
//| Symmetrical Triangle Detection                                   |
//+------------------------------------------------------------------+
int IsSymmetricalTriangle(const double &high[], const double &low[], const long &volume[],
                          double &breakoutPrice, double &breakdownPrice, double &stopLoss, double &takeProfit)
{
    Print("Analyzing for Symmetrical Triangle...");
    // Find at least 2 lower highs and 2 higher lows
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

    if(upper_fractal_count < 2 || lower_fractal_count < 2)
    {
        Print("Symmetrical Triangle: Not enough fractals.");
        return 0;
    }

    // Check for lower highs and higher lows
    if(upper_fractals[0] < upper_fractals[1] && low[lower_fractal_indices[0]] > low[lower_fractal_indices[1]])
    {
        Print("Symmetrical Triangle: Lower highs and higher lows found.");
        // Check for converging trendlines
        double upper_slope = (upper_fractals[0] - upper_fractals[1]) / (upper_fractal_indices[0] - upper_fractal_indices[1]);
        double lower_slope = (low[lower_fractal_indices[0]] - low[lower_fractal_indices[1]]) / (lower_fractal_indices[0] - lower_fractal_indices[1]);

        if(upper_slope < 0 && lower_slope > 0)
        {
            Print("Symmetrical Triangle: Converging trendlines found.");

            // Apex Analysis
            double apex_x = (low[lower_fractal_indices[1]] - upper_fractals[1] + upper_slope * upper_fractal_indices[1] - lower_slope * lower_fractal_indices[1]) / (upper_slope - lower_slope);
            double pattern_length = apex_x - upper_fractal_indices[1];
            double breakout_point = upper_fractal_indices[0];
            if((breakout_point - upper_fractal_indices[1]) / pattern_length > ApexRatio)
            {
                Print("Symmetrical Triangle: Breakout occurred too close to the apex.");
                return 0;
            }

            // Prior Trend Analysis
            double price_at_triangle_start = low[lower_fractal_indices[1]];
            double price_before_triangle = low[lower_fractal_indices[1] + 20];
            bool is_uptrend = price_at_triangle_start - price_before_triangle > scaled_UptrendMinHeight * _Point;

            // Volume Confirmation
            long triangleVolume = 0;
            for(int i = upper_fractal_indices[1]; i > 1; i--)
                triangleVolume += volume[i];

            if(volume[1] > triangleVolume / (upper_fractal_indices[1] - 1))
            {
                Print("Symmetrical Triangle: Volume confirmed.");
                breakoutPrice = upper_fractals[0];
                breakdownPrice = low[lower_fractal_indices[0]];
                stopLoss = low[lower_fractal_indices[0]] - StopLossPips * _Point;
                takeProfit = breakoutPrice + (upper_fractals[1] - low[lower_fractal_indices[1]]);

                if(is_uptrend && high[1] > breakoutPrice)
                    return 3; // Bullish breakout with prior uptrend
                if(!is_uptrend && low[1] < breakdownPrice)
                    return 4; // Bearish breakdown with prior downtrend
                if(high[1] > breakoutPrice)
                    return 1; // Bullish breakout
                if(low[1] < breakdownPrice)
                    return 2; // Bearish breakout
            }
             else { Print("Symmetrical Triangle: Volume not confirmed."); }
        }
         else { Print("Symmetrical Triangle: Converging trendlines not found."); }
    }
     else { Print("Symmetrical Triangle: Lower highs and higher lows not found."); }

    return 0;
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // We use a static variable to ensure the expert only runs once per bar.
    static datetime lastBarTime = 0;
    if(lastBarTime == iTime(_Symbol, _Period, 0))
        return;
    lastBarTime = iTime(_Symbol, _Period, 0);

    ManageTrailingStop();
    // Get historical data
    double high[], low[], close[];
    datetime time[];
    long volume[];
    if(!GetHistory(LookbackBars, high, low, close, time, volume))
        return;

    // --- Pattern Detection ---
    if(PatternToTrade == BULLISH_PENNANT || PatternToTrade == ALL)
    {
        Print("OnTick: Analyzing for Bullish Pennant...");
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
                ExecuteTrade(ORDER_TYPE_BUY, sl, "Bullish Pennant");
            }
        }
    }

    if(PatternToTrade == BEARISH_PENNANT || PatternToTrade == ALL)
    {
        Print("OnTick: Analyzing for Bearish Pennant...");
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
                ExecuteTrade(ORDER_TYPE_SELL, sl, "Bearish Pennant");
            }
        }
    }

    if(PatternToTrade == DESCENDING_BROADENING_WEDGE || PatternToTrade == ALL)
    {
        Print("OnTick: Analyzing for Descending Broadening Wedge...");
        double breakoutPrice = 0, breakdownPrice = 0, stopLoss = 0, takeProfit = 0;
        int breakout_type = IsDescendingBroadeningWedge(high, low, breakoutPrice, breakdownPrice, stopLoss, takeProfit);

        if(breakout_type == 1) // Bullish breakout
        {
            if(close[1] > breakoutPrice)
            {
                ExecuteTrade(ORDER_TYPE_BUY, stopLoss, "Descending Broadening Wedge");
            }
        }
        else if(breakout_type == 2 && TradeFailedWedgeBreakouts) // Bearish breakout
        {
            if(close[1] < breakdownPrice)
            {
                ExecuteTrade(ORDER_TYPE_SELL, stopLoss, "Descending Wedge Failed Breakout");
            }
        }
    }

    if(PatternToTrade == ASCENDING_BROADENING_WEDGE || PatternToTrade == ALL)
    {
        Print("OnTick: Analyzing for Ascending Broadening Wedge...");
        double breakdownPrice = 0, breakoutPrice = 0, stopLoss = 0, takeProfit = 0;
        int breakout_type = IsAscendingBroadeningWedge(high, low, breakdownPrice, breakoutPrice, stopLoss, takeProfit);

        if(breakout_type == 1) // Bearish breakout
        {
            if(close[1] < breakdownPrice)
            {
                ExecuteTrade(ORDER_TYPE_SELL, stopLoss, "Ascending Broadening Wedge");
            }
        }
        else if(breakout_type == 2 && TradeFailedWedgeBreakouts) // Bullish breakout
        {
            if(close[1] > breakoutPrice)
            {
                ExecuteTrade(ORDER_TYPE_BUY, stopLoss, "Ascending Wedge Failed Breakout");
            }
        }
    }

    if(PatternToTrade == BULLISH_RECTANGLE || PatternToTrade == ALL)
    {
        Print("OnTick: Analyzing for Bullish Rectangle...");
        double breakoutPrice = 0, stopLoss = 0, takeProfit = 0;
        if(IsBullishRectangle(high, low, breakoutPrice, stopLoss, takeProfit))
        {
            if(close[1] > breakoutPrice)
            {
                ExecuteTrade(ORDER_TYPE_BUY, stopLoss, "Bullish Rectangle");
            }
        }
    }

    if(PatternToTrade == BEARISH_RECTANGLE || PatternToTrade == ALL)
    {
        Print("OnTick: Analyzing for Bearish Rectangle...");
        double breakdownPrice = 0, stopLoss = 0, takeProfit = 0;
        if(IsBearishRectangle(high, low, breakdownPrice, stopLoss, takeProfit))
        {
            if(close[1] < breakdownPrice)
            {
                ExecuteTrade(ORDER_TYPE_SELL, stopLoss, "Bearish Rectangle");
            }
        }
    }

    if(PatternToTrade == BULLISH_FLAG || PatternToTrade == ALL)
    {
        Print("OnTick: Analyzing for Bullish Flag...");
        double breakoutPrice = 0, stopLoss = 0, takeProfit = 0;
        if(IsBullishFlag(high, low, volume, breakoutPrice, stopLoss, takeProfit))
        {
            if(close[1] > breakoutPrice)
            {
                ExecuteTrade(ORDER_TYPE_BUY, stopLoss, "Bullish Flag");
            }
        }
    }

    if(PatternToTrade == BEARISH_FLAG || PatternToTrade == ALL)
    {
        Print("OnTick: Analyzing for Bearish Flag...");
        double breakdownPrice = 0, stopLoss = 0, takeProfit = 0;
        if(IsBearishFlag(high, low, volume, breakdownPrice, stopLoss, takeProfit))
        {
            if(close[1] < breakdownPrice)
            {
                ExecuteTrade(ORDER_TYPE_SELL, stopLoss, "Bearish Flag");
            }
        }
    }

    if(PatternToTrade == HEAD_AND_SHOULDERS || PatternToTrade == ALL)
    {
        Print("OnTick: Analyzing for Head and Shoulders...");
        double breakdownPrice = 0, stopLoss = 0, takeProfit = 0;
        if(IsHeadAndShoulders(high, low, volume, breakdownPrice, stopLoss, takeProfit))
        {
            if(close[1] < breakdownPrice)
            {
                ExecuteTrade(ORDER_TYPE_SELL, stopLoss, "Head and Shoulders");
            }
        }
    }

    if(PatternToTrade == INVERTED_HEAD_AND_SHOULDERS || PatternToTrade == ALL)
    {
        Print("OnTick: Analyzing for Inverted Head and Shoulders...");
        double breakoutPrice = 0, stopLoss = 0, takeProfit = 0;
        if(IsInvertedHeadAndShoulders(high, low, volume, breakoutPrice, stopLoss, takeProfit))
        {
            if(close[1] > breakoutPrice)
            {
                ExecuteTrade(ORDER_TYPE_BUY, stopLoss, "Inverted Head and Shoulders");
            }
        }
    }

    if(PatternToTrade == FALLING_WEDGE || PatternToTrade == ALL)
    {
        Print("OnTick: Analyzing for Falling Wedge...");
        double breakoutPrice = 0, stopLoss = 0, takeProfit = 0;
        if(IsFallingWedge(high, low, volume, breakoutPrice, stopLoss, takeProfit))
        {
            if(close[1] > breakoutPrice)
            {
                ExecuteTrade(ORDER_TYPE_BUY, stopLoss, "Falling Wedge");
            }
        }
    }
}
//+------------------------------------------------------------------+
