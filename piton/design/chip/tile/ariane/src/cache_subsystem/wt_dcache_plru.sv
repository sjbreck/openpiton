// Author: Susan Tan
// Date: 19.12.2019
// only works for 4 ways
// miss return is prioritized over hit b/c cache implemented this way
// PLRU

import ariane_pkg::*;
import wt_cache_pkg::*;

module wt_dcache_plru(
  input  logic                 		       clk_i,
  input  logic                 		       rst_ni,
  input  logic                 		       flush_i,

  //input from miss unit (also from memory array)
  input  logic				       plru_hit_i, //update on a hit
  input  logic [DCACHE_CL_IDX_WIDTH-1:0]       plru_hit_idx_i, //update index 
  input  logic [$clog2(DCACHE_SET_ASSOC)-1:0]  plru_hit_way_i, //update way
  input  logic				       plru_miss_i, //update on a mshr return
  input  logic [DCACHE_CL_IDX_WIDTH-1:0]       plru_miss_idx_i, //update index 
  //predictor input
  input  logic [1:0]			       pred_result_i, //prediction on the new cl
  output logic [$clog2(DCACHE_SET_ASSOC)-1:0]  plru_way_o
);

  logic [2:0] plru_array_d[DCACHE_NUM_WORDS-1:0];
  logic [2:0] plru_array_q[DCACHE_NUM_WORDS-1:0];

  logic [2:0] his[DCACHE_NUM_WORDS-1:0]; 

///////////////////////
//assign replacement
//        bit[2]  
//       /     \
//    bit[1]  bit[0]
//   /     \  /   \
//  way0  way1way2 way3 
///////////////////////
assign plru_way_o = (plru_array_q[plru_miss_idx_i] == 3'b000) ? 0:
                    (plru_array_q[plru_miss_idx_i] == 3'b001) ? 0:
                    (plru_array_q[plru_miss_idx_i] == 3'b010) ? 1:
                    (plru_array_q[plru_miss_idx_i] == 3'b011) ? 1:
                    (plru_array_q[plru_miss_idx_i] == 3'b100) ? 2:
                    (plru_array_q[plru_miss_idx_i] == 3'b101) ? 3:
                    (plru_array_q[plru_miss_idx_i] == 3'b110) ? 2:
                    (plru_array_q[plru_miss_idx_i] == 3'b111) ? 3:0;

//update lru array on a hit and a new line
for(genvar i=0; i<DCACHE_NUM_WORDS; i++)begin: gen_idxs_comb
	always_comb begin: gen_plru_comb
		his[i] = plru_array_q[i];

		if(plru_miss_i && (plru_miss_idx_i == i))begin
			/*if(pred_result_i == 0)begin//place new line as lru
				plru_array_d[i] <= his[i];
			end
			else begin*/
				if (his[i] == 3'b000) plru_array_d[i] = {2'b11,his[i][0]};   //toggle the pointers when a new line inserted
				else if (his[i] == 3'b001) plru_array_d[i] = {2'b11,his[i][0]};
				else if (his[i] == 3'b010) plru_array_d[i] = {2'b10,his[i][0]};
				else if (his[i] == 3'b011) plru_array_d[i] = {2'b10,his[i][0]};
				else if (his[i] == 3'b100) plru_array_d[i] = {1'b0,his[i][1],1'b1};
				else if (his[i] == 3'b101) plru_array_d[i] = {1'b0,his[i][1],1'b0};
				else if (his[i] == 3'b110) plru_array_d[i] = {1'b0,his[i][1],1'b1};
				else if (his[i] == 3'b111) plru_array_d[i] = {1'b0,his[i][1],1'b0};
			//end
		end
		else if(i==plru_hit_idx_i && plru_hit_i)begin
			if(plru_hit_way_i == 0)begin                //toggle the pointers when a line is hitted
				plru_array_d[i] = {2'b11,his[i][0]};
			end
			else if(plru_hit_way_i == 1)begin
				plru_array_d[i] = {2'b10,his[i][0]};
			end	
			else if(plru_hit_way_i == 2)begin
				plru_array_d[i] = {1'b0,his[i][1], 1'b1};
			end
			else if(plru_hit_way_i == 3)begin
				plru_array_d[i] = {1'b0,his[i][1], 1'b0};
			end				
			else begin
				plru_array_d[i] = plru_array_q[i];
			end
		 end
		 else begin
			plru_array_d[i] = plru_array_q[i];
		 end
	end
end

// Registers
for(genvar i=0; i<DCACHE_NUM_WORDS; i++)begin: gen_idxs
	always_ff @(negedge rst_ni or posedge clk_i) begin: gen_reg_arrays
		if(!rst_ni || flush_i)begin
			//initially, way 0 is lru, way 3 is mru
			plru_array_q[i][0]<=0;
			plru_array_q[i][1]<=1;
			plru_array_q[i][2]<=2;
			plru_array_q[i][3]<=3;
		end
		else begin
			plru_array_q[i] <= plru_array_d[i];
		end
	end
end


//
endmodule
