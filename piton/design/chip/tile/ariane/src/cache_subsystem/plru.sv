// Author: Marcelo Orenes Vera - Princeton University
// Author: Florian Zaruba, ETH Zurich
// Date: 12.11.2019
// Description: PLRU Unit

// --------------
// PLRU
// --------------
//
// Description: Shift register
//
module plru #(
    parameter WAYS = 8
)(
    input  logic                      clk,
    input  logic                      reset_n,
    input  logic                      en,
    input  logic [WAYS-1:0]          evictable_way,
    output logic [$clog2(WAYS)-1:0]  evict_way_idx
);

    localparam WAY_BITS = $clog2(WAYS);
    
  ///////////////////////
  // PLRU for shared ways
  ///////////////////////
  logic [WAY_BITS-1:0] eviction_candidate_way_index;
  logic [WAY_BITS-1:0] unmasked_candidate_way_index;
  logic [WAYS-1  -1:0] plru_tree_nxt;
  logic [WAYS-1  -1:0] plru_tree_r;
  assign evict_way_idx = |evictable_way ? eviction_candidate_way_index : unmasked_candidate_way_index;
  genvar j,k;
  generate
  for (j = WAY_BITS; j > 0; j--)
    begin: evicted_way_gen
      if(j == WAY_BITS) begin : j_eq_way_bits_gen
        assign eviction_candidate_way_index[j - 1] = !( |evictable_way[0 +: WAYS/2] ) || ( |evictable_way[WAYS/2 +: WAYS/2] && !plru_tree_r[0] );
        assign unmasked_candidate_way_index[j - 1] = !plru_tree_r[0];
      end else begin : j_neq_way_bits_gen
        assign eviction_candidate_way_index[j - 1] = ( !( |evictable_way[eviction_candidate_way_index[WAY_BITS - 1 : j] * (1 << j)                  +: 1 << (j - 1)] ) ) ||
                                                      (    |evictable_way[eviction_candidate_way_index[WAY_BITS - 1 : j] * (1 << j) + (1 << (j - 1)) +: 1 << (j - 1)] &&
                                                      !plru_tree_r[WAY_BITS'(eviction_candidate_way_index[WAY_BITS - 1 : j]) + WAY_BITS'( WAYS / (1 << j) - 1)] );
        assign unmasked_candidate_way_index[j - 1] = !plru_tree_r[WAY_BITS'(unmasked_candidate_way_index[WAY_BITS - 1 : j]) + WAY_BITS'( WAYS / (1 << j) - 1)];

      end
    end
  endgenerate

  generate
  for (j = 0; j < WAY_BITS; j++) begin: plru_tree_gen
    for(k = 0; k < (1 << j); k++) begin: plru_tree_level_gen
      if((k == 0) && (j == 0)) begin : way_k_and_j_eq_zero_gen
        // if a high order way was unlocked, make the tree point to the low order ways
        assign plru_tree_nxt[0] = evict_way_idx[WAY_BITS - 1];
      end else begin : way_k_or_j_neq_zero_gen
        assign plru_tree_nxt[(1 << j) + k - 1] = evict_way_idx[WAY_BITS - 1 : WAY_BITS - j] == k[j - 1 : 0] ?
                                                      evict_way_idx[WAY_BITS - 1 - j] :
                                                      plru_tree_r[(1 << j) + k - 1];
      end
    end
  end
  endgenerate

  always_ff @(negedge reset_n or posedge clk)
  if (!reset_n) begin
    plru_tree_r <= {WAYS-1{1'b0}};
  end else if (en) begin
    plru_tree_r <= plru_tree_nxt;
  end


 endmodule
