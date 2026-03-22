// ============================================================================
// AXI_DualPort_RAM
// ----------------------------------------------------------------------------
// 模块功能：
// 1) 单个存储体提供双端口访问；
// 2) Port-A：AXI-Lite 从接口，给 CPU 常规 load/store；
// 3) Port-B：AXI Burst 子集从接口，给 DMA 高吞吐搬运；
// 4) 两个端口共享同一组 mem[]，便于软件与 DMA 交换数据。
//
// 说明：
// - 数据宽度固定 32bit；
// - Port-B 仅支持单个未完成读/写突发（简化实现）；
// - 不含 ID/RESP 等完整 AXI4 字段，定位于 demo 验证。
// ============================================================================
module AXI_DualPort_RAM #(
    parameter integer ADDR_WIDTH = 14, // 深度 = 2^ADDR_WIDTH（word）
    parameter INIT_FILE = ""            // 可选初始化文件路径（hex）
) (
    input  wire         aclk,    // 输入：RAM 时钟
    input  wire         aresetn, // 输入：低有效复位

    // ------------------------------------------------------------------------
    // Port-A：AXI-Lite 从接口
    // ------------------------------------------------------------------------
    input  wire         s0_axi_awvalid, // 输入：A口写地址有效
    output wire         s0_axi_awready, // 输出：A口写地址就绪
    input  wire [31:0]  s0_axi_awaddr,  // 输入：A口写地址
    input  wire [2:0]   s0_axi_awprot,  // 输入：A口保护属性（未使用）

    input  wire         s0_axi_wvalid, // 输入：A口写数据有效
    output wire         s0_axi_wready, // 输出：A口写数据就绪
    input  wire [31:0]  s0_axi_wdata,  // 输入：A口写数据
    input  wire [3:0]   s0_axi_wstrb,  // 输入：A口写字节使能

    output wire         s0_axi_bvalid, // 输出：A口写响应有效
    input  wire         s0_axi_bready, // 输入：A口写响应接收就绪

    input  wire         s0_axi_arvalid, // 输入：A口读地址有效
    output wire         s0_axi_arready, // 输出：A口读地址就绪
    input  wire [31:0]  s0_axi_araddr,  // 输入：A口读地址
    input  wire [2:0]   s0_axi_arprot,  // 输入：A口保护属性（未使用）

    output wire         s0_axi_rvalid, // 输出：A口读数据有效
    input  wire         s0_axi_rready, // 输入：A口读数据接收就绪
    output wire [31:0]  s0_axi_rdata,  // 输出：A口读数据

    // ------------------------------------------------------------------------
    // Port-B：AXI Burst 子集从接口
    // ------------------------------------------------------------------------
    input  wire         s1_axi_awvalid, // 输入：B口写地址有效
    output wire         s1_axi_awready, // 输出：B口写地址就绪
    input  wire [31:0]  s1_axi_awaddr,  // 输入：B口写起始地址
    input  wire [7:0]   s1_axi_awlen,   // 输入：B口突发长度（beats-1）
    input  wire [2:0]   s1_axi_awsize,  // 输入：B口每 beat 字节数编码
    input  wire [1:0]   s1_axi_awburst, // 输入：B口突发类型

    input  wire         s1_axi_wvalid, // 输入：B口写数据有效
    output wire         s1_axi_wready, // 输出：B口写数据就绪
    input  wire [31:0]  s1_axi_wdata,  // 输入：B口写数据
    input  wire [3:0]   s1_axi_wstrb,  // 输入：B口写字节使能
    input  wire         s1_axi_wlast,  // 输入：B口写突发最后一拍

    output wire         s1_axi_bvalid, // 输出：B口写响应有效
    input  wire         s1_axi_bready, // 输入：B口写响应接收就绪

    input  wire         s1_axi_arvalid, // 输入：B口读地址有效
    output wire         s1_axi_arready, // 输出：B口读地址就绪
    input  wire [31:0]  s1_axi_araddr,  // 输入：B口读起始地址
    input  wire [7:0]   s1_axi_arlen,   // 输入：B口读突发长度（beats-1）
    input  wire [2:0]   s1_axi_arsize,  // 输入：B口每 beat 字节数编码
    input  wire [1:0]   s1_axi_arburst, // 输入：B口突发类型

    output wire         s1_axi_rvalid, // 输出：B口读数据有效
    input  wire         s1_axi_rready, // 输入：B口读数据接收就绪
    output wire [31:0]  s1_axi_rdata,  // 输出：B口读数据
    output wire         s1_axi_rlast   // 输出：B口读突发最后一拍
);

localparam integer WORDS = (1 << ADDR_WIDTH);

(* ram_style = "block" *) reg [31:0] mem [0:WORDS-1];

// ------------------------------------------------------------------------
// Port A (AXI-Lite) registers
// ------------------------------------------------------------------------
reg aw_seen;
reg w_seen;
reg [31:0] awaddr_reg;
reg [31:0] wdata_reg;
reg [3:0]  wstrb_reg;
reg bvalid_reg;
reg rvalid_reg;
reg [31:0] rdata_reg;

wire [ADDR_WIDTH-1:0] aw_word_addr = awaddr_reg[ADDR_WIDTH+1:2];
wire [ADDR_WIDTH-1:0] ar_word_addr = s0_axi_araddr[ADDR_WIDTH+1:2];

assign s0_axi_awready = aresetn && !aw_seen && !bvalid_reg;
assign s0_axi_wready  = aresetn && !w_seen && !bvalid_reg;
assign s0_axi_bvalid  = bvalid_reg;
assign s0_axi_arready = aresetn && !rvalid_reg;
assign s0_axi_rvalid  = rvalid_reg;
assign s0_axi_rdata   = rdata_reg;

// ------------------------------------------------------------------------
// Port B (Burst) registers
// ------------------------------------------------------------------------
reg        wr_active_b;
reg [31:0] wr_addr_b;
reg [7:0]  wr_beats_left_b;
reg [2:0]  wr_size_b;
reg [1:0]  wr_burst_b;
reg        bvalid_b;

reg        rd_active_b;
reg [31:0] rd_addr_b;
reg [7:0]  rd_beats_left_b;
reg [2:0]  rd_size_b;
reg [1:0]  rd_burst_b;
reg        rvalid_b;
reg [31:0] rdata_b;
reg        rlast_b;

wire [31:0] wr_addr_next_b = (wr_burst_b == 2'b01) ? (wr_addr_b + (32'd1 << wr_size_b)) : wr_addr_b;
wire [31:0] rd_addr_next_b = (rd_burst_b == 2'b01) ? (rd_addr_b + (32'd1 << rd_size_b)) : rd_addr_b;

assign s1_axi_awready = aresetn && !wr_active_b && !bvalid_b;
assign s1_axi_wready  = aresetn && wr_active_b;
assign s1_axi_bvalid  = bvalid_b;

assign s1_axi_arready = aresetn && !rd_active_b;
assign s1_axi_rvalid  = rvalid_b;
assign s1_axi_rdata   = rdata_b;
assign s1_axi_rlast   = rlast_b;

integer i;
initial begin
    for (i = 0; i < WORDS; i = i + 1)
        mem[i] = 32'h0;
    if (INIT_FILE != "")
        $readmemh(INIT_FILE, mem);
end

always @(posedge aclk) begin
    if (!aresetn) begin
        // Port A reset
        aw_seen       <= 1'b0;
        w_seen        <= 1'b0;
        awaddr_reg    <= 32'h0;
        wdata_reg     <= 32'h0;
        wstrb_reg     <= 4'h0;
        bvalid_reg    <= 1'b0;
        rvalid_reg    <= 1'b0;
        rdata_reg     <= 32'h0;

        // Port B reset
        wr_active_b   <= 1'b0;
        wr_addr_b     <= 32'h0;
        wr_beats_left_b <= 8'd0;
        wr_size_b     <= 3'd0;
        wr_burst_b    <= 2'b01;
        bvalid_b      <= 1'b0;

        rd_active_b   <= 1'b0;
        rd_addr_b     <= 32'h0;
        rd_beats_left_b <= 8'd0;
        rd_size_b     <= 3'd0;
        rd_burst_b    <= 2'b01;
        rvalid_b      <= 1'b0;
        rdata_b       <= 32'h0;
        rlast_b       <= 1'b0;
    end else begin
        // ----------------------------------------------------------------
        // Port A AXI-Lite write path
        // ----------------------------------------------------------------
        if (s0_axi_awvalid && s0_axi_awready) begin
            aw_seen    <= 1'b1;
            awaddr_reg <= s0_axi_awaddr;
        end

        if (s0_axi_wvalid && s0_axi_wready) begin
            w_seen    <= 1'b1;
            wdata_reg <= s0_axi_wdata;
            wstrb_reg <= s0_axi_wstrb;
        end

        if (aw_seen && w_seen && !bvalid_reg) begin
            if (wstrb_reg[0]) mem[aw_word_addr][7:0]   <= wdata_reg[7:0];
            if (wstrb_reg[1]) mem[aw_word_addr][15:8]  <= wdata_reg[15:8];
            if (wstrb_reg[2]) mem[aw_word_addr][23:16] <= wdata_reg[23:16];
            if (wstrb_reg[3]) mem[aw_word_addr][31:24] <= wdata_reg[31:24];

            bvalid_reg <= 1'b1;
            aw_seen    <= 1'b0;
            w_seen     <= 1'b0;
        end

        if (bvalid_reg && s0_axi_bready)
            bvalid_reg <= 1'b0;

        // ----------------------------------------------------------------
        // Port A AXI-Lite read path
        // ----------------------------------------------------------------
        if (s0_axi_arvalid && s0_axi_arready) begin
            rdata_reg  <= mem[ar_word_addr];
            rvalid_reg <= 1'b1;
        end else if (rvalid_reg && s0_axi_rready) begin
            rvalid_reg <= 1'b0;
        end

        // ----------------------------------------------------------------
        // Port B AXI burst write path
        // ----------------------------------------------------------------
        if (s1_axi_awvalid && s1_axi_awready) begin
            wr_active_b     <= 1'b1;
            wr_addr_b       <= s1_axi_awaddr;
            wr_beats_left_b <= s1_axi_awlen + 8'd1;
            wr_size_b       <= s1_axi_awsize;
            wr_burst_b      <= s1_axi_awburst;
        end

        if (wr_active_b && s1_axi_wvalid && s1_axi_wready) begin
            if (s1_axi_wstrb[0]) mem[wr_addr_b[ADDR_WIDTH+1:2]][7:0]   <= s1_axi_wdata[7:0];
            if (s1_axi_wstrb[1]) mem[wr_addr_b[ADDR_WIDTH+1:2]][15:8]  <= s1_axi_wdata[15:8];
            if (s1_axi_wstrb[2]) mem[wr_addr_b[ADDR_WIDTH+1:2]][23:16] <= s1_axi_wdata[23:16];
            if (s1_axi_wstrb[3]) mem[wr_addr_b[ADDR_WIDTH+1:2]][31:24] <= s1_axi_wdata[31:24];

            if ((wr_beats_left_b == 8'd1) || s1_axi_wlast) begin
                wr_active_b <= 1'b0;
                bvalid_b    <= 1'b1;
            end else begin
                wr_beats_left_b <= wr_beats_left_b - 8'd1;
                wr_addr_b       <= wr_addr_next_b;
            end
        end

        if (bvalid_b && s1_axi_bready)
            bvalid_b <= 1'b0;

        // ----------------------------------------------------------------
        // Port B AXI burst read path
        // ----------------------------------------------------------------
        if (s1_axi_arvalid && s1_axi_arready) begin
            rd_active_b     <= 1'b1;
            rd_addr_b       <= s1_axi_araddr;
            rd_beats_left_b <= s1_axi_arlen + 8'd1;
            rd_size_b       <= s1_axi_arsize;
            rd_burst_b      <= s1_axi_arburst;
            rvalid_b        <= 1'b0;
            rlast_b         <= 1'b0;
        end

        if (rd_active_b) begin
            if (!rvalid_b) begin
                rdata_b  <= mem[rd_addr_b[ADDR_WIDTH+1:2]];
                rlast_b  <= (rd_beats_left_b == 8'd1);
                rvalid_b <= 1'b1;
            end else if (rvalid_b && s1_axi_rready) begin
                if (rd_beats_left_b == 8'd1) begin
                    rvalid_b    <= 1'b0;
                    rlast_b     <= 1'b0;
                    rd_active_b <= 1'b0;
                end else begin
                    rd_beats_left_b <= rd_beats_left_b - 8'd1;
                    rd_addr_b       <= rd_addr_next_b;
                    rdata_b         <= mem[rd_addr_next_b[ADDR_WIDTH+1:2]];
                    rlast_b         <= (rd_beats_left_b == 8'd2);
                    rvalid_b        <= 1'b1;
                end
            end
        end
    end
end

endmodule
