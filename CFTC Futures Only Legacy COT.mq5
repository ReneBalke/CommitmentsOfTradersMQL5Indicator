#include <Arrays/ArrayObj.mqh>
#include <internetlib.mqh>
#include <JAson.mqh>

#property indicator_separate_window
#property indicator_plots 3
#property indicator_buffers 3

#property indicator_label1 "Commercial"
#property indicator_type1 DRAW_LINE
#property indicator_style1 STYLE_SOLID
#property indicator_color1 clrRed
#property indicator_width1 1

#property indicator_label2 "Noncommercial"
#property indicator_type2 DRAW_LINE
#property indicator_style2 STYLE_SOLID
#property indicator_color2 clrGreen
#property indicator_width2 1

#property indicator_label3 "Nonreportable"
#property indicator_type3 DRAW_LINE
#property indicator_style3 STYLE_SOLID
#property indicator_color3 clrPurple
#property indicator_width3 1

class CCOTData : public CObject {
public:
   string name;
   datetime time;
   long commercialLong;
   long commercialShort;
   long commercialNet;
   long noncommercialLong;
   long noncommercialShort;
   long noncommercialNet;
   long nonreportableLong;
   long nonreportableShort;
   long nonreportableNet;
   
                     CCOTData(CJAVal &json){
                        name = json["contract_market_name"].ToStr();
                        time = StringToTime(json["report_date_as_yyyy_mm_dd"].ToStr());
                        commercialLong = json["comm_positions_long_all"].ToInt();
                        commercialShort = json["comm_positions_short_all"].ToInt();
                        commercialNet = commercialLong - commercialShort;
                        noncommercialLong = json["noncomm_positions_long_all"].ToInt();
                        noncommercialShort = json["noncomm_positions_short_all"].ToInt();
                        noncommercialNet = noncommercialLong - noncommercialShort;
                        nonreportableLong = json["nonrept_positions_long_all"].ToInt();
                        nonreportableShort = json["nonrept_positions_short_all"].ToInt();
                        nonreportableNet = nonreportableLong - nonreportableShort;
                     }
                     
   string            ToString(){
                        string txt;
                        StringConcatenate(txt,name,", ",time,"\n commercial: ",commercialNet,
                                                            "\n noncommercial: ",noncommercialNet,
                                                            "\n nonreportable: ",nonreportableNet);
                        return txt;
                     }
                     
   virtual int       Compare(const CObject *node,const int mode=0) const { 
                        CCOTData* other = (CCOTData*)node;
                        return (int)(time - other.time);
                     }
};

input string ContractMarketName = "EURO FX";
input int FromYear = 2020;
input bool IsCommercial = true;
input bool IsNoncommercial = true;
input bool IsNonreportable = true;

double buffer_commercial[];
double buffer_noncommercial[];
double buffer_nonreportable[];

CArrayObj reports;
int lastDay;

int OnInit()
  {
   IndicatorSetInteger(INDICATOR_DIGITS,0);

   SetIndexBuffer(0,buffer_commercial,INDICATOR_DATA);
   ArraySetAsSeries(buffer_commercial,true);
   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   
   SetIndexBuffer(1,buffer_noncommercial,INDICATOR_DATA);
   ArraySetAsSeries(buffer_noncommercial,true);
   PlotIndexSetDouble(1,PLOT_EMPTY_VALUE,EMPTY_VALUE);

   SetIndexBuffer(2,buffer_nonreportable,INDICATOR_DATA);
   ArraySetAsSeries(buffer_nonreportable,true);
   PlotIndexSetDouble(2,PLOT_EMPTY_VALUE,EMPTY_VALUE);

   if(MQLInfoInteger(MQL_TESTER)){
      getReports();
   }

   return(INIT_SUCCEEDED);
  }

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[]){
                
   MqlDateTime dt;
   TimeCurrent(dt);
   
   if(!MQLInfoInteger(MQL_TESTER) && lastDay != dt.day_of_year){
      getReports();
   }
   
   if(prev_calculated == 0){
      ArrayInitialize(buffer_commercial,EMPTY_VALUE);
      ArrayInitialize(buffer_noncommercial,EMPTY_VALUE);
      ArrayInitialize(buffer_nonreportable,EMPTY_VALUE);   
   }
   
   if(rates_total != prev_calculated){
      buffer_commercial[0] = EMPTY_VALUE;
      buffer_noncommercial[0] = EMPTY_VALUE;
      buffer_nonreportable[0] = EMPTY_VALUE;
   }

   if(lastDay != dt.day_of_year){
      for(int i = 0; i < reports.Total(); i++){
         CCOTData* cot = reports.At(i);
//         Print(cot.ToString());
         
         int index = iBarShift(_Symbol,PERIOD_CURRENT,cot.time);
         if(index > 0){
            if(IsCommercial) ArrayFill(buffer_commercial,ArraySize(buffer_commercial)-index-1,index+1,(double)cot.commercialNet);
            if(IsNoncommercial) ArrayFill(buffer_noncommercial,ArraySize(buffer_noncommercial)-index-1,index+1,(double)cot.noncommercialNet);
            if(IsNonreportable) ArrayFill(buffer_nonreportable,ArraySize(buffer_noncommercial)-index-1,index+1,(double)cot.nonreportableNet);
         }
      }   
   }
   lastDay = dt.day_of_year;

   if(rates_total != prev_calculated){
      int limit = rates_total - prev_calculated;
      if(limit >= rates_total) limit = rates_total - 2;
   
      for(int i = limit; i >= 0; i--){
         if(buffer_commercial[i] == EMPTY_VALUE) buffer_commercial[i] = buffer_commercial[i+1];
         if(buffer_noncommercial[i] == EMPTY_VALUE) buffer_noncommercial[i] = buffer_noncommercial[i+1];
         if(buffer_nonreportable[i] == EMPTY_VALUE) buffer_nonreportable[i] = buffer_nonreportable[i+1];
      }  
   }

   return(rates_total);
}

bool getReports(){
   reports.Clear();

   //string app_token = ytS7zrjJEFN5HJAF8cn6zK3D6;
   //string contract_name = "WHEAT-SRW";
   string contract_name = ContractMarketName; //"EURO FX";
   int limit = 1000000;
   int from_year = FromYear; //2020;
    
   string host = "publicreporting.cftc.gov";
   string object = StringFormat("/resource/6dca-aqww.json?contract_market_name=%s&$limit=%d&$where=report_date_as_yyyy_mm_dd>'%d'",contract_name,limit,from_year);
   int port = 80;

//   ResetLastError();
     
   MqlNet net;
   net.Open(host,port);
   
//   Print(GetLastError());

   string res;
   net.Request("GET",object,res);
   
//   Print(res.Length());
//   Print(res);
   
   net.Close();

   CJAVal json;  
   json.Deserialize(res);
   
//   string out;
//   json.Serialize(out);
         
   for(int i = 0; i < json.Size(); i++){
      CCOTData* cot = new CCOTData(json[i]);
      reports.Add(cot);
   }
   
   reports.Sort();
   
   return true;
}