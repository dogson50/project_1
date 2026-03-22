// ============================================================================
// AXI_Block_RAM
// ----------------------------------------------------------------------------
// 模块功能：
// 1) 提供一个简化 AXI-Lite 从设备 RAM（32bit 数据宽度）；
// 2) 支持 AW/W 分离握手，按 WSTRB 进行字节写；
// 3) 支持单拍读返回（AR 握手后返回对应 word）；
// 4) 可选通过 INIT_FILE 进行上电初始化（$readmemh）。
//
// 说明：
// - 本模块用于教学/demo 场景，未实现 BRESP/RRESP 等完整 AXI 响应字段；
// - 可直接与 picorv32_axi 的轻量接口配合使用。
// ============================================================================
module AXI_Block_RAM #(
    parameter integer ADDR_WIDTH = 14, // RAM 深度 = 2^ADDR_WIDTH（单位：word）
    parameter INIT_FILE = ""            // 可选初始化文件路径（hex）
) (
    input  wire         aclk,    // 输入：RAM 时钟
    input  wire         aresetn, // 输入：低有效复位

    // AXI-Lite 写地址通道（AW）
    input  wire         s_axi_awvalid, // 输入：写地址有效
    output wire         s_axi_awready, // 输出：写地址就绪
    input  wire [31:0]  s_axi_awaddr,  // 输入：写地址
    input  wire [2:0]   s_axi_awprot,  // 输入：保护属性（本实现未使用）

    // AXI-Lite 写数据通道（W）
    input  wire         s_axi_wvalid, // 输入：写数据有效
    output wire         s_axi_wready, // 输出：写数据就绪
    input  wire [31:0]  s_axi_wdata,  // 输入：写数据
    input  wire [3:0]   s_axi_wstrb,  // 输入：写字节使能

    // AXI-Lite 写响应通道（B）
    output wire         s_axi_bvalid, // 输出：写响应有效
    input  wire         s_axi_bready, // 输入：写响应接收就绪

    // AXI-Lite 读地址通道（AR）
    input  wire         s_axi_arvalid, // 输入：读地址有效
    output wire         s_axi_arready, // 输出：读地址就绪
    input  wire [31:0]  s_axi_araddr,  // 输入：读地址
    input  wire [2:0]   s_axi_arprot,  // 输入：保护属性（本实现未使用）

    // AXI-Lite 读数据通道（R）
    output wire         s_axi_rvalid, // 输出：读数据有效
    input  wire         s_axi_rready, // 输入：读数据接收就绪
    output wire [31:0]  s_axi_rdata   // 输出：读数据
);

localparam integer WORDS = (1 << ADDR_WIDTH);

// 推断为块 RAM
(* ram_style = "block" *) reg [31:0] mem [0:WORDS-1];

// AW/W 分离握手缓存
reg aw_seen;
reg w_seen;
reg [31:0] awaddr_reg;
reg [31:0] wdata_reg;
reg [3:0]  wstrb_reg;

// B/R 通道状态
reg bvalid_reg;
reg rvalid_reg;
reg [31:0] rdata_reg;

// word 地址索引（去掉 byte 偏移）
wire [ADDR_WIDTH-1:0] aw_word_addr = awaddr_reg[ADDR_WIDTH+1:2];
wire [ADDR_WIDTH-1:0] ar_word_addr = s_axi_araddr[ADDR_WIDTH+1:2];

assign s_axi_awready = aresetn && !aw_seen && !bvalid_reg;
assign s_axi_wready  = aresetn && !w_seen && !bvalid_reg;
assign s_axi_bvalid  = bvalid_reg;

assign s_axi_arready = aresetn && !rvalid_reg;
assign s_axi_rvalid  = rvalid_reg;
assign s_axi_rdata   = rdata_reg;

integer i;
initial begin
    for (i = 0; i < WORDS; i = i + 1)
        mem[i] = 32'h0;
    if (INIT_FILE != "")
        $readmemh(INIT_FILE, mem);
end

always @(posedge aclk) begin
    if (!aresetn) begin
        aw_seen    <= 1'b0;
        w_seen     <= 1'b0;
        awaddr_reg <= 32'h0;
        wdata_reg  <= 32'h0;
        wstrb_reg  <= 4'h0;
        bvalid_reg <= 1'b0;
        rvalid_reg <= 1'b0;
        rdata_reg  <= 32'h0;
    end else begin
        // 记录 AW 握手
        if (s_axi_awvalid && s_axi_awready) begin
            aw_seen    <= 1'b1;
            awaddr_reg <= s_axi_awaddr;
        end

        // 记录 W 握手
        if (s_axi_wvalid && s_axi_wready) begin
            w_seen    <= 1'b1;
            wdata_reg <= s_axi_wdata;
            wstrb_reg <= s_axi_wstrb;
        end

        // AW/W 都到齐后执行写入并拉高 BVALID
        if (aw_seen && w_seen && !bvalid_reg) begin
            if (wstrb_reg[0]) mem[aw_word_addr][7:0]   <= wdata_reg[7:0];
            if (wstrb_reg[1]) mem[aw_word_addr][15:8]  <= wdata_reg[15:8];
            if (wstrb_reg[2]) mem[aw_word_addr][23:16] <= wdata_reg[23:16];
            if (wstrb_reg[3]) mem[aw_word_addr][31:24] <= wdata_reg[31:24];
            bvalid_reg <= 1'b1;
            aw_seen    <= 1'b0;
            w_seen     <= 1'b0;
        end

        // B 通道完成
        if (bvalid_reg && s_axi_bready)
            bvalid_reg <= 1'b0;

        // AR 握手后返回对应 word
        if (s_axi_arvalid && s_axi_arready) begin
            rdata_reg  <= mem[ar_word_addr];
            rvalid_reg <= 1'b1;
        end else if (rvalid_reg && s_axi_rready) begin
            rvalid_reg <= 1'b0;
        end
    end
end

endmodule
