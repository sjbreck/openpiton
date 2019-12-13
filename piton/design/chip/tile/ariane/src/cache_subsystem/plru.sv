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
    parameter WIDTH = 8
)(
    input  logic                      clk_i,
    input  logic                      rst_ni,
    input  logic                      en_i,
    output logic [WIDTH-1:0]          refill_way_oh,
    output logic [$clog2(WIDTH)-1:0]  refill_way_bin
);

    localparam LOG_WIDTH = $clog2(WIDTH);

  ///////////////////////
  // PLRU for shared tags
  ///////////////////////
  generate
  for (j = TAG_BITS; j > 0; j--)
    begin: evicted_stag_gen
      if(j == TAG_BITS) begin : j_eq_stag_bits_gen
        assign eviction_candidate_stag_index[j - 1] = !( |evictable_stag[0 +: TAGS/2] ) || ( |evictable_stag[L1_N_STAGS/2 +: L1_N_STAGS/2] && !stag_plru_tree_r[0] );
      end else begin : j_neq_stag_bits_gen
        assign eviction_candidate_stag_index[j - 1] = ( !( |evictable_stag[eviction_candidate_stag_index[TAG_BITS - 1 : j] * (1 << j)                  +: 1 << (j - 1)] ) ) ||
                                                      (    |evictable_stag[eviction_candidate_stag_index[TAG_BITS - 1 : j] * (1 << j) + (1 << (j - 1)) +: 1 << (j - 1)] &&
                                                      !stag_plru_tree_r[TAG_BITS'(eviction_candidate_stag_index[L1_N_STAG_BITS - 1 : j]) + L1_N_STAG_BITS'( L1_N_STAGS / (1 << j) - 1)] );
      end
    end
  endgenerate

  generate
  for (j = 0; j < TAG_BITS; j++) begin: stag_plru_tree_gen
    for(k = 0; k < (1 << j); k++) begin: stag_plru_tree_level_gen
      if((k == 0) && (j == 0)) begin : stag_k_and_j_eq_zero_gen
        // if a high order way was unlocked, make the tree point to the low order ways
        assign stag_plru_tree_nxt[0] = eviction_candidate_stag_index[TAG_BITS - 1];
      end else begin : stag_k_or_j_neq_zero_gen
        assign stag_plru_tree_nxt[(1 << j) + k - 1] = eviction_candidate_stag_index[TAG_BITS - 1 : L1_N_STAG_BITS - j] == k[j - 1 : 0] ?
                                                      eviction_candidate_stag_index[TAG_BITS - 1 - j] :
                                                      stag_plru_tree_r[(1 << j) + k - 1];
      end
    end
  end
  endgenerate

  always_ff @(negedge reset_n or posedge clk) begin
    if (!reset_n) begin
      stag_plru_tree_r <= {TAGS-1{1'b0}};
    end else if (en_i) begin
      stag_plru_tree_r <= stag_plru_tree_nxt;
    end
  end


 endmodule
