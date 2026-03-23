`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 模块名: npu_csr_if
// 功能  : NPU 控制面的 AXI-Lite CSR 终端
//
// 设计说明:
// 1) 实现冻结版寄存器映射 0x00 ~ 0x50；
// 2) start / soft_reset 采用 W1P，输出单周期脉冲；
// 3) done / error / irq_pending 采用 W1C，输出单周期清除脉冲；
// 4) busy / done / error / irq_pending、错误码和 PERF_* 由外部镜像输入提供；
// 5) busy 时重复 start 的错误归属后级 npu_cmd_ctrl，本模块保持原样送出 start 脉冲。
//////////////////////////////////////////////////////////////////////////////////
module npu_csr_if (
    input  wire         clk,                    // 输入：CSR 时钟
    input  wire         resetn,                 // 输入：低有效复位

    // AXI-Lite
    input  wire         s_axi_awvalid,          // 输入：写地址有效
    output wire         s_axi_awready,          // 输出：写地址ready
    input  wire [31:0]  s_axi_awaddr,           // 输入：写地址
    input  wire [2:0]   s_axi_awprot,           // 输入：保护属性（本实现未使用）
    input  wire         s_axi_wvalid,           // 输入：写数据有效
    output wire         s_axi_wready,           // 输出：写数据ready
    input  wire [31:0]  s_axi_wdata,            // 输入：写数据
    input  wire [3:0]   s_axi_wstrb,            // 输入：字节使能
    output wire         s_axi_bvalid,           // 输出：写响应有效
    input  wire         s_axi_bready,           // 输入：写响应ready
    input  wire         s_axi_arvalid,          // 输入：读地址有效
    output wire         s_axi_arready,          // 输出：读地址ready
    input  wire [31:0]  s_axi_araddr,           // 输入：读地址
    input  wire [2:0]   s_axi_arprot,           // 输入：保护属性（本实现未使用）
    output wire         s_axi_rvalid,           // 输出：读数据有效
    input  wire         s_axi_rready,           // 输入：读数据ready
    output wire [31:0]  s_axi_rdata,            // 输出：读数据

    // 状态镜像输入
    input  wire         status_busy_i,          // 输入：busy
    input  wire         status_done_i,          // 输入：done
    input  wire         status_error_i,         // 输入：error
    input  wire         status_irq_pending_i,   // 输入：irq_pending
    input  wire [31:0]  err_code_i,             // 输入：错误码
    input  wire [31:0]  perf_cycle_i,           // 输入：总周期
    input  wire [31:0]  perf_mac_i,             // 输入：MAC 计数
    input  wire [31:0]  perf_stall_mem_i,       // 输入：访存 stall
    input  wire [31:0]  perf_stall_pipe_i,      // 输入：流水 stall
    input  wire [31:0]  perf_dma_data_cyc_i,    // 输入：DMA 有效周期
    input  wire [31:0]  perf_dma_win_cyc_i,     // 输入：DMA 统计窗口周期

    // 任务配置输出
    output wire         cfg_start_pulse_o,      // 输出：启动脉冲 (W1P)
    output wire         cfg_soft_reset_pulse_o, // 输出：软复位脉冲 (W1P)
    output wire         cfg_irq_en_o,           // 输出：中断使能
    output wire         cfg_clk_gate_en_o,      // 输出：门控使能
    output wire         cfg_dfs_en_o,           // 输出：DFS 使能
    output wire [1:0]   cfg_dfs_level_o,        // 输出：DFS 档位
    output wire [7:0]   cfg_core_num_active_o,  // 输出：启用 tile 数
    output wire [3:0]   cfg_simd_mode_o,        // 输出：SIMD 模式
    output wire [3:0]   cfg_op_mode_o,          // 输出：算子模式
    output wire [3:0]   cfg_act_mode_o,         // 输出：激活模式
    output wire [31:0]  cfg_src0_base_o,        // 输出：src0 基址
    output wire [31:0]  cfg_src1_base_o,        // 输出：src1 基址
    output wire [31:0]  cfg_dst_base_o,         // 输出：dst 基址
    output wire [15:0]  cfg_dim_m_o,            // 输出：M
    output wire [15:0]  cfg_dim_n_o,            // 输出：N
    output wire [15:0]  cfg_dim_k_o,            // 输出：K
    output wire [7:0]   cfg_stride_o,           // 输出：stride
    output wire [7:0]   cfg_pad_o,              // 输出：pad
    output wire [15:0]  cfg_qscale_o,           // 输出：qscale
    output wire [7:0]   cfg_qshift_o,           // 输出：qshift
    output wire [7:0]   cfg_qzp_o,              // 输出：qzp

    // W1C 清除输出
    output wire         w1c_done_o,             // 输出：清 done
    output wire         w1c_error_o,            // 输出：清 error
    output wire         w1c_irq_pending_o       // 输出：清 irq_pending
);

// ---------------------------------------------------------------------------
// CSR 地址映射（按 word 地址解码，实际 byte 偏移 = index * 4）
// ---------------------------------------------------------------------------
localparam [5:0] REG_CTRL              = 6'h00; // 0x00
localparam [5:0] REG_STATUS            = 6'h01; // 0x04
localparam [5:0] REG_MODE              = 6'h02; // 0x08
localparam [5:0] REG_SRC0_BASE         = 6'h03; // 0x0C
localparam [5:0] REG_SRC1_BASE         = 6'h04; // 0x10
localparam [5:0] REG_DST_BASE          = 6'h05; // 0x14
localparam [5:0] REG_DIM_MN            = 6'h06; // 0x18
localparam [5:0] REG_DIM_K             = 6'h07; // 0x1C
localparam [5:0] REG_STRIDE_PAD        = 6'h08; // 0x20
localparam [5:0] REG_QNT_CFG           = 6'h09; // 0x24
localparam [5:0] REG_CORE_CFG          = 6'h0A; // 0x28
localparam [5:0] REG_POWER_CFG         = 6'h0B; // 0x2C
localparam [5:0] REG_ERR_CODE          = 6'h0C; // 0x30
localparam [5:0] REG_PERF_CYCLE        = 6'h0D; // 0x34
localparam [5:0] REG_PERF_MAC          = 6'h0E; // 0x38
localparam [5:0] REG_PERF_STALL_MEM    = 6'h0F; // 0x3C
localparam [5:0] REG_PERF_STALL_PIPE   = 6'h10; // 0x40
localparam [5:0] REG_PERF_DMA_DATA_CYC = 6'h11; // 0x44
localparam [5:0] REG_PERF_DMA_WIN_CYC  = 6'h12; // 0x48
localparam [5:0] REG_CAPABILITY        = 6'h13; // 0x4C
localparam [5:0] REG_VERSION           = 6'h14; // 0x50

// CAPABILITY 位定义（当前用于描述 CSR 暴露能力，不等同于 SoC 端到端闭合）
localparam [31:0] CAP_4X4_TILE         = 32'h0000_0001;
localparam [31:0] CAP_CLUSTER          = 32'h0000_0002;
localparam [31:0] CAP_INT8_DATAPATH    = 32'h0000_0004;
localparam [31:0] CAP_PERF_COUNTER     = 32'h0000_0008;
localparam [31:0] CAP_CLK_GATE_CFG     = 32'h0000_0010;
localparam [31:0] CAP_DFS_CFG          = 32'h0000_0020;

localparam [31:0] CAPABILITY_CONST     = CAP_4X4_TILE
                                        | CAP_CLUSTER
                                        | CAP_INT8_DATAPATH
                                        | CAP_PERF_COUNTER
                                        | CAP_CLK_GATE_CFG
                                        | CAP_DFS_CFG;
localparam [31:0] VERSION_CONST        = 32'h2026_0323;

// AXI-Lite 写地址 / 写数据分离握手缓存
reg        aw_seen;
reg        w_seen;
reg [31:0] awaddr_reg;
reg [31:0] wdata_reg;
reg [3:0]  wstrb_reg;
reg        bvalid_reg;
reg        rvalid_reg;
reg [31:0] rdata_reg;

// 配置寄存器
reg        reg_cfg_irq_en;
reg        reg_cfg_clk_gate_en;
reg        reg_cfg_dfs_en;
reg [1:0]  reg_cfg_dfs_level;
reg [7:0]  reg_cfg_core_num_active;
reg [3:0]  reg_cfg_simd_mode;
reg [3:0]  reg_cfg_op_mode;
reg [3:0]  reg_cfg_act_mode;
reg [31:0] reg_cfg_src0_base;
reg [31:0] reg_cfg_src1_base;
reg [31:0] reg_cfg_dst_base;
reg [15:0] reg_cfg_dim_m;
reg [15:0] reg_cfg_dim_n;
reg [15:0] reg_cfg_dim_k;
reg [7:0]  reg_cfg_stride;
reg [7:0]  reg_cfg_pad;
reg [15:0] reg_cfg_qscale;
reg [7:0]  reg_cfg_qshift;
reg [7:0]  reg_cfg_qzp;

// W1P / W1C 单拍输出
reg start_pulse_reg;
reg soft_reset_pulse_reg;
reg w1c_done_reg;
reg w1c_error_reg;
reg w1c_irq_pending_reg;

wire [5:0] aw_word_addr = awaddr_reg[7:2];
wire [5:0] ar_word_addr = s_axi_araddr[7:2];

function [31:0] apply_wstrb;
    input [31:0] oldv;
    input [31:0] newv;
    input [3:0]  wstrb;
    begin
        apply_wstrb = oldv;
        if (wstrb[0]) apply_wstrb[7:0]   = newv[7:0];
        if (wstrb[1]) apply_wstrb[15:8]  = newv[15:8];
        if (wstrb[2]) apply_wstrb[23:16] = newv[23:16];
        if (wstrb[3]) apply_wstrb[31:24] = newv[31:24];
    end
endfunction

wire [31:0] ctrl_shadow        = {29'd0, reg_cfg_irq_en, 2'b00};
wire [31:0] mode_shadow        = {24'd0, reg_cfg_act_mode, reg_cfg_op_mode};
wire [31:0] dim_mn_shadow      = {reg_cfg_dim_m, reg_cfg_dim_n};
wire [31:0] dim_k_shadow       = {16'd0, reg_cfg_dim_k};
wire [31:0] stride_pad_shadow  = {16'd0, reg_cfg_pad, reg_cfg_stride};
wire [31:0] qnt_cfg_shadow     = {reg_cfg_qzp, reg_cfg_qshift, reg_cfg_qscale};
wire [31:0] core_cfg_shadow    = {20'd0, reg_cfg_simd_mode, reg_cfg_core_num_active};
wire [31:0] power_cfg_shadow   = {28'd0, reg_cfg_dfs_level, reg_cfg_dfs_en, reg_cfg_clk_gate_en};

wire [31:0] ctrl_merge_wdata       = apply_wstrb(ctrl_shadow,       wdata_reg, wstrb_reg);
wire [31:0] mode_merge_wdata       = apply_wstrb(mode_shadow,       wdata_reg, wstrb_reg);
wire [31:0] dim_mn_merge_wdata     = apply_wstrb(dim_mn_shadow,     wdata_reg, wstrb_reg);
wire [31:0] dim_k_merge_wdata      = apply_wstrb(dim_k_shadow,      wdata_reg, wstrb_reg);
wire [31:0] stride_pad_merge_wdata = apply_wstrb(stride_pad_shadow, wdata_reg, wstrb_reg);
wire [31:0] qnt_cfg_merge_wdata    = apply_wstrb(qnt_cfg_shadow,    wdata_reg, wstrb_reg);
wire [31:0] core_cfg_merge_wdata   = apply_wstrb(core_cfg_shadow,   wdata_reg, wstrb_reg);
wire [31:0] power_cfg_merge_wdata  = apply_wstrb(power_cfg_shadow,  wdata_reg, wstrb_reg);
wire [31:0] status_zero_merge      = apply_wstrb(32'h0,             wdata_reg, wstrb_reg);

assign s_axi_awready = resetn && !aw_seen && !bvalid_reg;
assign s_axi_wready  = resetn && !w_seen  && !bvalid_reg;
assign s_axi_bvalid  = bvalid_reg;

assign s_axi_arready = resetn && !rvalid_reg;
assign s_axi_rvalid  = rvalid_reg;
assign s_axi_rdata   = rdata_reg;

assign cfg_start_pulse_o      = start_pulse_reg;
assign cfg_soft_reset_pulse_o = soft_reset_pulse_reg;
assign cfg_irq_en_o           = reg_cfg_irq_en;
assign cfg_clk_gate_en_o      = reg_cfg_clk_gate_en;
assign cfg_dfs_en_o           = reg_cfg_dfs_en;
assign cfg_dfs_level_o        = reg_cfg_dfs_level;
assign cfg_core_num_active_o  = reg_cfg_core_num_active;
assign cfg_simd_mode_o        = reg_cfg_simd_mode;
assign cfg_op_mode_o          = reg_cfg_op_mode;
assign cfg_act_mode_o         = reg_cfg_act_mode;
assign cfg_src0_base_o        = reg_cfg_src0_base;
assign cfg_src1_base_o        = reg_cfg_src1_base;
assign cfg_dst_base_o         = reg_cfg_dst_base;
assign cfg_dim_m_o            = reg_cfg_dim_m;
assign cfg_dim_n_o            = reg_cfg_dim_n;
assign cfg_dim_k_o            = reg_cfg_dim_k;
assign cfg_stride_o           = reg_cfg_stride;
assign cfg_pad_o              = reg_cfg_pad;
assign cfg_qscale_o           = reg_cfg_qscale;
assign cfg_qshift_o           = reg_cfg_qshift;
assign cfg_qzp_o              = reg_cfg_qzp;

assign w1c_done_o             = w1c_done_reg;
assign w1c_error_o            = w1c_error_reg;
assign w1c_irq_pending_o      = w1c_irq_pending_reg;

always @(posedge clk) begin
    if (!resetn) begin
        aw_seen               <= 1'b0;
        w_seen                <= 1'b0;
        awaddr_reg            <= 32'h0;
        wdata_reg             <= 32'h0;
        wstrb_reg             <= 4'h0;
        bvalid_reg            <= 1'b0;
        rvalid_reg            <= 1'b0;
        rdata_reg             <= 32'h0;

        reg_cfg_irq_en        <= 1'b0;
        reg_cfg_clk_gate_en   <= 1'b0;
        reg_cfg_dfs_en        <= 1'b0;
        reg_cfg_dfs_level     <= 2'b00;
        reg_cfg_core_num_active <= 8'd0;
        reg_cfg_simd_mode     <= 4'd0;
        reg_cfg_op_mode       <= 4'd0;
        reg_cfg_act_mode      <= 4'd0;
        reg_cfg_src0_base     <= 32'h0;
        reg_cfg_src1_base     <= 32'h0;
        reg_cfg_dst_base      <= 32'h0;
        reg_cfg_dim_m         <= 16'h0;
        reg_cfg_dim_n         <= 16'h0;
        reg_cfg_dim_k         <= 16'h0;
        reg_cfg_stride        <= 8'h0;
        reg_cfg_pad           <= 8'h0;
        reg_cfg_qscale        <= 16'h0;
        reg_cfg_qshift        <= 8'h0;
        reg_cfg_qzp           <= 8'h0;

        start_pulse_reg       <= 1'b0;
        soft_reset_pulse_reg  <= 1'b0;
        w1c_done_reg          <= 1'b0;
        w1c_error_reg         <= 1'b0;
        w1c_irq_pending_reg   <= 1'b0;
    end else begin
        // 单拍输出默认拉低，需要时在本周期置 1
        start_pulse_reg      <= 1'b0;
        soft_reset_pulse_reg <= 1'b0;
        w1c_done_reg         <= 1'b0;
        w1c_error_reg        <= 1'b0;
        w1c_irq_pending_reg  <= 1'b0;

        if (s_axi_awvalid && s_axi_awready) begin
            aw_seen    <= 1'b1;
            awaddr_reg <= s_axi_awaddr;
        end

        if (s_axi_wvalid && s_axi_wready) begin
            w_seen    <= 1'b1;
            wdata_reg <= s_axi_wdata;
            wstrb_reg <= s_axi_wstrb;
        end

        // AW / W 都到齐后执行一次寄存器写
        if (aw_seen && w_seen && !bvalid_reg) begin
            case (aw_word_addr)
                REG_CTRL: begin
                    reg_cfg_irq_en <= ctrl_merge_wdata[2];
                    if (status_zero_merge[0]) start_pulse_reg      <= 1'b1;
                    if (status_zero_merge[1]) soft_reset_pulse_reg <= 1'b1;
                end

                REG_STATUS: begin
                    if (status_zero_merge[1]) w1c_done_reg        <= 1'b1;
                    if (status_zero_merge[2]) w1c_error_reg       <= 1'b1;
                    if (status_zero_merge[3]) w1c_irq_pending_reg <= 1'b1;
                end

                REG_MODE: begin
                    reg_cfg_op_mode  <= mode_merge_wdata[3:0];
                    reg_cfg_act_mode <= mode_merge_wdata[7:4];
                end

                REG_SRC0_BASE: begin
                    reg_cfg_src0_base <= apply_wstrb(reg_cfg_src0_base, wdata_reg, wstrb_reg);
                end

                REG_SRC1_BASE: begin
                    reg_cfg_src1_base <= apply_wstrb(reg_cfg_src1_base, wdata_reg, wstrb_reg);
                end

                REG_DST_BASE: begin
                    reg_cfg_dst_base <= apply_wstrb(reg_cfg_dst_base, wdata_reg, wstrb_reg);
                end

                REG_DIM_MN: begin
                    reg_cfg_dim_m <= dim_mn_merge_wdata[31:16];
                    reg_cfg_dim_n <= dim_mn_merge_wdata[15:0];
                end

                REG_DIM_K: begin
                    reg_cfg_dim_k <= dim_k_merge_wdata[15:0];
                end

                REG_STRIDE_PAD: begin
                    reg_cfg_stride <= stride_pad_merge_wdata[7:0];
                    reg_cfg_pad    <= stride_pad_merge_wdata[15:8];
                end

                REG_QNT_CFG: begin
                    reg_cfg_qscale <= qnt_cfg_merge_wdata[15:0];
                    reg_cfg_qshift <= qnt_cfg_merge_wdata[23:16];
                    reg_cfg_qzp    <= qnt_cfg_merge_wdata[31:24];
                end

                REG_CORE_CFG: begin
                    reg_cfg_core_num_active <= core_cfg_merge_wdata[7:0];
                    reg_cfg_simd_mode       <= core_cfg_merge_wdata[11:8];
                end

                REG_POWER_CFG: begin
                    reg_cfg_clk_gate_en <= power_cfg_merge_wdata[0];
                    reg_cfg_dfs_en      <= power_cfg_merge_wdata[1];
                    reg_cfg_dfs_level   <= power_cfg_merge_wdata[3:2];
                end

                default: begin
                end
            endcase

            bvalid_reg <= 1'b1;
            aw_seen    <= 1'b0;
            w_seen     <= 1'b0;
        end

        if (bvalid_reg && s_axi_bready)
            bvalid_reg <= 1'b0;

        if (s_axi_arvalid && s_axi_arready) begin
            case (ar_word_addr)
                REG_CTRL:              rdata_reg <= ctrl_shadow;
                REG_STATUS:            rdata_reg <= {27'd0, ~status_busy_i, status_irq_pending_i, status_error_i, status_done_i, status_busy_i};
                REG_MODE:              rdata_reg <= mode_shadow;
                REG_SRC0_BASE:         rdata_reg <= reg_cfg_src0_base;
                REG_SRC1_BASE:         rdata_reg <= reg_cfg_src1_base;
                REG_DST_BASE:          rdata_reg <= reg_cfg_dst_base;
                REG_DIM_MN:            rdata_reg <= dim_mn_shadow;
                REG_DIM_K:             rdata_reg <= dim_k_shadow;
                REG_STRIDE_PAD:        rdata_reg <= stride_pad_shadow;
                REG_QNT_CFG:           rdata_reg <= qnt_cfg_shadow;
                REG_CORE_CFG:          rdata_reg <= core_cfg_shadow;
                REG_POWER_CFG:         rdata_reg <= power_cfg_shadow;
                REG_ERR_CODE:          rdata_reg <= err_code_i;
                REG_PERF_CYCLE:        rdata_reg <= perf_cycle_i;
                REG_PERF_MAC:          rdata_reg <= perf_mac_i;
                REG_PERF_STALL_MEM:    rdata_reg <= perf_stall_mem_i;
                REG_PERF_STALL_PIPE:   rdata_reg <= perf_stall_pipe_i;
                REG_PERF_DMA_DATA_CYC: rdata_reg <= perf_dma_data_cyc_i;
                REG_PERF_DMA_WIN_CYC:  rdata_reg <= perf_dma_win_cyc_i;
                REG_CAPABILITY:        rdata_reg <= CAPABILITY_CONST;
                REG_VERSION:           rdata_reg <= VERSION_CONST;
                default:               rdata_reg <= 32'h0;
            endcase
            rvalid_reg <= 1'b1;
        end else if (rvalid_reg && s_axi_rready) begin
            rvalid_reg <= 1'b0;
        end
    end
end

endmodule
