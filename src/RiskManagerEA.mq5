
#property strict

//INPUTS
input bool   UseRiskPercent = false;
input double RiskPercent    = 0.5;
input double FixedRiskMoney = 25;
input double MarketSlippageBufferPoints = 0;

// BUTTONS
string BtnBuy     = "BTN_BUY";
string BtnSell    = "BTN_SELL";
string BtnBuyMkt  = "BTN_BUY_MKT";
string BtnSellMkt = "BTN_SELL_MKT";
string BtnPlace   = "BTN_PLACE";

//LINES
string BuyEntryLine  = "BUY_LIMIT";
string SellEntryLine = "SELL_LIMIT";
string BuySLLine     = "SL_BUY";
string SellSLLine    = "SL_SELL";
string MarketSLLine  = "SL_MARKET";

//MODE
enum TradeMode
{
   MODE_NONE,
   MODE_BUY,
   MODE_SELL,
   MODE_BUY_MARKET,
   MODE_SELL_MARKET
};
TradeMode CurrentMode = MODE_NONE;

void OnTick() {} 

int OnInit()
{
   // HARD RESET
   ObjectsDeleteAll(0, -1, OBJ_BUTTON);
   ResetState();

   CreateUIPanel();
   ChartRedraw();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int)
{
   ObjectsDeleteAll(0, -1, OBJ_BUTTON);
   ResetState();
   ChartRedraw();
}

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &,
                  const string &sparam)
{
   //BUTTON CLICKS
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == BtnBuy)       SetupBuyLimit();
      else if(sparam == BtnSell) SetupSellLimit();
      else if(sparam == BtnBuyMkt)  SetupBuyMarket();
      else if(sparam == BtnSellMkt) SetupSellMarket();
      else if(sparam == BtnPlace)   PlaceOrder();
   }

   // ESC KEY = CANCEL
   if(id == CHARTEVENT_KEYDOWN && (int)lparam == 27)
   {
      ResetState();
      ChartRedraw();
   }
}

void CreateUIPanel()
{
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int w = 95, h = 32, gx = 10, gy = 8;
   int x0 = cw - (w * 2) - gx - 20;
   int y0 = 20;

   CreateButton(BtnBuy,     "BUY LMT", x0,          y0,          clrDodgerBlue);
   CreateButton(BtnSell,    "SELL LMT",x0+w+gx,     y0,          clrRed);
   CreateButton(BtnBuyMkt,  "BUY",     x0,          y0+h+gy,    clrDodgerBlue);
   CreateButton(BtnSellMkt, "SELL",    x0+w+gx,     y0+h+gy,    clrRed);
   CreateButton(BtnPlace,   "PLACE",   x0+w/2,      y0+(h*2)+(gy*2), clrBlack);
}

void SetupBuyLimit()
{
   ResetState();
   double p = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   CreateLine(BuyEntryLine, p - 15*_Point, clrDodgerBlue);
   CreateLine(BuySLLine,    p - 40*_Point, clrRed);
   CurrentMode = MODE_BUY;
}

void SetupSellLimit()
{
   ResetState();
   double p = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   CreateLine(SellEntryLine, p + 15*_Point, clrDodgerBlue);
   CreateLine(SellSLLine,    p + 40*_Point, clrRed);
   CurrentMode = MODE_SELL;
}

void SetupBuyMarket()
{
   ResetState();
   double p = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   CreateLine(MarketSLLine, p - 40*_Point, clrRed);
   CurrentMode = MODE_BUY_MARKET;
}

void SetupSellMarket()
{
   ResetState();
   double p = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   CreateLine(MarketSLLine, p + 40*_Point, clrRed);
   CurrentMode = MODE_SELL_MARKET;
}

//placing order
void PlaceOrder()
{
   if(CurrentMode == MODE_BUY)
      ExecutePending(ORDER_TYPE_BUY_LIMIT, BuyEntryLine, BuySLLine);
   else if(CurrentMode == MODE_SELL)
      ExecutePending(ORDER_TYPE_SELL_LIMIT, SellEntryLine, SellSLLine);
   else if(CurrentMode == MODE_BUY_MARKET)
      ExecuteMarket(ORDER_TYPE_BUY);
   else if(CurrentMode == MODE_SELL_MARKET)
      ExecuteMarket(ORDER_TYPE_SELL);
}

void ExecutePending(ENUM_ORDER_TYPE type, string entryLine, string slLine)
{
   if(ObjectFind(0, entryLine) < 0 || ObjectFind(0, slLine) < 0) return;

   double entry = ObjectGetDouble(0, entryLine, OBJPROP_PRICE);
   double sl    = ObjectGetDouble(0, slLine, OBJPROP_PRICE);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(type == ORDER_TYPE_BUY_LIMIT)
   {
      if(entry >= ask || sl >= entry) return;
      double adj = entry + GetSpread();
      if(adj < ask) entry = adj;
   }

   if(type == ORDER_TYPE_SELL_LIMIT)
   {
      if(entry <= bid || sl <= entry) return;
      sl += GetSpread();
   }

   double lot = CalculateLot(entry, sl);
   if(lot <= 0) return;

   MqlTradeRequest req; MqlTradeResult res;
   ZeroMemory(req);

   req.action = TRADE_ACTION_PENDING;
   req.symbol = _Symbol;
   req.type   = type;
   req.volume = lot;
   req.price  = entry;
   req.sl     = sl;

   OrderSend(req, res);
   ResetState();
}

void ExecuteMarket(ENUM_ORDER_TYPE type)
{
   if(ObjectFind(0, MarketSLLine) < 0) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double buffer = MarketSlippageBufferPoints * _Point;

   double entry = (type == ORDER_TYPE_BUY) ? ask + buffer : bid - buffer;
   double sl = ObjectGetDouble(0, MarketSLLine, OBJPROP_PRICE);

   if(type == ORDER_TYPE_BUY && sl >= entry) return;
   if(type == ORDER_TYPE_SELL) sl += GetSpread();

   double lot = CalculateLot(entry, sl);
   if(lot <= 0) return;

   MqlTradeRequest req; MqlTradeResult res;
   ZeroMemory(req);

   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.type   = type;
   req.volume = lot;
   req.price  = (type == ORDER_TYPE_BUY) ? ask : bid;
   req.sl     = sl;

   OrderSend(req, res);
   ResetState();
}


double GetSpread()
{
   return SymbolInfoDouble(_Symbol, SYMBOL_ASK)
        - SymbolInfoDouble(_Symbol, SYMBOL_BID);
}

double CalculateLot(double entry, double sl)
{
   double risk = UseRiskPercent
      ? AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0
      : FixedRiskMoney;

   double dist = MathAbs(entry - sl);
   if(dist <= 0) return 0;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);

   double lossPerLot = (contractSize == 100000.0)
      ? (dist / tickSize) * tickValue
      : dist * contractSize;

   if(lossPerLot <= 0) return 0;

   double rawLot = risk / lossPerLot;

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(rawLot < minLot) return 0;

   int digits = (int)MathLog10(1.0 / step);
   return NormalizeDouble(MathFloor(rawLot / step) * step, digits);
}

void CreateLine(string name, double price, color clr)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, true);
}

void DeleteLines()
{
   ObjectDelete(0, BuyEntryLine);
   ObjectDelete(0, SellEntryLine);
   ObjectDelete(0, BuySLLine);
   ObjectDelete(0, SellSLLine);
   ObjectDelete(0, MarketSLLine);
}

void ResetState()
{
   DeleteLines();
   CurrentMode = MODE_NONE;
   ChartRedraw();
}

void CreateButton(string name, string text, int x, int y, color clr)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, 95);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, 32);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrBlack);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 11);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

