// Author: Susan Tan
// Date: 19.12.2019
// only works for 4 ways
// miss return is prioritized over hit b/c cache implemented this way

import ariane_pkg::*;
import wt_cache_pkg::*;

module wt_dcache_lru(
  input  logic                 		       clk_i,
  input  logic                 		       rst_ni,
  input  logic                 		       flush_i,

  //input from miss unit (also from memory array)
  input  logic				       lru_hit_i, //update on a hit
  input  logic [DCACHE_CL_IDX_WIDTH-1:0]       lru_hit_idx_i, //update index 
  input  logic [$clog2(DCACHE_SET_ASSOC)-1:0]  lru_hit_way_i, //update way
  input  logic				       lru_miss_i, //update on a mshr return
  input  logic [DCACHE_CL_IDX_WIDTH-1:0]       lru_miss_idx_i, //update index 
  //predictor input
  input  logic [1:0]			       pred_result_i, //prediction on the new cl
  output logic [$clog2(DCACHE_SET_ASSOC)-1:0]  lru_way_o
);

  logic [1:0] lru_array_d[DCACHE_NUM_WORDS-1:0][DCACHE_SET_ASSOC-1:0];
  logic [1:0] lru_array_q[DCACHE_NUM_WORDS-1:0][DCACHE_SET_ASSOC-1:0];

  logic [1:0] his0[DCACHE_NUM_WORDS-1:0]; 
  logic [1:0] his1[DCACHE_NUM_WORDS-1:0]; 
  logic [1:0] his2[DCACHE_NUM_WORDS-1:0]; 
  logic [1:0] his3[DCACHE_NUM_WORDS-1:0]; 

//assign replacement
assign lru_way_o = lru_array_q[lru_miss_idx_i][0];
//update lru array on a hit and a new line
for(genvar i=0; i<DCACHE_NUM_WORDS; i++)begin: gen_idxs_comb
	always_comb begin: gen_lru_comb
		his0[i] = lru_array_q[i][0]; //his 0 contains the way thats lru	
		his1[i] = lru_array_q[i][1];	
		his2[i] = lru_array_q[i][2];	
		his3[i] = lru_array_q[i][3];

		if(lru_miss_i && (lru_miss_idx_i == i))begin
			//if(pred_result_i == 3)begin//place new line as lru
				lru_array_d[i][0] = his1[i];
				lru_array_d[i][1] = his2[i];
				lru_array_d[i][2] = his3[i];
				lru_array_d[i][3] = his0[i];	
			/*end
			else if(pred_result_i == 0)begin
				lru_array_d[i][0] = his0[i];
				lru_array_d[i][1] = his1[i];
				lru_array_d[i][2] = his2[i];
				lru_array_d[i][3] = his3[i];	
			end
			else begin
				lru_array_d[i][0] = his1[i];
				lru_array_d[i][1] = his2[i];
				lru_array_d[i][2] = his0[i];
				lru_array_d[i][3] = his3[i];	
			end*/
		end
		else if(i==lru_hit_idx_i && lru_hit_i)begin
			if(lru_hit_way_i == his0[i])begin
				lru_array_d[i][0] = his1[i];
				lru_array_d[i][1] = his2[i];
				lru_array_d[i][2] = his3[i];
				lru_array_d[i][3] = his0[i];	
			end
			else if(lru_hit_way_i == his1[i])begin
				lru_array_d[i][0] = his0[i];
				lru_array_d[i][1] = his2[i];
				lru_array_d[i][2] = his3[i];
				lru_array_d[i][3] = his1[i];	
			end	
			else if(lru_hit_way_i == his2[i])begin
				lru_array_d[i][0] = his0[i];
				lru_array_d[i][1] = his1[i];
				lru_array_d[i][2] = his3[i];
				lru_array_d[i][3] = his2[i];
			end				
			else if(lru_hit_way_i == his3[i])begin
				lru_array_d[i][0] = his0[i];
				lru_array_d[i][1] = his1[i];
				lru_array_d[i][2] = his2[i];
				lru_array_d[i][3] = his3[i];
			end				
			else begin
				lru_array_d[i] = lru_array_q[i];
			end
		 end
		 else begin
			lru_array_d[i] = lru_array_q[i];
		 end
	end
end

// Registers
for(genvar i=0; i<DCACHE_NUM_WORDS; i++)begin: gen_idxs
	always_ff @(negedge rst_ni or posedge clk_i) begin: gen_reg_arrays
		if(!rst_ni || flush_i)begin
			//initially, way 0 is lru, way 3 is mru
			lru_array_q[i][0]<=0;
			lru_array_q[i][1]<=1;
			lru_array_q[i][2]<=2;
			lru_array_q[i][3]<=3;
		end
		else begin
			lru_array_q[i] <= lru_array_d[i];
		end
	end
end


//
endmodule
