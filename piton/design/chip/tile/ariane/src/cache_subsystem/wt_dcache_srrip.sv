// Author: Susan Tan
// Date: 22.12.2019
// only works for 4 ways
// miss return is prioritized over hit b/c cache implemented this way

import ariane_pkg::*;
import wt_cache_pkg::*;

module wt_dcache_srrip(
  input  logic                 		       clk_i,
  input  logic                 		       rst_ni,
  input  logic                 		       flush_i,

  //input from miss unit (also from memory array)
  input  logic				       srrip_hit_i, //update on a hit
  input  logic [DCACHE_CL_IDX_WIDTH-1:0]       srrip_hit_idx_i, //update index 
  input  logic [$clog2(DCACHE_SET_ASSOC)-1:0]  srrip_hit_way_i, //update way
  input  logic [DCACHE_CL_IDX_WIDTH-1:0]       srrip_miss_idx_i, //miss to be replaced
  input  logic 				       srrip_miss_i, //miss to be replaced is valid
  //predictor input
  input  logic [1:0]			       pred_result_i, //prediction on the new cl
  output logic [$clog2(DCACHE_SET_ASSOC)-1:0]  srrip_way_o,
  output logic				       srrip_conflict_o
);

  logic [1:0] srrip_array_d[DCACHE_NUM_WORDS-1:0][DCACHE_SET_ASSOC-1:0];
  logic [1:0] srrip_array_q[DCACHE_NUM_WORDS-1:0][DCACHE_SET_ASSOC-1:0];

  logic [1:0] his0[DCACHE_NUM_WORDS-1:0]; 
  logic [1:0] his1[DCACHE_NUM_WORDS-1:0]; 
  logic [1:0] his2[DCACHE_NUM_WORDS-1:0]; 
  logic [1:0] his3[DCACHE_NUM_WORDS-1:0]; 
  logic [1:0] tmp1_0[DCACHE_NUM_WORDS-1:0]; 
  logic [1:0] tmp1_1[DCACHE_NUM_WORDS-1:0]; 
  logic [1:0] tmp1_2[DCACHE_NUM_WORDS-1:0]; 
  logic [1:0] tmp1_3[DCACHE_NUM_WORDS-1:0]; 
  logic [1:0] tmp2_0[DCACHE_NUM_WORDS-1:0]; 
  logic [1:0] tmp2_1[DCACHE_NUM_WORDS-1:0]; 
  logic [1:0] tmp2_2[DCACHE_NUM_WORDS-1:0]; 
  logic [1:0] tmp2_3[DCACHE_NUM_WORDS-1:0]; 
  logic [1:0] tmp3_0[DCACHE_NUM_WORDS-1:0]; 
  logic [1:0] tmp3_1[DCACHE_NUM_WORDS-1:0]; 
  logic [1:0] tmp3_2[DCACHE_NUM_WORDS-1:0]; 
  logic [1:0] tmp3_3[DCACHE_NUM_WORDS-1:0]; 
  logic [1:0] srrip_way[DCACHE_NUM_WORDS-1:0]; 

//assign replacement
assign srrip_way_o = srrip_way[srrip_miss_idx_i];
//update srrip array on a hit and a new line
for(genvar i=0; i<DCACHE_NUM_WORDS; i++)begin: gen_idxs_comb
	always_comb begin: gen_srrip_comb
		his0[i] = srrip_array_q[i][0]; //his 0 contains the way thats lru	
		his1[i] = srrip_array_q[i][1];	
		his2[i] = srrip_array_q[i][2];	
		his3[i] = srrip_array_q[i][3];
		tmp1_0[i] = his0[i]+1;
		tmp1_1[i] = his1[i]+1;
		tmp1_2[i] = his2[i]+1;
		tmp1_3[i] = his3[i]+1;
		tmp2_0[i] = his0[i]+2;
		tmp2_1[i] = his1[i]+2;
		tmp2_2[i] = his2[i]+2;
		tmp2_3[i] = his3[i]+2;
		tmp3_0[i] = his0[i]+3;
		tmp3_1[i] = his1[i]+3;
		tmp3_2[i] = his2[i]+3;
		tmp3_3[i] = his3[i]+3;
		if(srrip_miss_i && (srrip_miss_idx_i == i))begin
			if(pred_result_i == 0)begin//place new line as srrip
				if(his0[i] == 3)begin
					srrip_array_d[i][0] = 3;
					srrip_array_d[i][1] = his1[i];
					srrip_array_d[i][2] = his2[i];
					srrip_array_d[i][3] = his3[i];
					srrip_way[i] = 0;	
				end
				else if(his1[i] == 3)begin
					srrip_array_d[i][0] = his0[i];
					srrip_array_d[i][1] = 3;
					srrip_array_d[i][2] = his2[i];
					srrip_array_d[i][3] = his3[i];	
					srrip_way[i] = 1;
				end
				else if(his2[i] == 3)begin
					srrip_array_d[i][0] = his0[i];
					srrip_array_d[i][1] = his1[i];
					srrip_array_d[i][2] = 3;
					srrip_array_d[i][3] = his3[i];	
					srrip_way[i] = 2;
				end
				else if(his3[i] == 3)begin
					srrip_array_d[i][0] = his0[i];
					srrip_array_d[i][1] = his1[i];
					srrip_array_d[i][2] = his2[i];
					srrip_array_d[i][3] = 3;	
					srrip_way[i] = 3;
				end
				else begin
					if(tmp1_0[i]==3 || tmp1_1[i]==3 || tmp1_2[i]==3 || tmp1_3[i]==3)
					begin
						srrip_array_d[i][0] = tmp1_0[i];
						srrip_array_d[i][1] = tmp1_1[i];
						srrip_array_d[i][2] = tmp1_2[i];
						srrip_array_d[i][3] = tmp1_3[i];
						srrip_way[i] = (tmp1_0[i]==3)?0:
							      (tmp1_1[i]==3)?1:
							      (tmp1_2[i]==3)?2:
							      (tmp1_3[i]==3)?3:0;		
					end
					else if(tmp2_0[i]==3 || tmp2_1[i]==3 || tmp2_2[i]==3 || tmp2_3[i]==3)
					begin
						srrip_array_d[i][0] = tmp2_0[i];
						srrip_array_d[i][1] = tmp2_1[i];
						srrip_array_d[i][2] = tmp2_2[i];
						srrip_array_d[i][3] = tmp2_3[i];		
						srrip_way[i] = (tmp2_0[i]==3)?0:
							      (tmp2_1[i]==3)?1:
							      (tmp2_2[i]==3)?2:
							      (tmp2_3[i]==3)?3:0;		
					end
					else begin
						srrip_array_d[i][0] = tmp3_0[i];
						srrip_array_d[i][1] = tmp3_1[i];
						srrip_array_d[i][2] = tmp3_2[i];
						srrip_array_d[i][3] = tmp3_3[i];		
						srrip_way[i] = (tmp3_0[i]==3)?0:
							      (tmp3_1[i]==3)?1:
							      (tmp3_2[i]==3)?2:
							      (tmp3_3[i]==3)?3:0;		
					end
				end	
			end
			else if (pred_result_i == 3) 
		        begin
				if(his0[i] == 3)begin
					srrip_array_d[i][0] = 0;
					srrip_array_d[i][1] = his1[i];
					srrip_array_d[i][2] = his2[i];
					srrip_array_d[i][3] = his3[i];	
					srrip_way[i] = 0;
				end
				else if(his1[i] == 3)begin
					srrip_array_d[i][0] = his0[i];
					srrip_array_d[i][1] = 0;
					srrip_array_d[i][2] = his2[i];
					srrip_array_d[i][3] = his3[i];
					srrip_way[i] = 1;	
				end
				else if(his2[i] == 3)begin
					srrip_array_d[i][0] = his0[i];
					srrip_array_d[i][1] = his1[i];
					srrip_array_d[i][2] = 0;
					srrip_array_d[i][3] = his3[i];	
					srrip_way[i] = 2;
				end
				else if(his3[i] == 3)begin
					srrip_array_d[i][0] = his0[i];
					srrip_array_d[i][1] = his1[i];
					srrip_array_d[i][2] = his2[i];
					srrip_array_d[i][3] = 0;
					srrip_way[i] = 3;	
				end
				else begin
					if(tmp1_0[i]==3 || tmp1_1[i]==3 || tmp1_2[i]==3 || tmp1_3[i]==3)
					begin
						srrip_array_d[i][0] = (tmp1_0[i]==3)? 0 : tmp1_0[i];
						srrip_array_d[i][1] = (tmp1_0[i]!=3 && tmp1_1[i]==3)? 0 : tmp1_1[i];
						srrip_array_d[i][2] = (tmp1_0[i]!=3 && tmp1_1[i]!=3 && tmp1_2[i] == 3)? 0 : tmp1_2[i];
						srrip_array_d[i][3] = (tmp1_0[i]!=3 && tmp1_1[i]!=3 && tmp1_2[i]!=3 && tmp1_3[i]==3)? 0 : tmp1_3[i];
						srrip_way[i] = (tmp1_0[i]==3)?0:
							       (tmp1_1[i]==3)?1:
							       (tmp1_2[i]==3)?2:
							       (tmp1_3[i]==3)?3:0;		
					end
					else if(tmp2_0[i]==3 || tmp2_1[i]==3 || tmp2_2[i]==3 || tmp2_3[i]==3)
					begin
						srrip_array_d[i][0] = (tmp2_0[i]==3)? 0 : tmp2_0[i];
						srrip_array_d[i][1] = (tmp2_0[i]!=3 && tmp2_1[i]==3)? 0 : tmp2_1[i];
						srrip_array_d[i][2] = (tmp2_0[i]!=3 && tmp2_1[i]!=3 && tmp2_2[i] == 3)? 0 : tmp2_2[i];
						srrip_array_d[i][3] = (tmp2_0[i]!=3 && tmp2_1[i]!=3 && tmp2_2[i]!=3 && tmp2_3[i]==3)? 0 : tmp2_3[i];
						srrip_way[i] = (tmp2_0[i]==3)?0:
							       (tmp2_1[i]==3)?1:
							       (tmp2_2[i]==3)?2:
							       (tmp2_3[i]==3)?3:0;		
					end
					else begin
						srrip_array_d[i][0] = (tmp3_0[i]==3)? 0 : tmp3_0[i];
						srrip_array_d[i][1] = (tmp3_0[i]!=3 && tmp3_1[i]==3)? 0 : tmp3_1[i];
						srrip_array_d[i][2] = (tmp3_0[i]!=3 && tmp3_1[i]!=3 && tmp3_2[i] == 3)? 0 : tmp3_2[i];
						srrip_array_d[i][3] = (tmp3_0[i]!=3 && tmp3_1[i]!=3 && tmp3_2[i]!=3 && tmp3_3[i]==3)? 0 : tmp3_3[i];
						srrip_way[i] = (tmp3_0[i]==3)?0:
							       (tmp3_1[i]==3)?1:
							       (tmp3_2[i]==3)?2:
							       (tmp3_3[i]==3)?3:0;		
					end
				end	
		        end
			else begin
				if(his0[i] == 3)begin
					srrip_array_d[i][0] = 2;
					srrip_array_d[i][1] = his1[i];
					srrip_array_d[i][2] = his2[i];
					srrip_array_d[i][3] = his3[i];	
					srrip_way[i] = 0;
				end
				else if(his1[i] == 3)begin
					srrip_array_d[i][0] = his0[i];
					srrip_array_d[i][1] = 2;
					srrip_array_d[i][2] = his2[i];
					srrip_array_d[i][3] = his3[i];
					srrip_way[i] = 1;	
				end
				else if(his2[i] == 3)begin
					srrip_array_d[i][0] = his0[i];
					srrip_array_d[i][1] = his1[i];
					srrip_array_d[i][2] = 2;
					srrip_array_d[i][3] = his3[i];	
					srrip_way[i] = 2;
				end
				else if(his3[i] == 3)begin
					srrip_array_d[i][0] = his0[i];
					srrip_array_d[i][1] = his1[i];
					srrip_array_d[i][2] = his2[i];
					srrip_array_d[i][3] = 2;
					srrip_way[i] = 3;	
				end
				else begin
					if(tmp1_0[i]==3 || tmp1_1[i]==3 || tmp1_2[i]==3 || tmp1_3[i]==3)
					begin
						srrip_array_d[i][0] = (tmp1_0[i]==3)? 2 : tmp1_0[i];
						srrip_array_d[i][1] = (tmp1_0[i]!=3 && tmp1_1[i]==3)? 2 : tmp1_1[i];
						srrip_array_d[i][2] = (tmp1_0[i]!=3 && tmp1_1[i]!=3 && tmp1_2[i] == 3)? 2 : tmp1_2[i];
						srrip_array_d[i][3] = (tmp1_0[i]!=3 && tmp1_1[i]!=3 && tmp1_2[i]!=3 && tmp1_3[i]==3)? 2 : tmp1_3[i];
						srrip_way[i] = (tmp1_0[i]==3)?0:
							       (tmp1_1[i]==3)?1:
							       (tmp1_2[i]==3)?2:
							       (tmp1_3[i]==3)?3:0;		
					end
					else if(tmp2_0[i]==3 || tmp2_1[i]==3 || tmp2_2[i]==3 || tmp2_3[i]==3)
					begin
						srrip_array_d[i][0] = (tmp2_0[i]==3)? 2 : tmp2_0[i];
						srrip_array_d[i][1] = (tmp2_0[i]!=3 && tmp2_1[i]==3)? 2 : tmp2_1[i];
						srrip_array_d[i][2] = (tmp2_0[i]!=3 && tmp2_1[i]!=3 && tmp2_2[i] == 3)? 2 : tmp2_2[i];
						srrip_array_d[i][3] = (tmp2_0[i]!=3 && tmp2_1[i]!=3 && tmp2_2[i]!=3 && tmp2_3[i]==3)? 2 : tmp2_3[i];
						srrip_way[i] = (tmp2_0[i]==3)?0:
							       (tmp2_1[i]==3)?1:
							       (tmp2_2[i]==3)?2:
							       (tmp2_3[i]==3)?3:0;		
					end
					else begin
						srrip_array_d[i][0] = (tmp3_0[i]==3)? 2 : tmp3_0[i];
						srrip_array_d[i][1] = (tmp3_0[i]!=3 && tmp3_1[i]==3)? 2 : tmp3_1[i];
						srrip_array_d[i][2] = (tmp3_0[i]!=3 && tmp3_1[i]!=3 && tmp3_2[i] == 3)? 2 : tmp3_2[i];
						srrip_array_d[i][3] = (tmp3_0[i]!=3 && tmp3_1[i]!=3 && tmp3_2[i]!=3 && tmp3_3[i]==3)? 2 : tmp3_3[i];
						srrip_way[i] = (tmp3_0[i]==3)?0:
							       (tmp3_1[i]==3)?1:
							       (tmp3_2[i]==3)?2:
							       (tmp3_3[i]==3)?3:0;		
					end
				end	
			end
		end
		else if(i==srrip_hit_idx_i && srrip_hit_i)begin
			srrip_way[i] = (his0[i]==3)?0:
				       (his1[i]==3)?1:
				       (his2[i]==3)?2:
				       (his3[i]==3)?3:
				       (his0[i]==2)?0:		
				       (his1[i]==2)?1:		
				       (his2[i]==2)?2:		
				       (his3[i]==2)?3:		
				       (his0[i]==1)?0:		
				       (his1[i]==1)?1:		
				       (his2[i]==1)?2:		
				       (his3[i]==1)?3:		
				       (his0[i]==0)?0:		
				       (his1[i]==0)?1:		
				       (his2[i]==0)?2:		
				       (his3[i]==0)?3:0;		
			if(srrip_hit_way_i == 0)begin
				srrip_array_d[i][0] = 0;
				srrip_array_d[i][1] = his1[i];
				srrip_array_d[i][2] = his2[i];
				srrip_array_d[i][3] = his3[i];	
			end
			else if(srrip_hit_way_i == 1)begin
				srrip_array_d[i][0] = his0[i];
				srrip_array_d[i][1] = 0;
				srrip_array_d[i][2] = his2[i];
				srrip_array_d[i][3] = his3[i];	
			end	
			else if(srrip_hit_way_i == 2)begin
				srrip_array_d[i][0] = his0[i];
				srrip_array_d[i][1] = his1[i];
				srrip_array_d[i][2] = 0;
				srrip_array_d[i][3] = his3[i];
			end				
			else if(srrip_hit_way_i == 3)begin
				srrip_array_d[i][0] = his0[i];
				srrip_array_d[i][1] = his1[i];
				srrip_array_d[i][2] = his2[i];
				srrip_array_d[i][3] = 0;
			end				
			else begin
				srrip_array_d[i] = srrip_array_q[i];
			end
		 end
		 else begin
			srrip_way[i] = 0;
			srrip_array_d[i] = srrip_array_q[i];
		 end
	end
end

// Registers
for(genvar i=0; i<DCACHE_NUM_WORDS; i++)begin: gen_idxs
	always_ff @(negedge rst_ni or posedge clk_i) begin: gen_reg_arrays
		if(!rst_ni || flush_i)begin
			//initially, way 0 is srrip, way 3 is mru
			srrip_array_q[i][0]<=3;
			srrip_array_q[i][1]<=3;
			srrip_array_q[i][2]<=3;
			srrip_array_q[i][3]<=3;
		end
		else begin
			srrip_array_q[i] <= srrip_array_d[i];
		end
	end
end


//
endmodule
