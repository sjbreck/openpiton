// Author: Susan Tan
// Date: 22.12.2019
// only works for 4 ways
// miss return is prioritized over hit b/c cache implemented this way
// NRU

import ariane_pkg::*;
import wt_cache_pkg::*;

module wt_dcache_nru(
  input  logic                 		       clk_i,
  input  logic                 		       rst_ni,
  input  logic                 		       flush_i,

  //input from miss unit (also from memory array)
  input  logic				       nru_hit_i, //update on a hit
  input  logic [DCACHE_CL_IDX_WIDTH-1:0]       nru_hit_idx_i, //update index 
  input  logic [$clog2(DCACHE_SET_ASSOC)-1:0]  nru_hit_way_i, //update way
  input  logic [DCACHE_CL_IDX_WIDTH-1:0]       nru_miss_idx_i, //miss to be replaced
  input  logic 				       nru_miss_i, //miss to be replaced is valid
  //predictor input
  input  logic [1:0]			       pred_result_i, //prediction on the new cl
  output logic [$clog2(DCACHE_SET_ASSOC)-1:0]  nru_way_o
);

  logic nru_array_d[DCACHE_NUM_WORDS-1:0][DCACHE_SET_ASSOC-1:0];
  logic nru_array_q[DCACHE_NUM_WORDS-1:0][DCACHE_SET_ASSOC-1:0];

  logic his0[DCACHE_NUM_WORDS-1:0]; 
  logic his1[DCACHE_NUM_WORDS-1:0]; 
  logic his2[DCACHE_NUM_WORDS-1:0]; 
  logic his3[DCACHE_NUM_WORDS-1:0]; 
  logic [1:0] nru_way[DCACHE_NUM_WORDS-1:0]; 

//assign replacement
assign nru_way_o = nru_way[nru_miss_idx_i];
//update nru array on a hit and a new line
for(genvar i=0; i<DCACHE_NUM_WORDS; i++)begin: gen_idxs_comb
	always_comb begin: gen_nru_comb
		his0[i] = nru_array_q[i][0]; //his 0 contains the way thats lru	
		his1[i] = nru_array_q[i][1];	
		his2[i] = nru_array_q[i][2];	
		his3[i] = nru_array_q[i][3];
		if(nru_miss_i && (nru_miss_idx_i == i))begin
			if(his0[i] == 1)begin
				nru_array_d[i][0] = 1'b1;
				nru_array_d[i][1] = his1[i];
				nru_array_d[i][2] = his2[i];
				nru_array_d[i][3] = his3[i];	
				nru_way[i] = 2'd0;
			end
			else if(his1[i] == 1)begin
				nru_array_d[i][0] = his0[i];
				nru_array_d[i][1] = 1'b1;
				nru_array_d[i][2] = his2[i];
				nru_array_d[i][3] = his3[i];
				nru_way[i] = 2'd1;	
			end
			else if(his2[i] == 1)begin
				nru_array_d[i][0] = his0[i];
				nru_array_d[i][1] = his1[i];
				nru_array_d[i][2] = 1'b1;
				nru_array_d[i][3] = his3[i];	
				nru_way[i] = 2'd2;
			end
			else if(his3[i] == 1)begin
				nru_array_d[i][0] = his0[i];
				nru_array_d[i][1] = his1[i];
				nru_array_d[i][2] = his2[i];
				nru_array_d[i][3] = 1'b1;
				nru_way[i] = 2'd3;	
			end
			else begin
				nru_array_d[i][0] = 1'b1;
				nru_array_d[i][1] = 1'b1;
				nru_array_d[i][2] = 1'b1;
				nru_array_d[i][3] = 1'b1;
				nru_way[i] = 2'b0;
			end	
		end
		else if(i==nru_hit_idx_i && nru_hit_i)begin
			nru_way[i] = (his0[i]==1)?2'd0:
				     (his1[i]==1)?2'd1:
				     (his2[i]==1)?2'd2:
				     (his3[i]==1)?2'd3:2'd0;		
			if(nru_hit_way_i == 0)begin
				nru_array_d[i][0] = '0;
				nru_array_d[i][1] = his1[i];
				nru_array_d[i][2] = his2[i];
				nru_array_d[i][3] = his3[i];	
			end
			else if(nru_hit_way_i == 1)begin
				nru_array_d[i][0] = his0[i];
				nru_array_d[i][1] = '0;
				nru_array_d[i][2] = his2[i];
				nru_array_d[i][3] = his3[i];	
			end	
			else if(nru_hit_way_i == 2)begin
				nru_array_d[i][0] = his0[i];
				nru_array_d[i][1] = his1[i];
				nru_array_d[i][2] = '0;
				nru_array_d[i][3] = his3[i];
			end				
			else if(nru_hit_way_i == 3)begin
				nru_array_d[i][0] = his0[i];
				nru_array_d[i][1] = his1[i];
				nru_array_d[i][2] = his2[i];
				nru_array_d[i][3] = '0;
			end				
			else begin
				nru_array_d[i] = nru_array_q[i];
			end
		 end
		 else begin
			nru_way[i] = 2'd0;
			nru_array_d[i] = nru_array_q[i];
		 end
	end
end

// Registers
for(genvar i=0; i<DCACHE_NUM_WORDS; i++)begin: gen_idxs
	always_ff @(negedge rst_ni or posedge clk_i) begin: gen_reg_arrays
		if(!rst_ni || flush_i)begin
			//initially, way 0 is nru, way 3 is mru
			nru_array_q[i][0]<=1'b1;
			nru_array_q[i][1]<=1'b1;
			nru_array_q[i][2]<=1'b1;
			nru_array_q[i][3]<=1'b1;
		end
		else begin
			nru_array_q[i] <= nru_array_d[i];
		end
	end
end


//
endmodule
