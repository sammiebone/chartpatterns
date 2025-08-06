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

    switch(_Period)
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
   rsi_handle = iRSI(_Symbol, _Period, RsiPeriod, PRICE_CLOSE);
   macd_handle = iMACD(_Symbol, _Period, MacdFastEmaPeriod, MacdSlowEmaPeriod, MacdSignalPeriod, PRICE_CLOSE);
   ma_handle = iMA(_Symbol, _Period, LongTermMaPeriod, 0, MODE_SMA, PRICE_CLOSE);
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
    for(int i = 1; i < LookbackBars - 20; i++)
    {
        if(high[i] > high[i+1] && low[i] > low[i+1] && (high[i] - low[i+10]) > scaled_FlagpoleMinHeight * _Point)
        {
            // Confirm preceding uptrend
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

    // Check for converging trendlines
    double upper_slope = (upFractal1 - upFractal2) / (upFractalIndex1 - upFractalIndex2);
    double lower_slope = (lowFractal1 - lowFractal2) / (lowFractalIndex1 - lowFractalIndex2);

    if(upper_slope < 0 && lower_slope > 0)
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
            if(CheckLongTermTrend(low))
            {
                if(CheckMACDConfirmation(BULLISH_CROSS))
                {
                    Print("Bullish Pennant confirmed.");
                    pennantLow = lowFractal1;
                    pennantLowIndex = lowFractalIndex1;
                    breakoutPrice = upFractal1;
                    return true;
                }
            }
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
    Print("Analyzing for Bearish Pennant...");
    // 1. Find the Flagpole
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

    // Check for converging trendlines
    double upper_slope = (upFractal1 - upFractal2) / (upFractalIndex1 - upFractalIndex2);
    double lower_slope = (lowFractal1 - lowFractal2) / (lowFractalIndex1 - lowFractalIndex2);

    if(upper_slope < 0 && lower_slope > 0)
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
            // Confirm preceding downtrend
            int pennant_start_index = upFractalIndex2;
            double price_at_pennant_start = high[pennant_start_index];
            double price_before_pennant = high[pennant_start_index + 20]; // 20 bars before pennant
            if(price_before_pennant - price_at_pennant_start > DowntrendMinHeight * _Point)
            {
                // Check for MACD confirmation
                if(CheckMACDConfirmation(BEARISH_CROSS))
                {
                    Print("Bearish Pennant confirmed.");
                    pennantHigh = upFractal1;
                    pennantHighIndex = upFractalIndex1;
                    breakdownPrice = lowFractal1;
                    return true;
                }
            }
        }
    }

    return false;
}
//+------------------------------------------------------------------+
//| Trading Functions                                                |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, double sl, string comment)
{
    if(PositionsTotal() > 0)
        return;

    double lot_size = Lots / 3.0;
    double tp1, tp2, tp3;

    if(type == ORDER_TYPE_BUY)
    {
        tp1 = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + TP1_Pips * _Point;
        tp2 = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + TP2_Pips * _Point;
        tp3 = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + TP3_Pips * _Point;
        trade.Buy(lot_size, NULL, 0, sl, tp1, comment + " TP1");
        trade.Buy(lot_size, NULL, 0, sl, tp2, comment + " TP2");
        trade.Buy(lot_size, NULL, 0, sl, tp3, comment + " TP3");
    }
    else if(type == ORDER_TYPE_SELL)
    {
        tp1 = SymbolInfoDouble(_Symbol, SYMBOL_BID) - TP1_Pips * _Point;
        tp2 = SymbolInfoDouble(_Symbol, SYMBOL_BID) - TP2_Pips * _Point;
        tp3 = SymbolInfoDouble(_Symbol, SYMBOL_BID) - TP3_Pips * _Point;
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
        return 0;

    // Check for lower highs and lower lows
    if(upper_fractals[0] < upper_fractals[1] && upper_fractals[1] < upper_fractals[2] &&
       low[lower_fractal_indices[0]] < low[lower_fractal_indices[1]] && low[lower_fractal_indices[1]] < low[lower_fractal_indices[2]])
    {
        // Check for divergence
        double upper_slope = (upper_fractals[0] - upper_fractals[2]) / (upper_fractal_indices[0] - upper_fractal_indices[2]);
        double lower_slope = (lower_fractals[0] - lower_fractals[2]) / (lower_fractal_indices[0] - lower_fractal_indices[2]);

        if(upper_slope < 0 && lower_slope < 0 && lower_slope < upper_slope)
        {
            // Confirm preceding downtrend
            int wedge_start_index = lower_fractal_indices[2];
            double price_at_wedge_start = high[wedge_start_index];
            double price_before_wedge = high[wedge_start_index + 20]; // 20 bars before wedge
            if(price_before_wedge - price_at_wedge_start > scaled_DowntrendMinHeight * _Point)
            {
                // Check for RSI divergence
                if(CheckRSIDivergence(low, lower_fractal_indices[0], lower_fractal_indices[2], BULLISH_DIVERGENCE))
                {
                    Print("Descending Broadening Wedge confirmed.");
                    breakoutPrice = upper_fractals[0];
                    breakdownPrice = lower_fractals[0];
                    stopLoss = lower_fractals[0] - StopLossPips * _Point;
                    takeProfit = high[upper_fractal_indices[2]]; // Method 1: Highest point of the wedge
                    return 1; // Bullish breakout
                }
            }
        }
    }

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
        return 0;

    // Check for higher highs and higher lows
    if(upper_fractals[0] > upper_fractals[1] && upper_fractals[1] > upper_fractals[2] &&
       low[lower_fractal_indices[0]] > low[lower_fractal_indices[1]] && low[lower_fractal_indices[1]] > low[lower_fractal_indices[2]])
    {
        // Check for divergence
        double upper_slope = (upper_fractals[0] - upper_fractals[2]) / (upper_fractal_indices[0] - upper_fractal_indices[2]);
        double lower_slope = (lower_fractals[0] - lower_fractals[2]) / (lower_fractal_indices[0] - lower_fractal_indices[2]);

        if(upper_slope > 0 && lower_slope > 0 && upper_slope > lower_slope)
        {
            // Confirm preceding uptrend
            int wedge_start_index = upper_fractal_indices[2];
            double price_at_wedge_start = low[wedge_start_index];
            double price_before_wedge = low[wedge_start_index + 20]; // 20 bars before wedge
            if(price_at_wedge_start - price_before_wedge > scaled_UptrendMinHeight * _Point)
            {
                // Check for RSI divergence
                if(CheckRSIDivergence(high, upper_fractal_indices[0], upper_fractal_indices[2], BEARISH_DIVERGENCE))
                {
                    Print("Ascending Broadening Wedge confirmed.");
                    breakdownPrice = lower_fractals[0];
                    breakoutPrice = upper_fractals[0];
                    stopLoss = upper_fractals[0] + StopLossPips * _Point;
                    takeProfit = low[lower_fractal_indices[2]]; // Method 1: Lowest point of the wedge
                    return 1; // Bearish breakout
                }
            }
        }
    }

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
        if(PositionSelect(_Symbol))
        {
            if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
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
                                trade.PositionModify(PositionGetInteger(POSITION_TICKET), tp1_price + TrailingStopPlusPips * _Point, PositionGetDouble(POSITION_TP));
                        }
                        else if(StringFind(comment, "TP3") != -1)
                        {
                            double tp2_price = 0;
                            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                                tp2_price = PositionGetDouble(POSITION_PRICE_OPEN) + TP2_Pips * _Point;
                            else
                                tp2_price = PositionGetDouble(POSITION_PRICE_OPEN) - TP2_Pips * _Point;

                            if(PositionGetDouble(POSITION_SL) < tp2_price)
                                trade.PositionModify(PositionGetInteger(POSITION_TICKET), tp2_price + TrailingStopPlusPips * _Point, PositionGetDouble(POSITION_TP));
                        }
                    }
                }
            }
        }
    }

    if(PatternToTrade == BULLISH_RECTANGLE || PatternToTrade == ALL)
    {
        double breakoutPrice = 0, stopLoss = 0, takeProfit = 0;
        if(IsBullishRectangle(high, low, breakoutPrice, stopLoss, takeProfit))
        {
            if(close[1] > breakoutPrice)
            {
                ExecuteTrade(ORDER_TYPE_BUY, stopLoss, "Bullish Rectangle");
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
        return false;

    // Check for horizontal trendlines
    double upper_level = (upper_fractals[0] + upper_fractals[1]) / 2;
    double lower_level = (lower_fractals[0] + lower_fractals[1]) / 2;
    double tolerance = 10 * _Point;

    if(MathAbs(upper_fractals[0] - upper_level) < tolerance && MathAbs(upper_fractals[1] - upper_level) < tolerance &&
       MathAbs(lower_fractals[0] - lower_level) < tolerance && MathAbs(lower_fractals[1] - lower_level) < tolerance)
    {
        // Check duration
        int duration = MathAbs(upper_fractal_indices[0] - lower_fractal_indices[0]);
        if(duration >= RectangleMinDuration && duration <= RectangleMaxDuration)
        {
            // Confirm preceding uptrend
            int rectangle_start_index = MathMax(upper_fractal_indices[1], lower_fractal_indices[1]);
            double price_at_rectangle_start = low[rectangle_start_index];
            double price_before_rectangle = low[rectangle_start_index + 20]; // 20 bars before rectangle
            if(price_at_rectangle_start - price_before_rectangle > scaled_UptrendMinHeight * _Point)
            {
            if(CheckMACDConfirmation(BULLISH_CROSS))
            {
                Print("Bullish Rectangle confirmed.");
                breakoutPrice = upper_level;
                stopLoss = lower_level - StopLossPips * _Point;
                takeProfit = breakoutPrice + (upper_level - lower_level);
                return true;
            }
            }
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

    ManageTrailingStop();
    // Get historical data
    double high[], low[], close[];
    datetime time[];
    long volume[];
    if(!GetHistory(LookbackBars, high, low, close, time, volume))
        return;

    // --- Pattern Detection ---
    // --- Pattern Detection ---
    if(PatternToTrade == BULLISH_PENNANT || PatternToTrade == ALL)
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
                ExecuteTrade(ORDER_TYPE_BUY, sl, "Bullish Pennant");
            }
        }
    }

    if(PatternToTrade == BEARISH_PENNANT || PatternToTrade == ALL)
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
                ExecuteTrade(ORDER_TYPE_SELL, sl, "Bearish Pennant");
            }
        }
    }

    if(PatternToTrade == DESCENDING_BROADENING_WEDGE || PatternToTrade == ALL)
    {
        double breakoutPrice = 0, breakdownPrice = 0, stopLoss = 0, takeProfit = 0;
        int breakout_type = IsDescendingBroadeningWedge(high, low, breakoutPrice, breakdownPrice, stopLoss, takeProfit);

        if(breakout_type == 1) // Bullish breakout
        {
            if(close[1] > breakoutPrice)
            {
                ExecuteTrade(ORDER_TYPE_BUY, stopLoss, "Descending Broadening Wedge");
            }
        }
        else if(breakout_type == 1 && TradeFailedWedgeBreakouts) // Bearish breakout
        {
            if(close[1] < breakdownPrice)
            {
                ExecuteTrade(ORDER_TYPE_SELL, stopLoss, "Descending Wedge Failed Breakout");
            }
        }
    }

    if(PatternToTrade == ASCENDING_BROADENING_WEDGE || PatternToTrade == ALL)
    {
        double breakdownPrice = 0, breakoutPrice = 0, stopLoss = 0, takeProfit = 0;
        int breakout_type = IsAscendingBroadeningWedge(high, low, breakdownPrice, breakoutPrice, stopLoss, takeProfit);

        if(breakout_type == 1) // Bearish breakout
        {
            if(close[1] < breakdownPrice)
            {
                ExecuteTrade(ORDER_TYPE_SELL, stopLoss, "Ascending Broadening Wedge");
            }
        }
        else if(breakout_type == 1 && TradeFailedWedgeBreakouts) // Bullish breakout
        {
            if(close[1] > breakoutPrice)
            {
                ExecuteTrade(ORDER_TYPE_BUY, stopLoss, "Ascending Wedge Failed Breakout");
            }
        }
    }
}
//+------------------------------------------------------------------+
