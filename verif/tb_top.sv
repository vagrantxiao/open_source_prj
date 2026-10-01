`timescale 1ns/1ps

// Co-simulation testbench instantiating axi2stream_v1_0 and datamover_m1_m_axi.
// axi2stream_v1_0 exposes 5 FIO ports (wr_addr, wr_data, rd_addr, rd_data, wr_resp)
// which are hooked directly to the matching channels of datamover_m1_m_axi.
// A simple 32-bit AXI4 memory model closes the m_axi_m1 loop.

module tb_top;

localparam int AXIL_DW         = 32;
localparam int AXIL_AW         = 6;
localparam int MEM_DEPTH_WORDS = 2048;   // 2048 x 64B
localparam int BURST_WORDS     = 1024;   // 1024 x 64B user-side burst
localparam int TB_TIMEOUT_CYCLES = 2_000_000;

// axi2stream register map (word aligned, S00_AXI uses ADDR_LSB=2)
localparam logic [AXIL_AW-1:0] ADDR_WR_ADDR = 6'h00; // slv_reg0
localparam logic [AXIL_AW-1:0] ADDR_WR_DATA = 6'h04; // slv_reg1
localparam logic [AXIL_AW-1:0] ADDR_RD_ADDR = 6'h08; // slv_reg2
localparam logic [AXIL_AW-1:0] ADDR_CTRL    = 6'h1c; // slv_reg7
localparam logic [AXIL_AW-1:0] ADDR_RD_DATA = 6'h2c; // slv_reg11
localparam logic [AXIL_AW-1:0] ADDR_WR_RESP = 6'h30; // slv_reg12
localparam logic [AXIL_AW-1:0] ADDR_STATUS  = 6'h3c; // slv_reg15

// Control (slv_reg7) bit layout: see axi2stream_v1_0.v user logic.
localparam int CTRL_WINC_WR_ADDR = 0;
localparam int CTRL_WINC_WR_DATA = 2;
localparam int CTRL_WINC_RD_ADDR = 4;
localparam int CTRL_RINC_RD_DATA = 7;
localparam int CTRL_RINC_WR_RESP = 9;
localparam int CTRL_AP_START     = 14;

// Status (slv_reg15) bit layout:
// bit0=rempty_wr_addr, bit1=wfull_wr_addr,
// bit2=rempty_wr_data, bit3=wfull_wr_data,
// bit4=rempty_rd_addr, bit5=wfull_rd_addr,
// bit6=rempty_rd_data, bit7=wfull_rd_data,
// bit8=rempty_wr_resp, bit9=wfull_wr_resp
localparam int ST_WFULL_WR_ADDR = 1;
localparam int ST_WFULL_WR_DATA = 3;
localparam int ST_WFULL_RD_ADDR = 5;
localparam int ST_REMTY_RD_DATA = 6;
localparam int ST_REMTY_WR_RESP = 8;

// ---------------- clock / reset ----------------
logic ap_clk   = 1'b0;
logic ap_rst_n = 1'b0;
always #5 ap_clk = ~ap_clk;

// ---------------- AXI-Lite master to axi2stream ----------------
logic [AXIL_AW-1:0]        s00_axi_awaddr;
logic [2:0]                s00_axi_awprot;
logic                      s00_axi_awvalid;
logic                      s00_axi_awready;
logic [AXIL_DW-1:0]        s00_axi_wdata;
logic [(AXIL_DW/8)-1:0]    s00_axi_wstrb;
logic                      s00_axi_wvalid;
logic                      s00_axi_wready;
logic [1:0]                s00_axi_bresp;
logic                      s00_axi_bvalid;
logic                      s00_axi_bready;
logic [AXIL_AW-1:0]        s00_axi_araddr;
logic [2:0]                s00_axi_arprot;
logic                      s00_axi_arvalid;
logic                      s00_axi_arready;
logic [AXIL_DW-1:0]        s00_axi_rdata;
logic [1:0]                s00_axi_rresp;
logic                      s00_axi_rvalid;
logic                      s00_axi_rready;

// ---------------- 5 FIO channels between axi2stream and datamover ----------------
logic [31:0] fio_wr_addr;
logic        fio_wr_addr_valid;
logic        fio_wr_addr_ready;

logic [31:0] fio_wr_data;
logic        fio_wr_data_valid;
logic        fio_wr_data_ready;

logic [31:0] fio_rd_addr;
logic        fio_rd_addr_valid;
logic        fio_rd_addr_ready;

logic [31:0] fio_rd_data;
logic        fio_rd_data_valid;
logic        fio_rd_data_ready;

logic [31:0] fio_wr_resp;
logic        fio_wr_resp_valid;
logic        fio_wr_resp_ready;

logic        ap_start_unused;

// ---------------- datamover side helper signals ----------------
logic [31:0]  wr_addr_len;
logic [31:0]  rd_addr_len;
logic [63:0]  wr_data_be;
logic [5:0]   i_rfifonum;

assign wr_addr_len = BURST_WORDS;        // 1024 x 64B
assign rd_addr_len = BURST_WORDS;
assign wr_data_be  = '1;                 // all byte lanes enabled

// Width-adapt FIO 32b <-> datamover 512b user data.
logic [511:0] dm_wr_data_512;
logic [511:0] dm_rd_data_512;
assign dm_wr_data_512 = {480'd0, fio_wr_data};  // pad MSBs to 0

// ---------------- m_axi_m1 bus wires ----------------
logic [0:0]   m_axi_m1_AWID;
logic [31:0]  m_axi_m1_AWADDR;
logic [7:0]   m_axi_m1_AWLEN;
logic [2:0]   m_axi_m1_AWSIZE;
logic [1:0]   m_axi_m1_AWBURST;
logic [1:0]   m_axi_m1_AWLOCK;
logic [3:0]   m_axi_m1_AWCACHE;
logic [2:0]   m_axi_m1_AWPROT;
logic [3:0]   m_axi_m1_AWQOS;
logic [3:0]   m_axi_m1_AWREGION;
logic [0:0]   m_axi_m1_AWUSER;
logic         m_axi_m1_AWVALID;
logic         m_axi_m1_AWREADY;
logic [0:0]   m_axi_m1_WID;
logic [511:0] m_axi_m1_WDATA;
logic [63:0]  m_axi_m1_WSTRB;
logic         m_axi_m1_WLAST;
logic [0:0]   m_axi_m1_WUSER;
logic         m_axi_m1_WVALID;
logic         m_axi_m1_WREADY;
logic [0:0]   m_axi_m1_BID;
logic [1:0]   m_axi_m1_BRESP;
logic [0:0]   m_axi_m1_BUSER;
logic         m_axi_m1_BVALID;
logic         m_axi_m1_BREADY;
logic [0:0]   m_axi_m1_ARID;
logic [31:0]  m_axi_m1_ARADDR;
logic [7:0]   m_axi_m1_ARLEN;
logic [2:0]   m_axi_m1_ARSIZE;
logic [1:0]   m_axi_m1_ARBURST;
logic [1:0]   m_axi_m1_ARLOCK;
logic [3:0]   m_axi_m1_ARCACHE;
logic [2:0]   m_axi_m1_ARPROT;
logic [3:0]   m_axi_m1_ARQOS;
logic [3:0]   m_axi_m1_ARREGION;
logic [0:0]   m_axi_m1_ARUSER;
logic         m_axi_m1_ARVALID;
logic         m_axi_m1_ARREADY;
logic [0:0]   m_axi_m1_RID;
logic [511:0] m_axi_m1_RDATA;
logic [1:0]   m_axi_m1_RRESP;
logic         m_axi_m1_RLAST;
logic [0:0]   m_axi_m1_RUSER;
logic         m_axi_m1_RVALID;
logic         m_axi_m1_RREADY;

// Datamover internal channel wires
logic         dm_rd_data_valid;
logic         dm_rd_data_ready;
logic         dm_wr_resp_valid;
logic         dm_wr_resp_ready;

// Connect datamover <-> axi2stream FIO ports.
// Only take the LSB 32b of the 512b read-data word for FIO.
assign fio_rd_data       = dm_rd_data_512[31:0];
assign fio_rd_data_valid = dm_rd_data_valid;
assign dm_rd_data_ready  = fio_rd_data_ready;

assign fio_wr_resp       = 32'h1;
assign fio_wr_resp_valid = dm_wr_resp_valid;
assign dm_wr_resp_ready  = fio_wr_resp_ready;

// ---------------- axi2stream_v1_0 instance ----------------
axi2stream_v1_0 #(
  .C_S00_AXI_DATA_WIDTH(AXIL_DW),
  .C_S00_AXI_ADDR_WIDTH(AXIL_AW)
) u_axi2stream (
  .ap_start        (ap_start_unused),

  .fio_wr_addr      (fio_wr_addr),
  .fio_wr_addr_valid(fio_wr_addr_valid),
  .fio_wr_addr_ready(fio_wr_addr_ready),

  .fio_wr_data      (fio_wr_data),
  .fio_wr_data_valid(fio_wr_data_valid),
  .fio_wr_data_ready(fio_wr_data_ready),

  .fio_rd_addr      (fio_rd_addr),
  .fio_rd_addr_valid(fio_rd_addr_valid),
  .fio_rd_addr_ready(fio_rd_addr_ready),

  .fio_rd_data      (fio_rd_data),
  .fio_rd_data_valid(fio_rd_data_valid),
  .fio_rd_data_ready(fio_rd_data_ready),

  .fio_wr_resp      (fio_wr_resp),
  .fio_wr_resp_valid(fio_wr_resp_valid),
  .fio_wr_resp_ready(fio_wr_resp_ready),

  .s00_axi_aclk    (ap_clk),
  .s00_axi_aresetn (ap_rst_n),
  .s00_axi_awaddr  (s00_axi_awaddr),
  .s00_axi_awprot  (s00_axi_awprot),
  .s00_axi_awvalid (s00_axi_awvalid),
  .s00_axi_awready (s00_axi_awready),
  .s00_axi_wdata   (s00_axi_wdata),
  .s00_axi_wstrb   (s00_axi_wstrb),
  .s00_axi_wvalid  (s00_axi_wvalid),
  .s00_axi_wready  (s00_axi_wready),
  .s00_axi_bresp   (s00_axi_bresp),
  .s00_axi_bvalid  (s00_axi_bvalid),
  .s00_axi_bready  (s00_axi_bready),
  .s00_axi_araddr  (s00_axi_araddr),
  .s00_axi_arprot  (s00_axi_arprot),
  .s00_axi_arvalid (s00_axi_arvalid),
  .s00_axi_arready (s00_axi_arready),
  .s00_axi_rdata   (s00_axi_rdata),
  .s00_axi_rresp   (s00_axi_rresp),
  .s00_axi_rvalid  (s00_axi_rvalid),
  .s00_axi_rready  (s00_axi_rready)
);

// ---------------- datamover_m1_m_axi instance ----------------
datamover_m1_m_axi u_datamover (
  .ACLK   (ap_clk),
  .ARESET (~ap_rst_n),
  .ACLK_EN(1'b1),

  .m_axi_m1_AWID    (m_axi_m1_AWID),
  .m_axi_m1_AWADDR  (m_axi_m1_AWADDR),
  .m_axi_m1_AWLEN   (m_axi_m1_AWLEN),
  .m_axi_m1_AWSIZE  (m_axi_m1_AWSIZE),
  .m_axi_m1_AWBURST (m_axi_m1_AWBURST),
  .m_axi_m1_AWLOCK  (m_axi_m1_AWLOCK),
  .m_axi_m1_AWCACHE (m_axi_m1_AWCACHE),
  .m_axi_m1_AWPROT  (m_axi_m1_AWPROT),
  .m_axi_m1_AWQOS   (m_axi_m1_AWQOS),
  .m_axi_m1_AWREGION(m_axi_m1_AWREGION),
  .m_axi_m1_AWUSER  (m_axi_m1_AWUSER),
  .m_axi_m1_AWVALID (m_axi_m1_AWVALID),
  .m_axi_m1_AWREADY (m_axi_m1_AWREADY),

  .m_axi_m1_WID    (m_axi_m1_WID),
  .m_axi_m1_WDATA  (m_axi_m1_WDATA),
  .m_axi_m1_WSTRB  (m_axi_m1_WSTRB),
  .m_axi_m1_WLAST  (m_axi_m1_WLAST),
  .m_axi_m1_WUSER  (m_axi_m1_WUSER),
  .m_axi_m1_WVALID (m_axi_m1_WVALID),
  .m_axi_m1_WREADY (m_axi_m1_WREADY),

  .m_axi_m1_BID    (m_axi_m1_BID),
  .m_axi_m1_BRESP  (m_axi_m1_BRESP),
  .m_axi_m1_BUSER  (m_axi_m1_BUSER),
  .m_axi_m1_BVALID (m_axi_m1_BVALID),
  .m_axi_m1_BREADY (m_axi_m1_BREADY),

  .m_axi_m1_ARID    (m_axi_m1_ARID),
  .m_axi_m1_ARADDR  (m_axi_m1_ARADDR),
  .m_axi_m1_ARLEN   (m_axi_m1_ARLEN),
  .m_axi_m1_ARSIZE  (m_axi_m1_ARSIZE),
  .m_axi_m1_ARBURST (m_axi_m1_ARBURST),
  .m_axi_m1_ARLOCK  (m_axi_m1_ARLOCK),
  .m_axi_m1_ARCACHE (m_axi_m1_ARCACHE),
  .m_axi_m1_ARPROT  (m_axi_m1_ARPROT),
  .m_axi_m1_ARQOS   (m_axi_m1_ARQOS),
  .m_axi_m1_ARREGION(m_axi_m1_ARREGION),
  .m_axi_m1_ARUSER  (m_axi_m1_ARUSER),
  .m_axi_m1_ARVALID (m_axi_m1_ARVALID),
  .m_axi_m1_ARREADY (m_axi_m1_ARREADY),

  .m_axi_m1_RID    (m_axi_m1_RID),
  .m_axi_m1_RDATA  (m_axi_m1_RDATA),
  .m_axi_m1_RRESP  (m_axi_m1_RRESP),
  .m_axi_m1_RLAST  (m_axi_m1_RLAST),
  .m_axi_m1_RUSER  (m_axi_m1_RUSER),
  .m_axi_m1_RVALID (m_axi_m1_RVALID),
  .m_axi_m1_RREADY (m_axi_m1_RREADY),

  .wr_addr      (fio_wr_addr),
  .wr_addr_len  (wr_addr_len),
  .wr_addr_valid(fio_wr_addr_valid),
  .wr_addr_ready(fio_wr_addr_ready),

  .wr_data      (dm_wr_data_512),
  .wr_data_be   (wr_data_be),
  .wr_data_valid(fio_wr_data_valid),
  .wr_data_ready(fio_wr_data_ready),

  .wr_resp_valid(dm_wr_resp_valid),
  .wr_resp_ready(dm_wr_resp_ready),

  .rd_addr      (fio_rd_addr),
  .rd_addr_len  (rd_addr_len),
  .rd_addr_valid(fio_rd_addr_valid),
  .rd_addr_ready(fio_rd_addr_ready),

  .rd_data      (dm_rd_data_512),
  .rd_data_valid(dm_rd_data_valid),
  .rd_data_ready(dm_rd_data_ready),

  .I_RFIFONUM(i_rfifonum)
);

// ---------------- Simple 32-bit AXI4 memory model ----------------
axi_mem_model #(
  .ADDR_WIDTH (32),
  .DATA_WIDTH (512),
  .ID_WIDTH   (1),
  .DEPTH_WORDS(MEM_DEPTH_WORDS)
) u_m1_mem (
  .clk    (ap_clk),
  .rst    (~ap_rst_n),
  .awvalid(m_axi_m1_AWVALID),
  .awready(m_axi_m1_AWREADY),
  .awaddr (m_axi_m1_AWADDR),
  .awid   (m_axi_m1_AWID),
  .awlen  (m_axi_m1_AWLEN),
  .awsize (m_axi_m1_AWSIZE),
  .awburst(m_axi_m1_AWBURST),
  .awlock (m_axi_m1_AWLOCK),
  .awcache(m_axi_m1_AWCACHE),
  .awprot (m_axi_m1_AWPROT),
  .awqos  (m_axi_m1_AWQOS),
  .awregion(m_axi_m1_AWREGION),
  .awuser (m_axi_m1_AWUSER),
  .wvalid (m_axi_m1_WVALID),
  .wready (m_axi_m1_WREADY),
  .wdata  (m_axi_m1_WDATA),
  .wstrb  (m_axi_m1_WSTRB),
  .wlast  (m_axi_m1_WLAST),
  .wid    (m_axi_m1_WID),
  .wuser  (m_axi_m1_WUSER),
  .bvalid (m_axi_m1_BVALID),
  .bready (m_axi_m1_BREADY),
  .bresp  (m_axi_m1_BRESP),
  .bid    (m_axi_m1_BID),
  .buser  (m_axi_m1_BUSER),
  .arvalid(m_axi_m1_ARVALID),
  .arready(m_axi_m1_ARREADY),
  .araddr (m_axi_m1_ARADDR),
  .arid   (m_axi_m1_ARID),
  .arlen  (m_axi_m1_ARLEN),
  .arsize (m_axi_m1_ARSIZE),
  .arburst(m_axi_m1_ARBURST),
  .arlock (m_axi_m1_ARLOCK),
  .arcache(m_axi_m1_ARCACHE),
  .arprot (m_axi_m1_ARPROT),
  .arqos  (m_axi_m1_ARQOS),
  .arregion(m_axi_m1_ARREGION),
  .aruser (m_axi_m1_ARUSER),
  .rvalid (m_axi_m1_RVALID),
  .rready (m_axi_m1_RREADY),
  .rdata  (m_axi_m1_RDATA),
  .rlast  (m_axi_m1_RLAST),
  .rid    (m_axi_m1_RID),
  .ruser  (m_axi_m1_RUSER),
  .rresp  (m_axi_m1_RRESP)
);

// ---------------- Test control ----------------
logic [31:0] ctrl_shadow;
logic [31:0] tmp_data;
logic [31:0] readback_data;
logic [31:0] wr_resp_data;
integer i;

initial begin : tb_watchdog
  repeat (TB_TIMEOUT_CYCLES) @(posedge ap_clk);
  $fatal(1, "[FAIL] tb_top timeout after %0d cycles", TB_TIMEOUT_CYCLES);
end

task automatic axil_write(input logic [AXIL_AW-1:0] addr, input logic [31:0] data);
begin
  @(posedge ap_clk);
  s00_axi_awaddr  <= addr;
  s00_axi_awprot  <= 3'b000;
  s00_axi_awvalid <= 1'b1;
  s00_axi_wdata   <= data;
  s00_axi_wstrb   <= 4'hF;
  s00_axi_wvalid  <= 1'b1;
  s00_axi_bready  <= 1'b1;
  do @(posedge ap_clk);
  while (!(s00_axi_awready && s00_axi_wready));
  s00_axi_awvalid <= 1'b0;
  s00_axi_wvalid  <= 1'b0;
  while (!s00_axi_bvalid) @(posedge ap_clk);
  @(posedge ap_clk);
  s00_axi_bready  <= 1'b0;
end
endtask

task automatic axil_read(input logic [AXIL_AW-1:0] addr, output logic [31:0] data);
begin
  @(posedge ap_clk);
  s00_axi_araddr  <= addr;
  s00_axi_arprot  <= 3'b000;
  s00_axi_arvalid <= 1'b1;
  while (!s00_axi_arready) @(posedge ap_clk);
  @(posedge ap_clk);
  s00_axi_arvalid <= 1'b0;

  s00_axi_rready  <= 1'b1;
  while (!s00_axi_rvalid) @(posedge ap_clk);
  data = s00_axi_rdata;
  @(posedge ap_clk);
  s00_axi_rready  <= 1'b0;
end
endtask

task automatic ctrl_toggle_bit(input int bit_idx);
begin
  ctrl_shadow = ctrl_shadow ^ (32'h1 << bit_idx);
  axil_write(ADDR_CTRL, ctrl_shadow);
end
endtask

task automatic fifo_push(
  input logic [AXIL_AW-1:0] data_addr,
  input int                 winc_bit,
  input logic [31:0]        data
);
begin
  axil_write(data_addr, data);
  ctrl_toggle_bit(winc_bit);
end
endtask

task automatic wait_not_empty(input int rempty_bit);
  int t;
begin
  t = 0;
  while (1) begin
    axil_read(ADDR_STATUS, tmp_data);
    if (tmp_data[rempty_bit] == 1'b0) break;
    t = t + 1;
    if (t > 200000) $fatal(1, "[FAIL] wait_not_empty timeout bit=%0d", rempty_bit);
  end
end
endtask

task automatic wait_not_full(input int wfull_bit);
  int t;
begin
  t = 0;
  while (1) begin
    axil_read(ADDR_STATUS, tmp_data);
    if (tmp_data[wfull_bit] == 1'b0) break;
    t = t + 1;
    if (t > 200000) $fatal(1, "[FAIL] wait_not_full timeout bit=%0d", wfull_bit);
  end
end
endtask

task automatic fifo_pop(
  input logic [AXIL_AW-1:0] data_addr,
  input int                 rinc_bit,
  input int                 rempty_bit,
  output logic [31:0]       data
);
begin
  wait_not_empty(rempty_bit);
  // Pulse rinc first; SynFIFO latches rdata on rinc so the slv_reg
  // readback becomes valid only after the pulse.
  ctrl_toggle_bit(rinc_bit);
  // Allow a couple of cycles for rdata to propagate.
  repeat (2) @(posedge ap_clk);
  axil_read(data_addr, data);
end
endtask

initial begin
  s00_axi_awaddr  = '0;
  s00_axi_awprot  = '0;
  s00_axi_awvalid = 1'b0;
  s00_axi_wdata   = '0;
  s00_axi_wstrb   = '0;
  s00_axi_wvalid  = 1'b0;
  s00_axi_bready  = 1'b0;
  s00_axi_araddr  = '0;
  s00_axi_arprot  = '0;
  s00_axi_arvalid = 1'b0;
  s00_axi_rready  = 1'b0;
  ctrl_shadow     = '0;

  repeat (20) @(posedge ap_clk);
  ap_rst_n = 1'b1;
  repeat (10) @(posedge ap_clk);

  for (i = 0; i < MEM_DEPTH_WORDS; i = i + 1) begin
    u_m1_mem.mem[i] = '0;
  end

  // Assert ap_start in control register.
  ctrl_shadow[CTRL_AP_START] = 1'b1;
  axil_write(ADDR_CTRL, ctrl_shadow);

  // -------- WRITE phase: 1024 x 64B --------
  $display("[CO-SIM] WRITE phase: %0d x 64B", BURST_WORDS);
  wait_not_full(ST_WFULL_WR_ADDR);
  fifo_push(ADDR_WR_ADDR, CTRL_WINC_WR_ADDR, 32'd0);
  for (i = 0; i < BURST_WORDS; i = i + 1) begin
    wait_not_full(ST_WFULL_WR_DATA);
    fifo_push(ADDR_WR_DATA, CTRL_WINC_WR_DATA, 32'hA000_0000 + i);
  end
  fifo_pop(ADDR_WR_RESP, CTRL_RINC_WR_RESP, ST_REMTY_WR_RESP, wr_resp_data);
  $display("[CO-SIM] WRITE done. wr_resp=0x%08x", wr_resp_data);

  // -------- READ phase: 1024 x 64B --------
  $display("[CO-SIM] READ phase: %0d x 64B", BURST_WORDS);
  wait_not_full(ST_WFULL_RD_ADDR);
  fifo_push(ADDR_RD_ADDR, CTRL_WINC_RD_ADDR, 32'd0);
  for (i = 0; i < BURST_WORDS; i = i + 1) begin
    fifo_pop(ADDR_RD_DATA, CTRL_RINC_RD_DATA, ST_REMTY_RD_DATA, readback_data);
    if (readback_data !== (32'hA000_0000 + i)) begin
      $fatal(1, "[FAIL] rd mismatch @%0d exp=0x%08x act=0x%08x",
             i, 32'hA000_0000 + i, readback_data);
    end
  end
  $display("[CO-SIM] READ done. last rd_data=0x%08x", readback_data);

  $display("[PASS] axi2stream_v1_0 <-> datamover_m1_m_axi 1024x64B co-sim OK");
  $finish;
end

endmodule


// ============================================================================
// Simple AXI4 memory model (32-bit).  Supports 1-beat read/write bursts used
// by the co-simulation.  Address field is interpreted as a byte address and
// shifted by 2 to index the word memory.
// ============================================================================
module axi_mem_model #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32,
  parameter int ID_WIDTH   = 1,
  parameter int DEPTH_WORDS= 1024
) (
  input  logic                     clk,
  input  logic                     rst,

  input  logic                     awvalid,
  output logic                     awready,
  input  logic [ADDR_WIDTH-1:0]    awaddr,
  input  logic [ID_WIDTH-1:0]      awid,
  input  logic [7:0]               awlen,
  input  logic [2:0]               awsize,
  input  logic [1:0]               awburst,
  input  logic [1:0]               awlock,
  input  logic [3:0]               awcache,
  input  logic [2:0]               awprot,
  input  logic [3:0]               awqos,
  input  logic [3:0]               awregion,
  input  logic [0:0]               awuser,

  input  logic                     wvalid,
  output logic                     wready,
  input  logic [DATA_WIDTH-1:0]    wdata,
  input  logic [DATA_WIDTH/8-1:0]  wstrb,
  input  logic                     wlast,
  input  logic [ID_WIDTH-1:0]      wid,
  input  logic [0:0]               wuser,

  output logic                     bvalid,
  input  logic                     bready,
  output logic [1:0]               bresp,
  output logic [ID_WIDTH-1:0]      bid,
  output logic [0:0]               buser,

  input  logic                     arvalid,
  output logic                     arready,
  input  logic [ADDR_WIDTH-1:0]    araddr,
  input  logic [ID_WIDTH-1:0]      arid,
  input  logic [7:0]               arlen,
  input  logic [2:0]               arsize,
  input  logic [1:0]               arburst,
  input  logic [1:0]               arlock,
  input  logic [3:0]               arcache,
  input  logic [2:0]               arprot,
  input  logic [3:0]               arqos,
  input  logic [3:0]               arregion,
  input  logic [0:0]               aruser,

  output logic                     rvalid,
  input  logic                     rready,
  output logic [DATA_WIDTH-1:0]    rdata,
  output logic                     rlast,
  output logic [ID_WIDTH-1:0]      rid,
  output logic [0:0]               ruser,
  output logic [1:0]               rresp
);

localparam int STRB_WIDTH = DATA_WIDTH / 8;

logic [DATA_WIDTH-1:0] mem [0:DEPTH_WORDS-1];

logic [ADDR_WIDTH-1:0] wr_base_addr;
logic [7:0]            wr_len;
logic [15:0]           wr_beat;
logic                  wr_active;
logic                  wr_resp_pending;

logic [ADDR_WIDTH-1:0] rd_base_addr;
logic [7:0]            rd_len;
logic [15:0]           rd_beat;
logic                  rd_active;
logic [ID_WIDTH-1:0]   rd_id;

int unsigned idx;
integer      byte_i;

assign awready = (!wr_active) && (!bvalid) && (!wr_resp_pending);
assign wready  = wr_active;
assign arready = (!rd_active) && (!rvalid);

always_ff @(posedge clk) begin
  if (rst) begin
    wr_base_addr    <= '0;
    wr_len          <= '0;
    wr_beat         <= '0;
    wr_active       <= 1'b0;
    wr_resp_pending <= 1'b0;
    bvalid          <= 1'b0;
    bresp           <= 2'b00;
    bid             <= '0;
    buser           <= '0;
  end else begin
    if (awvalid && awready) begin
      wr_base_addr <= awaddr;
      wr_len       <= awlen;
      wr_beat      <= '0;
      wr_active    <= 1'b1;
      bid          <= awid;
    end

    if (wvalid && wready && wr_active) begin
      idx = (wr_base_addr >> $clog2(STRB_WIDTH)) + wr_beat;
      if (idx < DEPTH_WORDS) begin
        for (byte_i = 0; byte_i < STRB_WIDTH; byte_i = byte_i + 1) begin
          if (wstrb[byte_i]) mem[idx][8*byte_i +: 8] <= wdata[8*byte_i +: 8];
        end
      end
      if ((wr_beat == wr_len) || wlast) begin
        wr_active       <= 1'b0;
        wr_resp_pending <= 1'b1;
      end
      wr_beat <= wr_beat + 1'b1;
    end

    if (wr_resp_pending && !bvalid) begin
      bvalid <= 1'b1;
      bresp  <= 2'b00;
      buser  <= '0;
      wr_resp_pending <= 1'b0;
    end

    if (bvalid && bready) bvalid <= 1'b0;
  end
end

always_ff @(posedge clk) begin
  if (rst) begin
    rd_base_addr <= '0;
    rd_len       <= '0;
    rd_beat      <= '0;
    rd_active    <= 1'b0;
    rd_id        <= '0;
    rvalid       <= 1'b0;
    rdata        <= '0;
    rlast        <= 1'b0;
    rid          <= '0;
    ruser        <= '0;
    rresp        <= 2'b00;
  end else begin
    if (arvalid && arready) begin
      rd_base_addr <= araddr;
      rd_len       <= arlen;
      rd_beat      <= '0;
      rd_active    <= 1'b1;
      rd_id        <= arid;
    end

    if (rd_active && (!rvalid || rready)) begin
      idx = (rd_base_addr >> $clog2(STRB_WIDTH)) + rd_beat;
      rdata <= (idx < DEPTH_WORDS) ? mem[idx] : '0;
      rid   <= rd_id;
      ruser <= '0;
      rresp <= 2'b00;
      rlast <= (rd_beat == rd_len);
      rvalid<= 1'b1;
      if (rd_beat == rd_len) rd_active <= 1'b0;
      else                    rd_beat   <= rd_beat + 1'b1;
    end

    if (rvalid && rready && rlast) begin
      rvalid <= 1'b0;
      rlast  <= 1'b0;
    end
  end
end

endmodule

