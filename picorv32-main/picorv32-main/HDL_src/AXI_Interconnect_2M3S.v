// ============================================================================
// AXI_Interconnect_2M3S
// ----------------------------------------------------------------------------
// 模块功能：
// 1) 提供 2 主设备到 3 从设备的 AXI-Lite 地址路由与握手转发；
// 2) 支持轮询仲裁（m0/m1）；
// 3) 全局只允许 1 个未完成写事务 + 1 个未完成读事务（简化实现）。
//
// 端口约定：
// - m0：通常接 CPU；
// - m1：可接 DMA 或其它主设备；
// - s0/s1/s2：按地址映射选通。
// ============================================================================
module AXI_Interconnect_2M3S #(
    parameter [31:0] PORT0_BASE = 32'h0000_0000,
    parameter [31:0] PORT0_MASK = 32'hffff_0000,
    parameter [31:0] PORT1_BASE = 32'h2000_0000,
    parameter [31:0] PORT1_MASK = 32'hffff_0000,
    parameter [31:0] PORT2_BASE = 32'h4000_0000,
    parameter [31:0] PORT2_MASK = 32'hffff_0000
) (
    input  wire        aclk,    // 输入：互连时钟
    input  wire        aresetn, // 输入：低有效复位

    // ============================
    // Master 0（通常为 CPU）
    // ============================
    input  wire        m0_axi_awvalid, // 输入：m0 写地址有效
    output wire        m0_axi_awready, // 输出：m0 写地址就绪
    input  wire [31:0] m0_axi_awaddr,  // 输入：m0 写地址
    input  wire [2:0]  m0_axi_awprot,  // 输入：m0 保护属性
    input  wire        m0_axi_wvalid,  // 输入：m0 写数据有效
    output wire        m0_axi_wready,  // 输出：m0 写数据就绪
    input  wire [31:0] m0_axi_wdata,   // 输入：m0 写数据
    input  wire [3:0]  m0_axi_wstrb,   // 输入：m0 写字节使能
    output wire        m0_axi_bvalid,  // 输出：m0 写响应有效
    input  wire        m0_axi_bready,  // 输入：m0 写响应接收就绪
    input  wire        m0_axi_arvalid, // 输入：m0 读地址有效
    output wire        m0_axi_arready, // 输出：m0 读地址就绪
    input  wire [31:0] m0_axi_araddr,  // 输入：m0 读地址
    input  wire [2:0]  m0_axi_arprot,  // 输入：m0 保护属性
    output wire        m0_axi_rvalid,  // 输出：m0 读数据有效
    input  wire        m0_axi_rready,  // 输入：m0 读数据接收就绪
    output wire [31:0] m0_axi_rdata,   // 输出：m0 读数据

    // ============================
    // Master 1（通常为 DMA）
    // ============================
    input  wire        m1_axi_awvalid, // 输入：m1 写地址有效
    output wire        m1_axi_awready, // 输出：m1 写地址就绪
    input  wire [31:0] m1_axi_awaddr,  // 输入：m1 写地址
    input  wire [2:0]  m1_axi_awprot,  // 输入：m1 保护属性
    input  wire        m1_axi_wvalid,  // 输入：m1 写数据有效
    output wire        m1_axi_wready,  // 输出：m1 写数据就绪
    input  wire [31:0] m1_axi_wdata,   // 输入：m1 写数据
    input  wire [3:0]  m1_axi_wstrb,   // 输入：m1 写字节使能
    output wire        m1_axi_bvalid,  // 输出：m1 写响应有效
    input  wire        m1_axi_bready,  // 输入：m1 写响应接收就绪
    input  wire        m1_axi_arvalid, // 输入：m1 读地址有效
    output wire        m1_axi_arready, // 输出：m1 读地址就绪
    input  wire [31:0] m1_axi_araddr,  // 输入：m1 读地址
    input  wire [2:0]  m1_axi_arprot,  // 输入：m1 保护属性
    output wire        m1_axi_rvalid,  // 输出：m1 读数据有效
    input  wire        m1_axi_rready,  // 输入：m1 读数据接收就绪
    output wire [31:0] m1_axi_rdata,   // 输出：m1 读数据

    // ============================
    // Slave 0（Program RAM）
    // ============================
    output wire        s0_axi_awvalid, // 输出：到 s0 写地址有效
    input  wire        s0_axi_awready, // 输入：s0 写地址就绪
    output wire [31:0] s0_axi_awaddr,  // 输出：到 s0 写地址
    output wire [2:0]  s0_axi_awprot,  // 输出：到 s0 保护属性
    output wire        s0_axi_wvalid,  // 输出：到 s0 写数据有效
    input  wire        s0_axi_wready,  // 输入：s0 写数据就绪
    output wire [31:0] s0_axi_wdata,   // 输出：到 s0 写数据
    output wire [3:0]  s0_axi_wstrb,   // 输出：到 s0 写字节使能
    input  wire        s0_axi_bvalid,  // 输入：s0 写响应有效
    output wire        s0_axi_bready,  // 输出：到 s0 写响应接收就绪
    output wire        s0_axi_arvalid, // 输出：到 s0 读地址有效
    input  wire        s0_axi_arready, // 输入：s0 读地址就绪
    output wire [31:0] s0_axi_araddr,  // 输出：到 s0 读地址
    output wire [2:0]  s0_axi_arprot,  // 输出：到 s0 保护属性
    input  wire        s0_axi_rvalid,  // 输入：s0 读数据有效
    output wire        s0_axi_rready,  // 输出：到 s0 读数据接收就绪
    input  wire [31:0] s0_axi_rdata,   // 输入：s0 读数据

    // ============================
    // Slave 1（Data RAM）
    // ============================
    output wire        s1_axi_awvalid, // 输出：到 s1 写地址有效
    input  wire        s1_axi_awready, // 输入：s1 写地址就绪
    output wire [31:0] s1_axi_awaddr,  // 输出：到 s1 写地址
    output wire [2:0]  s1_axi_awprot,  // 输出：到 s1 保护属性
    output wire        s1_axi_wvalid,  // 输出：到 s1 写数据有效
    input  wire        s1_axi_wready,  // 输入：s1 写数据就绪
    output wire [31:0] s1_axi_wdata,   // 输出：到 s1 写数据
    output wire [3:0]  s1_axi_wstrb,   // 输出：到 s1 写字节使能
    input  wire        s1_axi_bvalid,  // 输入：s1 写响应有效
    output wire        s1_axi_bready,  // 输出：到 s1 写响应接收就绪
    output wire        s1_axi_arvalid, // 输出：到 s1 读地址有效
    input  wire        s1_axi_arready, // 输入：s1 读地址就绪
    output wire [31:0] s1_axi_araddr,  // 输出：到 s1 读地址
    output wire [2:0]  s1_axi_arprot,  // 输出：到 s1 保护属性
    input  wire        s1_axi_rvalid,  // 输入：s1 读数据有效
    output wire        s1_axi_rready,  // 输出：到 s1 读数据接收就绪
    input  wire [31:0] s1_axi_rdata,   // 输入：s1 读数据

    // ============================
    // Slave 2（DMA CSR）
    // ============================
    output wire        s2_axi_awvalid, // 输出：到 s2 写地址有效
    input  wire        s2_axi_awready, // 输入：s2 写地址就绪
    output wire [31:0] s2_axi_awaddr,  // 输出：到 s2 写地址
    output wire [2:0]  s2_axi_awprot,  // 输出：到 s2 保护属性
    output wire        s2_axi_wvalid,  // 输出：到 s2 写数据有效
    input  wire        s2_axi_wready,  // 输入：s2 写数据就绪
    output wire [31:0] s2_axi_wdata,   // 输出：到 s2 写数据
    output wire [3:0]  s2_axi_wstrb,   // 输出：到 s2 写字节使能
    input  wire        s2_axi_bvalid,  // 输入：s2 写响应有效
    output wire        s2_axi_bready,  // 输出：到 s2 写响应接收就绪
    output wire        s2_axi_arvalid, // 输出：到 s2 读地址有效
    input  wire        s2_axi_arready, // 输入：s2 读地址就绪
    output wire [31:0] s2_axi_araddr,  // 输出：到 s2 读地址
    output wire [2:0]  s2_axi_arprot,  // 输出：到 s2 保护属性
    input  wire        s2_axi_rvalid,  // 输入：s2 读数据有效
    output wire        s2_axi_rready,  // 输出：到 s2 读数据接收就绪
    input  wire [31:0] s2_axi_rdata    // 输入：s2 读数据
);

localparam [1:0] MASTER_M0 = 2'd0;
localparam [1:0] MASTER_M1 = 2'd1;

localparam [1:0] TARGET_P0      = 2'd0;
localparam [1:0] TARGET_P1      = 2'd1;
localparam [1:0] TARGET_P2      = 2'd2;
localparam [1:0] TARGET_DEFAULT = 2'd3;

function [1:0] decode_target;
    input [31:0] addr;
    begin
        if ((addr & PORT0_MASK) == PORT0_BASE)
            decode_target = TARGET_P0;
        else if ((addr & PORT1_MASK) == PORT1_BASE)
            decode_target = TARGET_P1;
        else if ((addr & PORT2_MASK) == PORT2_BASE)
            decode_target = TARGET_P2;
        else
            decode_target = TARGET_DEFAULT;
    end
endfunction

reg write_active;
reg [1:0] write_master;
reg [1:0] write_target;
reg       default_bvalid;

reg read_active;
reg [1:0] read_master;
reg [1:0] read_target;
reg       default_rvalid;
reg [31:0] default_rdata;

reg rr_aw;
reg rr_ar;

wire aw_req0 = m0_axi_awvalid;
wire aw_req1 = m1_axi_awvalid;
wire ar_req0 = m0_axi_arvalid;
wire ar_req1 = m1_axi_arvalid;

wire aw_sel1 = aw_req1 && (!aw_req0 || rr_aw);
wire aw_sel0 = aw_req0 && !aw_sel1;
wire ar_sel1 = ar_req1 && (!ar_req0 || rr_ar);
wire ar_sel0 = ar_req0 && !ar_sel1;

wire [31:0] aw_sel_addr = aw_sel1 ? m1_axi_awaddr : m0_axi_awaddr;
wire [2:0]  aw_sel_prot = aw_sel1 ? m1_axi_awprot : m0_axi_awprot;
wire [1:0]  aw_target   = decode_target(aw_sel_addr);

wire [31:0] ar_sel_addr = ar_sel1 ? m1_axi_araddr : m0_axi_araddr;
wire [2:0]  ar_sel_prot = ar_sel1 ? m1_axi_arprot : m0_axi_arprot;
wire [1:0]  ar_target   = decode_target(ar_sel_addr);

wire aw_ready_mux = (aw_target == TARGET_P0) ? s0_axi_awready :
                    (aw_target == TARGET_P1) ? s1_axi_awready :
                    (aw_target == TARGET_P2) ? s2_axi_awready : 1'b1;

wire ar_ready_mux = (ar_target == TARGET_P0) ? s0_axi_arready :
                    (ar_target == TARGET_P1) ? s1_axi_arready :
                    (ar_target == TARGET_P2) ? s2_axi_arready : 1'b1;

assign m0_axi_awready = !write_active && aw_sel0 && aw_ready_mux;
assign m1_axi_awready = !write_active && aw_sel1 && aw_ready_mux;

wire w_ready_mux = (write_target == TARGET_P0) ? s0_axi_wready :
                   (write_target == TARGET_P1) ? s1_axi_wready :
                   (write_target == TARGET_P2) ? s2_axi_wready : !default_bvalid;

assign m0_axi_wready = write_active && (write_master == MASTER_M0) && w_ready_mux;
assign m1_axi_wready = write_active && (write_master == MASTER_M1) && w_ready_mux;

wire b_valid_mux = (write_target == TARGET_P0) ? s0_axi_bvalid :
                   (write_target == TARGET_P1) ? s1_axi_bvalid :
                   (write_target == TARGET_P2) ? s2_axi_bvalid : default_bvalid;

assign m0_axi_bvalid = write_active && (write_master == MASTER_M0) && b_valid_mux;
assign m1_axi_bvalid = write_active && (write_master == MASTER_M1) && b_valid_mux;

assign m0_axi_arready = !read_active && ar_sel0 && ar_ready_mux;
assign m1_axi_arready = !read_active && ar_sel1 && ar_ready_mux;

wire r_valid_mux = (read_target == TARGET_P0) ? s0_axi_rvalid :
                   (read_target == TARGET_P1) ? s1_axi_rvalid :
                   (read_target == TARGET_P2) ? s2_axi_rvalid : default_rvalid;

wire [31:0] r_data_mux = (read_target == TARGET_P0) ? s0_axi_rdata :
                         (read_target == TARGET_P1) ? s1_axi_rdata :
                         (read_target == TARGET_P2) ? s2_axi_rdata : default_rdata;

assign m0_axi_rvalid = read_active && (read_master == MASTER_M0) && r_valid_mux;
assign m1_axi_rvalid = read_active && (read_master == MASTER_M1) && r_valid_mux;
assign m0_axi_rdata  = r_data_mux;
assign m1_axi_rdata  = r_data_mux;

assign s0_axi_awvalid = !write_active && (aw_target == TARGET_P0) && (aw_sel0 || aw_sel1);
assign s1_axi_awvalid = !write_active && (aw_target == TARGET_P1) && (aw_sel0 || aw_sel1);
assign s2_axi_awvalid = !write_active && (aw_target == TARGET_P2) && (aw_sel0 || aw_sel1);
assign s0_axi_awaddr  = aw_sel_addr;
assign s1_axi_awaddr  = aw_sel_addr;
assign s2_axi_awaddr  = aw_sel_addr;
assign s0_axi_awprot  = aw_sel_prot;
assign s1_axi_awprot  = aw_sel_prot;
assign s2_axi_awprot  = aw_sel_prot;

wire [31:0] w_sel_data = (write_master == MASTER_M1) ? m1_axi_wdata : m0_axi_wdata;
wire [3:0]  w_sel_strb = (write_master == MASTER_M1) ? m1_axi_wstrb : m0_axi_wstrb;
wire        w_sel_valid = (write_master == MASTER_M1) ? m1_axi_wvalid : m0_axi_wvalid;
wire        b_sel_ready = (write_master == MASTER_M1) ? m1_axi_bready : m0_axi_bready;

assign s0_axi_wvalid = write_active && (write_target == TARGET_P0) && w_sel_valid;
assign s1_axi_wvalid = write_active && (write_target == TARGET_P1) && w_sel_valid;
assign s2_axi_wvalid = write_active && (write_target == TARGET_P2) && w_sel_valid;
assign s0_axi_wdata  = w_sel_data;
assign s1_axi_wdata  = w_sel_data;
assign s2_axi_wdata  = w_sel_data;
assign s0_axi_wstrb  = w_sel_strb;
assign s1_axi_wstrb  = w_sel_strb;
assign s2_axi_wstrb  = w_sel_strb;

assign s0_axi_bready = write_active && (write_target == TARGET_P0) && b_sel_ready;
assign s1_axi_bready = write_active && (write_target == TARGET_P1) && b_sel_ready;
assign s2_axi_bready = write_active && (write_target == TARGET_P2) && b_sel_ready;

assign s0_axi_arvalid = !read_active && (ar_target == TARGET_P0) && (ar_sel0 || ar_sel1);
assign s1_axi_arvalid = !read_active && (ar_target == TARGET_P1) && (ar_sel0 || ar_sel1);
assign s2_axi_arvalid = !read_active && (ar_target == TARGET_P2) && (ar_sel0 || ar_sel1);
assign s0_axi_araddr  = ar_sel_addr;
assign s1_axi_araddr  = ar_sel_addr;
assign s2_axi_araddr  = ar_sel_addr;
assign s0_axi_arprot  = ar_sel_prot;
assign s1_axi_arprot  = ar_sel_prot;
assign s2_axi_arprot  = ar_sel_prot;

wire r_sel_ready = (read_master == MASTER_M1) ? m1_axi_rready : m0_axi_rready;

assign s0_axi_rready = read_active && (read_target == TARGET_P0) && r_sel_ready;
assign s1_axi_rready = read_active && (read_target == TARGET_P1) && r_sel_ready;
assign s2_axi_rready = read_active && (read_target == TARGET_P2) && r_sel_ready;

wire aw_hs0 = m0_axi_awvalid && m0_axi_awready;
wire aw_hs1 = m1_axi_awvalid && m1_axi_awready;
wire aw_hs  = aw_hs0 || aw_hs1;

wire w_hs0 = m0_axi_wvalid && m0_axi_wready;
wire w_hs1 = m1_axi_wvalid && m1_axi_wready;
wire w_hs  = w_hs0 || w_hs1;

wire b_hs0 = m0_axi_bvalid && m0_axi_bready;
wire b_hs1 = m1_axi_bvalid && m1_axi_bready;
wire b_hs  = b_hs0 || b_hs1;

wire ar_hs0 = m0_axi_arvalid && m0_axi_arready;
wire ar_hs1 = m1_axi_arvalid && m1_axi_arready;
wire ar_hs  = ar_hs0 || ar_hs1;

wire r_hs0 = m0_axi_rvalid && m0_axi_rready;
wire r_hs1 = m1_axi_rvalid && m1_axi_rready;
wire r_hs  = r_hs0 || r_hs1;

always @(posedge aclk) begin
    if (!aresetn) begin
        write_active  <= 1'b0;
        write_master  <= MASTER_M0;
        write_target  <= TARGET_DEFAULT;
        default_bvalid <= 1'b0;

        read_active   <= 1'b0;
        read_master   <= MASTER_M0;
        read_target   <= TARGET_DEFAULT;
        default_rvalid <= 1'b0;
        default_rdata  <= 32'h0;

        rr_aw <= 1'b0;
        rr_ar <= 1'b0;
    end else begin
        if (!write_active && aw_hs) begin
            write_active <= 1'b1;
            write_master <= aw_hs1 ? MASTER_M1 : MASTER_M0;
            write_target <= aw_target;
            default_bvalid <= 1'b0;
            if (aw_req0 && aw_req1)
                rr_aw <= ~rr_aw;
        end

        if (write_active && (write_target == TARGET_DEFAULT) && w_hs)
            default_bvalid <= 1'b1;

        if (write_active && b_hs) begin
            write_active   <= 1'b0;
            default_bvalid <= 1'b0;
        end

        if (!read_active && ar_hs) begin
            read_active <= 1'b1;
            read_master <= ar_hs1 ? MASTER_M1 : MASTER_M0;
            read_target <= ar_target;
            if (ar_target == TARGET_DEFAULT) begin
                default_rdata  <= 32'h0;
                default_rvalid <= 1'b1;
            end else begin
                default_rvalid <= 1'b0;
            end
            if (ar_req0 && ar_req1)
                rr_ar <= ~rr_ar;
        end

        if (read_active && r_hs) begin
            read_active   <= 1'b0;
            default_rvalid <= 1'b0;
        end
    end
end

endmodule
