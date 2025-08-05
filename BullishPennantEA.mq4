//+------------------------------------------------------------------+
//|                                             BullishPennantEA.mq4 |
//|                                     Expert Advisor by Jules      |
//|                      Finds and trades Bullish Pennant patterns.  |
//+------------------------------------------------------------------+
#property copyright "Jules"
#property link      ""
#property version   "1.00"
#property strict

//--- input parameters
input double Lots                = 0.01;     // Lot size for trading
input int    StopLossPips        = 50;       // Stop loss in pips
input int    MagicNumber         = 12345;    // Magic number for orders
input int    FlagpoleMinHeight   = 200;      // Minimum height of the flagpole in points
input int    PennantMaxBars      = 25;       // Maximum bars for pennant formation
input int    LookbackBars        = 100;      // Number of bars to look back for a pattern

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
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
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
   // We use a static variable to ensure the expert only runs once per bar.
   static datetime lastBarTime = 0;
   if(lastBarTime == Time[0])
      return;
   lastBarTime = Time[0];

   // --- Bullish Pennant Pattern Detection ---

   // 1. Find the Flagpole: A strong upward move.
   int flagpoleStartIndex = -1;
   double flagpoleHigh = 0;
   double flagpoleLow = 0;
   int flagpoleBars = 0;

   // Loop through recent bars to find a potential flagpole.
   for(int i = 1; i < LookbackBars; i++)
   {
      // A simple algorithm to detect a sharp price increase.
      // This can be customized for more complex detection.
      if(High[i] > High[i+1] && Low[i] > Low[i+1] && (High[i] - Low[i+10]) > FlagpoleMinHeight * _Point)
      {
         flagpoleStartIndex = i;
         flagpoleHigh = High[i];
         flagpoleLow = Low[i+10];
         flagpoleBars = 10; // Assuming a 10-bar flagpole for this example.
         break;
      }
   }

   // If a flagpole is found, proceed to look for a pennant.
   if(flagpoleStartIndex != -1)
   {
      // 2. Find the Pennant: A consolidation period with converging trendlines.
      int pennantStartShift = flagpoleStartIndex - flagpoleBars;

      // We use fractals to identify swing highs and lows for the trendlines.
      double upFractal1 = 0, upFractal2 = 0;
      int upFractalIndex1 = 0, upFractalIndex2 = 0;
      double lowFractal1 = 0, lowFractal2 = 0;
      int lowFractalIndex1 = 0, lowFractalIndex2 = 0;

      // Find the two most recent upper fractals.
      upFractalIndex1 = FindFractal(pennantStartShift, MODE_UPPER);
      if(upFractalIndex1 > 0)
         upFractalIndex2 = FindFractal(upFractalIndex1 + 1, MODE_UPPER, pennantStartShift + PennantMaxBars);

      // Find the two most recent lower fractals.
      lowFractalIndex1 = FindFractal(pennantStartShift, MODE_LOWER);
      if(lowFractalIndex1 > 0)
         lowFractalIndex2 = FindFractal(lowFractalIndex1 + 1, MODE_LOWER, pennantStartShift + PennantMaxBars);

      // If we have found two pairs of fractals, check for convergence.
      if(upFractalIndex1 > 0 && upFractalIndex2 > 0 && lowFractalIndex1 > 0 && lowFractalIndex2 > 0)
      {
         upFractal1 = iFractals(NULL, 0, MODE_UPPER, upFractalIndex1);
         upFractal2 = iFractals(NULL, 0, MODE_UPPER, upFractalIndex2);
         lowFractal1 = iFractals(NULL, 0, MODE_LOWER, lowFractalIndex1);
         lowFractal2 = iFractals(NULL, 0, MODE_LOWER, lowFractalIndex2);

         // Check for converging trendlines (lower highs and higher lows).
         if(upFractal1 < upFractal2 && lowFractal1 > lowFractal2)
         {
            // 3. Volume Confirmation: Volume should decrease during pennant formation.
            long flagpoleVolume = CalculateVolume(flagpoleStartIndex, pennantStartShift);
            long pennantVolume = CalculateVolume(pennantStartShift, 1);

            if(flagpoleVolume > pennantVolume)
            {
               // 4. Breakout Confirmation and Trade Execution
               // The breakout occurs when the price closes above the upper trendline.
               double upperTrendlinePrice = GetTrendlinePrice(upFractal1, upFractalIndex1, upFractal2, upFractalIndex2, 1);
               if(Close[1] > upperTrendlinePrice)
               {
                  // Ensure there are no open trades managed by this EA.
                  if(IsTradeOpen() == false)
                  {
                     // Calculate Stop Loss: Below the lowest point of the pennant.
                     double sl = lowFractal1 - StopLossPips * _Point;

                     // Calculate Take Profit: Based on the flagpole height.
                     double flagpoleHeight = flagpoleHigh - flagpoleLow;
                     double tp = Close[1] + flagpoleHeight;

                     // Send the buy order.
                     OrderSend(Symbol(), OP_BUY, Lots, Ask, 3, sl, tp, "Bullish Pennant", MagicNumber, 0, clrGreen);
                  }
               }
            }
         }
      }
   }
}
//+------------------------------------------------------------------+
//| Helper Functions                                                 |
//+------------------------------------------------------------------+
int FindFractal(int start, int mode, int end = 0)
{
   for(int i = start; i > end; i--)
   {
      if(iFractals(NULL, 0, mode, i) != 0)
         return i;
   }
   return 0;
}

long CalculateVolume(int start, int end)
{
   long totalVolume = 0;
   for(int i = start; i > end; i--)
   {
      totalVolume += Volume[i];
   }
   return totalVolume;
}

bool IsTradeOpen()
{
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
            return true;
      }
   }
   return false;
}

double GetTrendlinePrice(double price1, int index1, double price2, int index2, int targetIndex)
{
    if (index1 == index2) return price1;
    return price1 + (double)(targetIndex - index1) * (price2 - price1) / (double)(index2 - index1);
}
  }
//+------------------------------------------------------------------+
