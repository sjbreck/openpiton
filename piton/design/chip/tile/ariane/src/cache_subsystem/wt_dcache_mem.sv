// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Author: Michael Schaffner <schaffner@iis.ee.ethz.ch>, ETH Zurich
// Date: 13.09.2018
// Description: Memory arrays, arbiter and tag comparison for wb dcache.
//
//
// Notes: 1) all ports can trigger a readout of all ways, and the way where the tag hits is selected
//
//        2) only port0 can write full cache lines. higher ports are read only. also, port0 can only read the tag array,
//           and does not trigger a cache line readout.
//
//        3) the single word write port is a separate port without access to the tag memory.
//           these single word writes can interleave with read operations if they go to different
//           cacheline offsets, since each word offset is placed into a different SRAM bank.
//
//        4) Read ports with same priority are RR arbited. but high prio ports (rd_prio_i[port_nr] = '1b1) will stall
//           low prio ports (rd_prio_i[port_nr] = '1b0)

import ariane_pkg::*;
import wt_cache_pkg::*;

module wt_dcache_mem #(
  parameter bit          Axi64BitCompliant  = 1'b0, // set this to 1 when using in conjunction with 64bit AXI bus adapter
  parameter int unsigned NumPorts           = 3
) (
  input  logic                                              clk_i,
  input  logic                                              rst_ni,

  // ports
  input  logic  [NumPorts-1:0][DCACHE_TAG_WIDTH-1:0]        rd_tag_i,           // tag in - comes one cycle later
  input  logic  [NumPorts-1:0][DCACHE_CL_IDX_WIDTH-1:0]     rd_idx_i,
  input  logic  [NumPorts-1:0][DCACHE_OFFSET_WIDTH-1:0]     rd_off_i,
  input  logic  [NumPorts-1:0]                              rd_req_i,           // read the word at offset off_i[:3] in all ways
  input  logic  [NumPorts-1:0]                              rd_tag_only_i,      // only do a tag/valid lookup, no access to data arrays
  input  logic  [NumPorts-1:0]                              rd_prio_i,          // 0: low prio, 1: high prio
  output logic  [NumPorts-1:0]                              rd_ack_o,
  output logic                [DCACHE_SET_ASSOC-1:0]        rd_vld_bits_o,
  output logic                [DCACHE_SET_ASSOC-1:0]        rd_ever_hit_o,
  output logic                [DCACHE_SET_ASSOC-1:0]        rd_hit_oh_o,
  output logic        [$clog2(DCACHE_SET_ASSOC)-1:0]        rd_rep_way_o,        // use this way in case of miss
  output logic                                              rd_rep_way_vld_o,  // force the way to be the one used in replace
  output logic                [63:0]                        rd_data_o,

  // only available on port 0, uses address signals of port 0
  input  logic 		      [$clog2(DCACHE_SET_ASSOC)-1:0]      wr_sig_we_i,
  input  logic                                              write_signature_i,
  input  logic                [13:0]                        wr_cl_signature_i,
  input  logic                                              wr_cl_vld_i,
  input  logic                                              wr_cl_nc_i,         // noncacheable access
  input  logic                                              wr_cl_line_upgraded_i, //loads the rest of the line
  input  logic                [DCACHE_SET_ASSOC-1:0]        wr_cl_we_i,         // writes a full cacheline
  input  logic                [DCACHE_TAG_WIDTH-1:0]        wr_cl_tag_i,
  input  logic                [DCACHE_CL_IDX_WIDTH-1:0]     wr_cl_idx_i,
  input  logic                [DCACHE_OFFSET_WIDTH-1:0]     wr_cl_off_i,
  input  logic                [DCACHE_LINE_WIDTH-1:0]       wr_cl_data_i,
  input  logic                [DCACHE_LINE_WIDTH/8-1:0]     wr_cl_data_be_i,
  input  logic                [DCACHE_SET_ASSOC-1:0]        wr_vld_bits_i,

  // separate port for single word write, no tag access
  input  logic                [DCACHE_SET_ASSOC-1:0]        wr_req_i,           // write a single word to offset off_i[:3]
  output logic                                              wr_ack_o,
  input  logic                [DCACHE_CL_IDX_WIDTH-1:0]     wr_idx_i,
  input  logic                [DCACHE_OFFSET_WIDTH-1:0]     wr_off_i,
  input  logic                [63:0]                        wr_data_i,
  input  logic                [7:0]                         wr_data_be_i,

  // forwarded wbuffer
  input wbuffer_t             [DCACHE_WBUF_DEPTH-1:0]       wbuffer_data_i,

  //output to predictor
  output logic		      [3:0]  		            pred_outcome_o,
  output logic		      [13:0]			    pred_hit_shct_o, //signature that hitted
  output logic		      [3:0][13:0]    		    pred_miss_shct_o, //signature that missed

  //output to policies
  output logic						    hit_o,
  output logic		      [DCACHE_CL_IDX_WIDTH-1:0]	    hit_idx_o,
  output logic		      [$clog2(DCACHE_SET_ASSOC)-1:0]hit_way_o
  /*output logic						    lru_mshr_o,
  output logic		      [DCACHE_CL_IDX_WIDTH-1:0]	    lru_mshr_idx_o,
  output logic		      [$clog2(DCACHE_SET_ASSOC)-1:0]lru_mshr_way_o,*/

);

  logic [DCACHE_NUM_BANKS-1:0]                                  bank_req;
  logic [DCACHE_NUM_BANKS-1:0]                                  bank_we;
  logic [DCACHE_NUM_BANKS-1:0][DCACHE_SET_ASSOC-1:0][7:0]       bank_be;
  logic [DCACHE_NUM_BANKS-1:0][DCACHE_CL_IDX_WIDTH-1:0]         bank_idx;
  logic [DCACHE_CL_IDX_WIDTH-1:0]                               bank_idx_d, bank_idx_q;
  logic [DCACHE_OFFSET_WIDTH-1:0]                               bank_off_d, bank_off_q;

  logic [DCACHE_NUM_BANKS-1:0][DCACHE_SET_ASSOC-1:0][63:0]      bank_wdata;                   //
  logic [DCACHE_NUM_BANKS-1:0][DCACHE_SET_ASSOC-1:0][63:0]      bank_rdata;                   //
  logic [DCACHE_SET_ASSOC-1:0][63:0]                            rdata_cl;                     // selected word from each cacheline

  logic [DCACHE_TAG_WIDTH-1:0]                                  rd_tag;
  logic [DCACHE_SET_ASSOC-1:0]                                  vld_req;                      // bit enable for valid regs
  logic                                                         vld_we;                       // valid bits write enable
  logic [DCACHE_SET_ASSOC-1:0]                                  vld_wdata;                    // valid bits to write
  logic [DCACHE_SET_ASSOC-1:0][DCACHE_TAG_WIDTH-1:0]            tag_rdata;                    // these are the tags coming from the tagmem
  logic [DCACHE_NUM_WORDS-1:0][DCACHE_SET_ASSOC-1:0]            hit_q;                         // whether the line was hit or not

  logic                       [DCACHE_CL_IDX_WIDTH-1:0]         vld_addr;                     // valid bit

  logic [$clog2(NumPorts)-1:0]                                  vld_sel_d, vld_sel_q;

  logic [DCACHE_WBUF_DEPTH-1:0]                                 wbuffer_hit_oh;
  logic [7:0]                                                   wbuffer_be;
  logic [63:0]                                                  wbuffer_rdata, rdata;
  logic [63:0]                                                  wbuffer_cmp_addr;

  logic                                                         cmp_en_d, cmp_en_q;
  logic                       [DCACHE_CL_IDX_WIDTH-1:0]         vld_addr_q, rd_idx_q;
  logic                                                         rd_acked;
  logic [NumPorts-1:0]                                          bank_collision, rd_req_masked, rd_req_prio;

  localparam BANK_SIZE_BITS = 3; // a bank is 8 bytes
  localparam BANK_SEL_BITS = $clog2(DCACHE_NUM_BANKS);

///////////////////////////////////////////////////////
// Signature Array
// Signature is brought into register if
// there is a miss
///////////////////////////////////////////////////////
logic[13:0] sig_array_d [DCACHE_NUM_WORDS-1:0][DCACHE_SET_ASSOC-1:0];
logic[13:0] sig_array_q [DCACHE_NUM_WORDS-1:0][DCACHE_SET_ASSOC-1:0];
logic [13:0] signature;
assign signature = {wr_cl_idx_i[6:0],wr_cl_tag_i[6:0]};
//ff array of signatures

wire store_sig[DCACHE_NUM_WORDS-1:0][DCACHE_SET_ASSOC-1:0];
for(genvar i=0; i<DCACHE_NUM_WORDS; i++)begin: gen_idxs_comb
	for(genvar j=0; j<DCACHE_SET_ASSOC; j++)begin: gen_ways_comb
		assign store_sig[i][j] = write_signature_i && (wr_cl_idx_i==i) && (wr_sig_we_i==j);
		assign sig_array_d[i][j] = store_sig[i][j] ? wr_cl_signature_i : sig_array_q[i][j];
	end
end

for(genvar i=0; i<DCACHE_NUM_WORDS; i++)begin: gen_idxs
	for(genvar j=0; j<DCACHE_SET_ASSOC; j++)begin: gen_ways
		always_ff @(negedge rst_ni or posedge clk_i) begin: gen_reg_arrays
			if(!rst_ni)begin
				sig_array_q[i][j] <= '0;
			end
			else begin
				sig_array_q[i][j] <= sig_array_d[i][j];
			end
		end
	end
end

///////////////////////////////////////////////////////
// Outcome Array
// Outcome is changed to 1 when receiving a hit
// outcome is changed back to zero if there is a miss
///////////////////////////////////////////////////////
logic [$clog2(DCACHE_SET_ASSOC)-1:0]  rd_hit_idx;
assign hit_o = |rd_hit_oh_o;
assign hit_idx_o = vld_addr_q;
assign hit_way_o = rd_hit_idx;
logic outcome_d [DCACHE_NUM_WORDS-1:0][DCACHE_SET_ASSOC-1:0];
logic outcome_q [DCACHE_NUM_WORDS-1:0][DCACHE_SET_ASSOC-1:0];

logic update_outcome_on_hit[DCACHE_NUM_WORDS-1:0][DCACHE_SET_ASSOC-1:0];
logic update_outcome_on_miss[DCACHE_NUM_WORDS-1:0][DCACHE_SET_ASSOC-1:0];
for(genvar i=0; i<DCACHE_NUM_WORDS; i++)begin: gen_outcome_idxs_bool
	for(genvar j=0; j<DCACHE_SET_ASSOC; j++)begin: gen_ways_bool

		assign update_outcome_on_hit[i][j] = (hit_o) && (hit_way_o == j) && (hit_idx_o==i); 
		assign update_outcome_on_miss[i][j] = (wr_cl_vld_i && (wr_cl_idx_i==i) && 
							(wr_cl_we_i[j]))? 1'b1 : 1'b0;
		assign outcome_d[i][j] = update_outcome_on_hit[i][j] ? 1'b1 :
                            		(update_outcome_on_miss[i][j] ? 1'b0 : outcome_q[i][j]);
	end
end

for(genvar i=0; i<DCACHE_NUM_WORDS; i++)begin: gen_outcome_ff_idxs
	for(genvar j=0; j<DCACHE_SET_ASSOC; j++)begin: gen_outcome_ff_ways
		always_ff @(negedge rst_ni or posedge clk_i) begin: gen_outcome_ff_arrays
			if(!rst_ni)begin
				outcome_q[i][j] <= '0;
			end
			else begin
				outcome_q[i][j] <= outcome_d[i][j];
			end
		end
	end
end

////////////////////////////////////////////////////////////////
// Predictor Interface
// predictor reads the signatures and outcomes of all ways
// from the missed index
// because occassions like flush invalidates all ways in a set
///////////////////////////////////////////////////////////////

always_comb begin: output_to_predictor
	if(hit_o)begin
		pred_hit_shct_o = sig_array_q[hit_idx_o][hit_way_o];
	end
	else begin
		pred_hit_shct_o = '0;
	end

	if(write_signature_i)begin
		pred_miss_shct_o[0] = sig_array_q[wr_cl_idx_i][0];
		pred_miss_shct_o[1] = sig_array_q[wr_cl_idx_i][1];
		pred_miss_shct_o[2] = sig_array_q[wr_cl_idx_i][2];
		pred_miss_shct_o[3] = sig_array_q[wr_cl_idx_i][3];
		pred_outcome_o[0] = outcome_q[wr_cl_idx_i][0];
		pred_outcome_o[1] = outcome_q[wr_cl_idx_i][1];
		pred_outcome_o[2] = outcome_q[wr_cl_idx_i][2];
		pred_outcome_o[3] = outcome_q[wr_cl_idx_i][3];
	end
	else begin
		pred_miss_shct_o = '0;
		pred_outcome_o = '0;
	end
end

///////////////////////////////////////////////////////
// arbiter
///////////////////////////////////////////////////////

  // Priority is highest for lowest read port index
  //
  // SRAM bank mapping:
  //
  // Bank 0                   Bank 2
  // [way0, w0] [way1, w0] .. [way0, w1] [way1, w1] ..

  // byte enable mapping
  for (genvar k=0;k<DCACHE_NUM_BANKS;k++) begin : gen_bank
    for (genvar j=0;j<DCACHE_SET_ASSOC;j++) begin : gen_bank_way
      assign bank_be[k][j]   = (wr_cl_we_i[j] & wr_cl_vld_i)  ? wr_cl_data_be_i[k*8 +: 8] :
                               (wr_req_i[j]   & wr_ack_o)     ? wr_data_be_i              :
                                                                '0;

      assign bank_wdata[k][j] = (wr_cl_we_i[j] & wr_cl_vld_i) ?  wr_cl_data_i[k*64 +: 64] :
                                                                 wr_data_i;
    end
  end

  assign vld_wdata  = wr_vld_bits_i;
  assign vld_addr   = (wr_cl_vld_i) ? wr_cl_idx_i   : rd_idx_i[vld_sel_d];
  assign bank_idx_d = (wr_cl_vld_i) ? wr_cl_idx_i   : rd_idx_i[vld_sel_d];
  assign rd_tag     = rd_tag_i[vld_sel_q]; //delayed by one cycle //comes only from CPU
  assign bank_off_d = (wr_cl_vld_i) ? wr_cl_off_i   : rd_off_i[vld_sel_d];
  assign vld_req    = (wr_cl_vld_i) ? wr_cl_we_i    : (rd_acked) ? '1 : '0;
  wire [63:0] rd_paddr = {rd_tag, vld_addr_q, bank_off_q};

  // priority masking
  // disable low prio requests when any of the high prio reqs is present
  assign rd_req_prio   = rd_req_i & rd_prio_i;
  assign rd_req_masked = (|rd_req_prio) ? rd_req_prio : rd_req_i;

  logic rd_req;
  rr_arb_tree #(
    .NumIn     (NumPorts),
    .DataWidth (1)
  ) i_rr_arb_tree (
    .clk_i  (clk_i   ),
    .rst_ni (rst_ni  ),
    .flush_i('0      ),
    .rr_i   ('0      ),
    .req_i  (rd_req_masked ),
    .gnt_o  (rd_ack_o      ),
    .data_i ('0            ),
    .gnt_i  (~wr_cl_vld_i  ),
    .req_o  (rd_req        ),
    .data_o (              ),
    .idx_o  (vld_sel_d     )
  );

  assign rd_acked = rd_req & ~wr_cl_vld_i;

  always_comb begin : p_bank_req
    vld_we   = wr_cl_vld_i;
    bank_req = '0;
    wr_ack_o = '0;
    bank_we  = '0;
    bank_idx = '{default:wr_idx_i};

    for(int k=0; k<NumPorts; k++) begin
      bank_collision[k] = rd_off_i[k][DCACHE_OFFSET_WIDTH-1:BANK_SIZE_BITS] == wr_off_i[DCACHE_OFFSET_WIDTH-1:BANK_SIZE_BITS];
    end

    if(wr_cl_vld_i & |wr_cl_we_i) begin
      bank_req = '1;
      bank_we  = '1;
      bank_idx = '{default:wr_cl_idx_i};
    end else begin
      if(rd_acked) begin
        if(!rd_tag_only_i[vld_sel_d]) begin
          bank_req    = dcache_cl_bin2oh(rd_off_i[vld_sel_d][DCACHE_OFFSET_WIDTH-1:BANK_SIZE_BITS]);
          bank_idx[rd_off_i[vld_sel_d][DCACHE_OFFSET_WIDTH-1:BANK_SIZE_BITS]] = rd_idx_i[vld_sel_d];
        end
      end

      if(|wr_req_i) begin
        if(rd_tag_only_i[vld_sel_d] || !(rd_ack_o[vld_sel_d] && bank_collision[vld_sel_d])) begin
          wr_ack_o = 1'b1;
          bank_req |= dcache_cl_bin2oh(wr_off_i[DCACHE_OFFSET_WIDTH-1:BANK_SIZE_BITS]);
          bank_we   = dcache_cl_bin2oh(wr_off_i[DCACHE_OFFSET_WIDTH-1:BANK_SIZE_BITS]);
        end
      end
    end
  end

///////////////////////////////////////////////////////
// tag comparison, hit generatio, readoud muxes
///////////////////////////////////////////////////////

  logic [DCACHE_OFFSET_WIDTH-1:0]       wr_cl_off;
  logic [$clog2(DCACHE_WBUF_DEPTH)-1:0] wbuffer_hit_idx;

  assign cmp_en_d = (|vld_req) & ~vld_we;

  // word tag comparison in write buffer
  assign wbuffer_cmp_addr = (wr_cl_vld_i) ? {wr_cl_tag_i, wr_cl_idx_i, wr_cl_off_i} :
                                            {rd_tag, bank_idx_q, bank_off_q};

  wire [BANK_SEL_BITS-1:0] bank_sel = bank_off_q[DCACHE_OFFSET_WIDTH-1:BANK_SIZE_BITS];
  wire [BANK_SEL_BITS-1:0] wr_cl_bank_sel = wr_cl_off_i[DCACHE_OFFSET_WIDTH-1:BANK_SIZE_BITS];


  logic [DCACHE_SET_ASSOC*DCACHE_NUM_BANKS-1:0] rd_vld_bits;
  logic                [DCACHE_SET_ASSOC-1:0]   rd_tag_hit_oh;
  // hit generation
  for (genvar i=0;i<DCACHE_SET_ASSOC;i++) begin : gen_tag_cmpsel
    // tag comparison of ways >0
    assign rd_tag_hit_oh[i] = (rd_tag == tag_rdata[i]) && cmp_en_q;
    assign rd_hit_oh_o[i] = rd_tag_hit_oh[i] && rd_vld_bits[i*DCACHE_NUM_BANKS+bank_sel];
    assign rd_vld_bits_o[i] = |rd_vld_bits[i*DCACHE_NUM_BANKS+:DCACHE_NUM_BANKS];
    // byte offset mux of ways >0
    assign rdata_cl[i] = bank_rdata[bank_sel][i];
  end

  for(genvar k=0; k<DCACHE_WBUF_DEPTH; k++) begin : gen_wbuffer_hit
    assign wbuffer_hit_oh[k] = (|wbuffer_data_i[k].valid) & (wbuffer_data_i[k].wtag == (wbuffer_cmp_addr >> 3));
  end

  lzc #(
    .WIDTH ( DCACHE_WBUF_DEPTH )
  ) i_lzc_wbuffer_hit (
    .in_i    ( wbuffer_hit_oh   ),
    .cnt_o   ( wbuffer_hit_idx  ),
    .empty_o (                  )
  );
  wire rd_miss, rd_tag_miss;
  lzc #(
    .WIDTH ( DCACHE_SET_ASSOC )
  ) i_lzc_rd_hit (
    .in_i    ( rd_hit_oh_o  ),
    .cnt_o   ( rd_hit_idx   ),
    .empty_o ( rd_miss       )
  );

  lzc #(
    .WIDTH ( DCACHE_SET_ASSOC )
  ) i_lzc_rd_tag_hit (
    .in_i    ( rd_tag_hit_oh  ),
    .cnt_o   ( rd_rep_way_o   ),
    .empty_o ( rd_tag_miss    )
  );

 // we hardcode the way if there is a tag hit and one bank is valid already
 // if the bank that hits is the one we are looking up, then its a cache hit and the rep_way is ignored
  assign rd_rep_way_vld_o = !rd_tag_miss && rd_vld_bits_o[rd_rep_way_o];


  assign wbuffer_rdata = wbuffer_data_i[wbuffer_hit_idx].data;
  assign wbuffer_be    = (|wbuffer_hit_oh) ? wbuffer_data_i[wbuffer_hit_idx].valid : '0;

  if (Axi64BitCompliant) begin : gen_axi_off
      assign wr_cl_off     = (wr_cl_nc_i) ? '0 : wr_cl_bank_sel;
  end else begin  : gen_piton_off
      assign wr_cl_off     = wr_cl_bank_sel;
  end

  assign rdata         = (wr_cl_vld_i)  ? wr_cl_data_i[wr_cl_off*64 +: 64] :
                                          rdata_cl[rd_hit_idx];

  // overlay bytes that hit in the write buffer
  for(genvar k=0; k<8; k++) begin : gen_rd_data
    assign rd_data_o[8*k +: 8] = (wbuffer_be[k]) ? wbuffer_rdata[8*k +: 8] : rdata[8*k +: 8];
  end

///////////////////////////////////////////////////////
// memory arrays and regs
///////////////////////////////////////////////////////

  logic [DCACHE_TAG_WIDTH+DCACHE_NUM_BANKS-1:0] vld_tag_rdata [DCACHE_SET_ASSOC-1:0];

  for (genvar k = 0; k < DCACHE_NUM_BANKS; k++) begin : gen_data_banks
    // Data RAM
    sram #(
      .DATA_WIDTH ( ariane_pkg::DCACHE_SET_ASSOC * 64 ),
      .NUM_WORDS  ( wt_cache_pkg::DCACHE_NUM_WORDS    )
    ) i_data_sram (
      .clk_i      ( clk_i               ),
      .rst_ni     ( rst_ni              ),
      .req_i      ( bank_req   [k]      ),
      .we_i       ( bank_we    [k]      ),
      .addr_i     ( bank_idx   [k]      ),
      .wdata_i    ( bank_wdata [k]      ),
      .be_i       ( bank_be    [k]      ),
      .rdata_o    ( bank_rdata [k]      )
    );
  end

  // WE MODIFIED THE VALID BITS STORED TOGETHER WITH THE TAG, SO WE HAVE 2 VALID BITS, ONE PER BANK
  // BANKS_WRITE checks which banks are being loaded. Upgraded signals means that the line had a single bank valid
  // and it missed in the other one, that resulted in loading the rest of the line. We make sure in wt_dcache_missunit
  // that the miss writes to the same way where there was a tag hit, but a cache miss, due to the half line loading.
  wire [DCACHE_NUM_BANKS-1:0] banks_write = {wr_cl_data_be_i[8] || wr_cl_line_upgraded_i,
                                             wr_cl_data_be_i[0] || wr_cl_line_upgraded_i};
  for (genvar i = 0; i < DCACHE_SET_ASSOC; i++) begin : gen_tag_srams
    wire [DCACHE_NUM_BANKS-1:0] valid_bits = banks_write & {DCACHE_NUM_BANKS{vld_wdata[i]}};
    assign tag_rdata[i]     = vld_tag_rdata[i][DCACHE_TAG_WIDTH-1:0];
    assign rd_vld_bits[i*DCACHE_NUM_BANKS+:DCACHE_NUM_BANKS] = vld_tag_rdata[i][DCACHE_TAG_WIDTH+DCACHE_NUM_BANKS-1:DCACHE_TAG_WIDTH];
    assign rd_ever_hit_o[i] = hit_q[vld_addr_q][i];
    // Tag RAM
    sram #(
      // tag + valid bit
      .DATA_WIDTH ( ariane_pkg::DCACHE_TAG_WIDTH + DCACHE_NUM_BANKS ),
      .NUM_WORDS  ( wt_cache_pkg::DCACHE_NUM_WORDS   )
    ) i_tag_sram (
      .clk_i     ( clk_i               ),
      .rst_ni    ( rst_ni              ),
      .req_i     ( vld_req[i]          ),
      .we_i      ( vld_we              ),
      .addr_i    ( vld_addr            ),
      .wdata_i   ( {valid_bits, wr_cl_tag_i} ),
      .be_i      ( '1                  ),
      .rdata_o   ( vld_tag_rdata[i]    )
    );
    
    // WE STORE THE HITS TO SHOW IN THE MONITOR WHICH WAYS WERE EVER HIT
    for (genvar j = 0; j < DCACHE_NUM_WORDS; j++) begin : gen_hit_bits
      wire set_indexed = (j[DCACHE_CL_IDX_WIDTH-1:0] == vld_addr);
      wire set_indexed_q = (j[DCACHE_CL_IDX_WIDTH-1:0] == vld_addr_q);
      // Hit bits
      always_ff @(negedge rst_ni or posedge clk_i)
      if (!rst_ni) begin
        hit_q[j][i] <= 1'b0;
      end else begin
        hit_q[j][i] <= rd_hit_oh_o[i] && set_indexed_q || hit_q[j][i] && !(vld_we && vld_req[i] && set_indexed);
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : p_regs
    if(!rst_ni) begin
      bank_idx_q <= '0;
      bank_off_q <= '0;
      vld_sel_q  <= '0;
      cmp_en_q   <= '0;
      vld_addr_q <= '0;
    end else begin
      bank_idx_q <= bank_idx_d;
      bank_off_q <= bank_off_d;
      vld_sel_q  <= vld_sel_d ;
      cmp_en_q   <= cmp_en_d;
      vld_addr_q <= vld_addr;
    end
  end

///////////////////////////////////////////////////////
// assertions
///////////////////////////////////////////////////////

//pragma translate_off
`ifndef VERILATOR

  hit_hot1: assert property (
    @(posedge clk_i) disable iff (!rst_ni) &vld_req |-> !vld_we |=> $onehot0(rd_hit_oh_o))
      else $fatal(1,"[l1 dcache] rd_hit_oh_o signal must be hot1");

  word_write_hot1: assert property (
    @(posedge clk_i) disable iff (!rst_ni) wr_ack_o |-> $onehot0(wr_req_i))
      else $fatal(1,"[l1 dcache] wr_req_i signal must be hot1");

  wbuffer_hit_hot1: assert property (
    @(posedge clk_i) disable iff (!rst_ni) &vld_req |-> !vld_we |=> $onehot0(wbuffer_hit_oh))
      else $fatal(1,"[l1 dcache] wbuffer_hit_oh signal must be hot1");

  // this is only used for verification!
  logic [1:0]                                   vld_mirror[wt_cache_pkg::DCACHE_NUM_WORDS-1:0][ariane_pkg::DCACHE_SET_ASSOC-1:0];
  logic [ariane_pkg::DCACHE_TAG_WIDTH-1:0] tag_mirror[wt_cache_pkg::DCACHE_NUM_WORDS-1:0][ariane_pkg::DCACHE_SET_ASSOC-1:0];
  logic [ariane_pkg::DCACHE_SET_ASSOC-1:0] tag_write_duplicate_test;
  logic [31:0] bw_byte_count;
  wire [4:0] bw_add;
  assign bw_add = {1'b0, {4{wr_cl_data_be_i[0]}} & 4'd8} + {1'b0, {4{wr_cl_data_be_i[8]}} & 4'd8};
  
  // HERE WE ADDED BW_BYTE_COUNT TO COUNT BANDWIDTH BETWEEN ARIANE AND OPENPITON NETWORK
  always_ff @(posedge clk_i or negedge rst_ni) begin : p_mirror
    if(!rst_ni) begin
      vld_mirror <= '{default:'0};
      tag_mirror <= '{default:'0};
      bw_byte_count <= '{default:'0};
      
    end else begin
      if (vld_we) begin
        bw_byte_count <= bw_byte_count + bw_add; 
      end

      for (int i = 0; i < DCACHE_SET_ASSOC; i++) begin
        if(vld_req[i] & vld_we) begin
          vld_mirror[vld_addr][i] <= ({wr_cl_data_be_i[8], wr_cl_data_be_i[0]} | {2{wr_cl_line_upgraded_i}})
                                       & {2{vld_wdata[i]}};
          tag_mirror[vld_addr][i] <= wr_cl_tag_i;
        end
      end
    end
  end

  for (genvar i = 0; i < DCACHE_SET_ASSOC; i++) begin : gen_tag_dubl_test
      assign tag_write_duplicate_test[i] = (tag_mirror[vld_addr][i] == wr_cl_tag_i) & vld_mirror[vld_addr][i][wr_cl_bank_sel] & (|vld_wdata);
  end

  tag_write_duplicate: assert property (
    @(posedge clk_i) disable iff (!rst_ni) |vld_req |-> vld_we |-> !(|tag_write_duplicate_test))
      else $fatal(1,"[l1 dcache] cannot allocate a CL that is already present in the cache");

`endif
//pragma translate_on

endmodule // wt_dcache_mem
