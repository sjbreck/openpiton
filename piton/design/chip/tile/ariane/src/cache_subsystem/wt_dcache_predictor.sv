//Created By: Susan Tan
//Last Time Modified: 12/12/2019

import ariane_pkg::*;
import wt_cache_pkg::*;

module wt_dcache_predictor #(
   parameter bit Axi64BitCompliant = 1'b0,
   parameter int unsigned NumPorts = 3
)( 
   input logic	        	clk_i,
   input logic          	rst_ni,
   input logic			flush_i, //when bad things happen, normally 0
   //input ports
   input logic			pred_hit_i,
   input logic   		pred_miss_i,  
   input logic[3:0]	        pred_outcome_i, 
   input logic[13:0]		pred_hit_shct_i, //signature of hitted line
   input logic[1:0][13:0]	pred_miss_shct_i, // evicted sig
   input logic[3:0]      	pred_miss_way_i, // evicted sig
   input logic[13:0]		pred_shct_i, //this field is only necessary on a cache miss
   
   //output ports
   output logic[1:0]	pred_result_o
);


 logic[1:0] shct_d[16383:0];
 logic[1:0] shct_q[16383:0];
 
//output prediction: 0 means distant reference, 1 means immedite reference
 assign pred_result_o = shct_q[pred_shct_i];
// assign valid_o = shct_q[signature_i].valid;

 logic[1:0] sat_counter_hit;
 logic[1:0] sat_counter_miss[3:0];

 always_comb begin: update_shct
      shct_d = shct_q;
      sat_counter_hit = shct_q[pred_hit_shct_i];
      sat_counter_miss[0] = shct_q[pred_miss_shct_i[0]];
      sat_counter_miss[1] = shct_q[pred_miss_shct_i[1]];
      sat_counter_miss[2] = shct_q[pred_miss_shct_i[2]];
      sat_counter_miss[3] = shct_q[pred_miss_shct_i[3]];
      if(pred_hit_i)begin
	 if(sat_counter_hit==3) shct_d[pred_hit_shct_i] = 3;
	 else shct_d[pred_hit_shct_i] = sat_counter_hit + 1;
      end
      else begin
	 shct_d[pred_hit_shct_i] = sat_counter_hit;
      end
      if(pred_miss_i)begin
	 if(pred_miss_way_i[0] && pred_outcome_i[0] == 0)begin
		if(sat_counter_miss[0] == 0) shct_d[pred_miss_shct_i[0]] = 0;
	 	else shct_d[pred_miss_shct_i[0]] = sat_counter_miss[0] - 1;
	 end
	 else begin
		shct_d[pred_miss_shct_i[0]] = sat_counter_miss[0];
	 end
	 if(pred_miss_way_i[1] && pred_outcome_i[1] == 0)begin
		if(sat_counter_miss[1] == 0) shct_d[pred_miss_shct_i[1]] = 0;
	 	else shct_d[pred_miss_shct_i[1]] = sat_counter_miss[1] - 1;
	 end
	 else begin
		shct_d[pred_miss_shct_i[1]] = sat_counter_miss[1];
	 end
	 if(pred_miss_way_i[2] && pred_outcome_i[2] == 0)begin
		if(sat_counter_miss[2] == 0) shct_d[pred_miss_shct_i[2]] = 0;
	 	else shct_d[pred_miss_shct_i[2]] = sat_counter_miss[2] - 1;
	 end
	 else begin
		shct_d[pred_miss_shct_i[2]] = sat_counter_miss[2];
	 end
	 if(pred_miss_way_i[3] && pred_outcome_i[3] == 0)begin
		if(sat_counter_miss[3] == 0) shct_d[pred_miss_shct_i[3]] = 0;
	 	else shct_d[pred_miss_shct_i[3]] = sat_counter_miss[3] - 1;
	 end
	 else begin
		shct_d[pred_miss_shct_i[3]] = sat_counter_miss[3];
	 end
      end
      else begin
		shct_d[pred_miss_shct_i[3]] = sat_counter_miss[3];
		shct_d[pred_miss_shct_i[2]] = sat_counter_miss[2];
		shct_d[pred_miss_shct_i[1]] = sat_counter_miss[1];
		shct_d[pred_miss_shct_i[0]] = sat_counter_miss[0];
      end
 end

 for (genvar i=0; i< 16384; i++) begin: gen_ffs
	always_ff @ (posedge clk_i or negedge rst_ni)begin:ff_shct
		if(!rst_ni || flush_i)begin
			shct_q[i] <= 3;
		end
		else begin
			shct_q[i] <= shct_d[i];
		end
	end
	
 end

endmodule
