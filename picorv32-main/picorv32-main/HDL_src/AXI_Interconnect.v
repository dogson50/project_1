// ============================================================================
// AXI_Interconnect
// ----------------------------------------------------------------------------
// 一个“单主两从”的简化 AXI-Lite 互连：
// - 主设备：CPU（picorv32_axi）
// - 从设备：Slave0(Program RAM) + Slave1(Data RAM)
//
// 设计要点：
// 1) AW/AR 分别译码，按地址路由到不同 Slave
// 2) 写通道采用“先锁定目标，再等待 W/B 完成”策略
// 3) 读通道采用“先锁定目标，再等待 R 完成”策略
// 4) 未命中地址返回默认 0（读）或空写响应（写）
//
// 这是 demo 级互连，目的是清晰可读与快速验证。
// ============================================================================
module AXI_Interconnect #(
    parameter [31:0] PORT0_BASE = 32'h0000_0000,
    parameter [31:0] PORT0_MASK = 32'hffff_0000,
    parameter [31:0] PORT1_BASE = 32'h2000_0000,
    parameter [31:0] PORT1_MASK = 32'hffff_0000
) (
    input  wire        aclk,
    input  wire        aresetn,

    // ============================
    // AXI-Lite Master Side (CPU)
    // ============================
    input  wire        m_axi_awvalid,
    output wire        m_axi_awready,
    input  wire [31:0] m_axi_awaddr,
    input  wire [2:0]  m_axi_awprot,

    input  wire        m_axi_wvalid,
    output wire        m_axi_wready,
    input  wire [31:0] m_axi_wdata,
    input  wire [3:0]  m_axi_wstrb,

    output wire        m_axi_bvalid,
    input  wire        m_axi_bready,

    input  wire        m_axi_arvalid,
    output wire        m_axi_arready,
    input  wire [31:0] m_axi_araddr,
    input  wire [2:0]  m_axi_arprot,

    output wire        m_axi_rvalid,
    input  wire        m_axi_rready,
    output wire [31:0] m_axi_rdata,

    // ===============================
    // AXI-Lite Slave Side 0 (Program)
    // ===============================
    output wire        s0_axi_awvalid,
    input  wire        s0_axi_awready,
    output wire [31:0] s0_axi_awaddr,
    output wire [2:0]  s0_axi_awprot,

    output wire        s0_axi_wvalid,
    input  wire        s0_axi_wready,
    output wire [31:0] s0_axi_wdata,
    output wire [3:0]  s0_axi_wstrb,

    input  wire        s0_axi_bvalid,
    output wire        s0_axi_bready,

    output wire        s0_axi_arvalid,
    input  wire        s0_axi_arready,
    output wire [31:0] s0_axi_araddr,
    output wire [2:0]  s0_axi_arprot,

    input  wire        s0_axi_rvalid,
    output wire        s0_axi_rready,
    input  wire [31:0] s0_axi_rdata,

    // ==============================
    // AXI-Lite Slave Side 1 (Data)
    // ==============================
    output wire        s1_axi_awvalid,
    input  wire        s1_axi_awready,
    output wire [31:0] s1_axi_awaddr,
    output wire [2:0]  s1_axi_awprot,

    output wire        s1_axi_wvalid,
    input  wire        s1_axi_wready,
    output wire [31:0] s1_axi_wdata,
    output wire [3:0]  s1_axi_wstrb,

    input  wire        s1_axi_bvalid,
    output wire        s1_axi_bready,

    output wire        s1_axi_arvalid,
    input  wire        s1_axi_arready,
    output wire [31:0] s1_axi_araddr,
    output wire [2:0]  s1_axi_arprot,

    input  wire        s1_axi_rvalid,
    output wire        s1_axi_rready,
    input  wire [31:0] s1_axi_rdata
);

localparam [1:0] TARGET_P0      = 2'd0;
localparam [1:0] TARGET_P1      = 2'd1;
localparam [1:0] TARGET_DEFAULT = 2'd2;

wire aw_p0_sel;
wire aw_p1_sel;
wire ar_p0_sel;
wire ar_p1_sel;

// 写地址译码（AW）
AXI_Decoder #(
    .PORT0_BASE(PORT0_BASE),
    .PORT0_MASK(PORT0_MASK),
    .PORT1_BASE(PORT1_BASE),
    .PORT1_MASK(PORT1_MASK)
) u_aw_decoder (
    .addr(m_axi_awaddr),
    .p0_sel(aw_p0_sel),
    .p1_sel(aw_p1_sel)
);

// 读地址译码（AR）
AXI_Decoder #(
    .PORT0_BASE(PORT0_BASE),
    .PORT0_MASK(PORT0_MASK),
    .PORT1_BASE(PORT1_BASE),
    .PORT1_MASK(PORT1_MASK)
) u_ar_decoder (
    .addr(m_axi_araddr),
    .p0_sel(ar_p0_sel),
    .p1_sel(ar_p1_sel)
);

// 译码结果：命中 P0/P1，否则走默认目标
wire [1:0] aw_target = aw_p0_sel ? TARGET_P0 : (aw_p1_sel ? TARGET_P1 : TARGET_DEFAULT);
wire [1:0] ar_target = ar_p0_sel ? TARGET_P0 : (ar_p1_sel ? TARGET_P1 : TARGET_DEFAULT);

// 写事务状态机寄存器
reg       write_active;
reg [1:0] write_target;
reg       default_bvalid;

// 读事务状态机寄存器
reg       read_active;
reg [1:0] read_target;
reg       default_rvalid;
reg [31:0] default_rdata;

// 常用握手事件
wire aw_hs = m_axi_awvalid && m_axi_awready;
wire w_hs  = m_axi_wvalid  && m_axi_wready;
wire b_hs  = m_axi_bvalid  && m_axi_bready;
wire ar_hs = m_axi_arvalid && m_axi_arready;
wire r_hs  = m_axi_rvalid  && m_axi_rready;

// 地址/属性/数据广播到所有 slave，最终由 valid 控制生效目标
assign s0_axi_awaddr = m_axi_awaddr;
assign s1_axi_awaddr = m_axi_awaddr;
assign s0_axi_awprot = m_axi_awprot;
assign s1_axi_awprot = m_axi_awprot;

assign s0_axi_wdata = m_axi_wdata;
assign s1_axi_wdata = m_axi_wdata;
assign s0_axi_wstrb = m_axi_wstrb;
assign s1_axi_wstrb = m_axi_wstrb;

assign s0_axi_araddr = m_axi_araddr;
assign s1_axi_araddr = m_axi_araddr;
assign s0_axi_arprot = m_axi_arprot;
assign s1_axi_arprot = m_axi_arprot;

// 只有在写通道空闲时，才允许 AW 发到目标 slave
assign s0_axi_awvalid = (!write_active) && (aw_target == TARGET_P0) && m_axi_awvalid;
assign s1_axi_awvalid = (!write_active) && (aw_target == TARGET_P1) && m_axi_awvalid;

// 写目标锁定后，W 通道只发往被锁定 slave
assign s0_axi_wvalid = write_active && (write_target == TARGET_P0) && m_axi_wvalid;
assign s1_axi_wvalid = write_active && (write_target == TARGET_P1) && m_axi_wvalid;

// 只有在读通道空闲时，才允许 AR 发到目标 slave
assign s0_axi_arvalid = (!read_active) && (ar_target == TARGET_P0) && m_axi_arvalid;
assign s1_axi_arvalid = (!read_active) && (ar_target == TARGET_P1) && m_axi_arvalid;

// 回传给 Master 的 ready/valid/data 由目标 slave 多路复用
assign m_axi_awready = !write_active &&
                       ((aw_target == TARGET_P0) ? s0_axi_awready :
                        (aw_target == TARGET_P1) ? s1_axi_awready : 1'b1);

assign m_axi_wready = write_active &&
                      ((write_target == TARGET_P0) ? s0_axi_wready :
                       (write_target == TARGET_P1) ? s1_axi_wready : !default_bvalid);

assign m_axi_bvalid = write_active &&
                      ((write_target == TARGET_P0) ? s0_axi_bvalid :
                       (write_target == TARGET_P1) ? s1_axi_bvalid : default_bvalid);

assign s0_axi_bready = write_active && (write_target == TARGET_P0) && m_axi_bready;
assign s1_axi_bready = write_active && (write_target == TARGET_P1) && m_axi_bready;

assign m_axi_arready = !read_active &&
                       ((ar_target == TARGET_P0) ? s0_axi_arready :
                        (ar_target == TARGET_P1) ? s1_axi_arready : 1'b1);

assign m_axi_rvalid = read_active &&
                      ((read_target == TARGET_P0) ? s0_axi_rvalid :
                       (read_target == TARGET_P1) ? s1_axi_rvalid : default_rvalid);

assign m_axi_rdata = (read_target == TARGET_P0) ? s0_axi_rdata :
                     (read_target == TARGET_P1) ? s1_axi_rdata : default_rdata;

assign s0_axi_rready = read_active && (read_target == TARGET_P0) && m_axi_rready;
assign s1_axi_rready = read_active && (read_target == TARGET_P1) && m_axi_rready;

always @(posedge aclk) begin
    if (!aresetn) begin
        write_active  <= 1'b0;
        write_target  <= TARGET_DEFAULT;
        default_bvalid <= 1'b0;

        read_active   <= 1'b0;
        read_target   <= TARGET_DEFAULT;
        default_rvalid <= 1'b0;
        default_rdata  <= 32'h0;
    end else begin
        // 接收到 AW 后，锁定写目标，等待后续 W/B 完成
        if (!write_active && aw_hs) begin
            write_active <= 1'b1;
            write_target <= aw_target;
            default_bvalid <= 1'b0;
        end

        // 默认目标下，W 到达即产生一个“空写响应”
        if (write_active && (write_target == TARGET_DEFAULT) && w_hs)
            default_bvalid <= 1'b1;

        // 写响应完成，释放写通道
        if (write_active && b_hs) begin
            write_active  <= 1'b0;
            default_bvalid <= 1'b0;
        end

        // 接收到 AR 后，锁定读目标
        if (!read_active && ar_hs) begin
            read_active <= 1'b1;
            read_target <= ar_target;
            // 默认目标下返回 0
            if (ar_target == TARGET_DEFAULT) begin
                default_rdata  <= 32'h0;
                default_rvalid <= 1'b1;
            end else begin
                default_rvalid <= 1'b0;
            end
        end

        // 读响应完成，释放读通道
        if (read_active && r_hs) begin
            read_active   <= 1'b0;
            default_rvalid <= 1'b0;
        end
    end
end

endmodule
