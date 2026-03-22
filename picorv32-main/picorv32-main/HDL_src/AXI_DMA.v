// ============================================================================
// AXI_DMA (Burst V1)
// ----------------------------------------------------------------------------
// 这是一个“AXI-Lite 配置 + AXI Burst 数据搬运”的 DMA 控制器。
//
// 角色划分：
// 1) 控制面（CSR）：
//    - 通过 AXI-Lite 从接口接收 CPU 配置；
//    - 主要寄存器：SRC_ADDR / DST_ADDR / BYTE_LEN / CTRL / STATUS。
//
// 2) 数据面（Burst）：
//    - 通过 AXI Burst 主接口做 mem2mem 搬运；
//    - 流程是“先读突发，再写突发”，循环直到 rem_words=0。
//
// 关键约束：
// - 数据宽度固定 32bit；
// - 地址和长度必须 4 字节对齐；
// - 每次突发长度由 REG_BURST_WORDS 决定，并受 BURST_BUF_WORDS 上限约束。
//
// 典型软件流程：
// 1) 写 SRC/DST/LEN；
// 2) 可选写 BURST_WORDS；
// 3) 写 CTRL.start；
// 4) 轮询 STATUS.done 或等待 irq_dma。
// ============================================================================
module AXI_DMA #(
    parameter integer BURST_BUF_WORDS = 16 // DMA 内部突发缓存深度（word）
) (
    input  wire        aclk,    // 输入：DMA 工作时钟
    input  wire        aresetn, // 输入：低有效复位

    // ------------------------------------------------------------------------
    // AXI-Lite 从接口（CPU 配置 DMA CSR）
    // ------------------------------------------------------------------------
    input  wire        s_axi_awvalid, // 输入：写地址有效
    output wire        s_axi_awready, // 输出：写地址就绪
    input  wire [31:0] s_axi_awaddr,  // 输入：写地址
    input  wire [2:0]  s_axi_awprot,  // 输入：保护属性（本实现未使用）

    input  wire        s_axi_wvalid, // 输入：写数据有效
    output wire        s_axi_wready, // 输出：写数据就绪
    input  wire [31:0] s_axi_wdata,  // 输入：写数据
    input  wire [3:0]  s_axi_wstrb,  // 输入：写字节使能

    output wire        s_axi_bvalid, // 输出：写响应有效
    input  wire        s_axi_bready, // 输入：写响应接收就绪

    input  wire        s_axi_arvalid, // 输入：读地址有效
    output wire        s_axi_arready, // 输出：读地址就绪
    input  wire [31:0] s_axi_araddr,  // 输入：读地址
    input  wire [2:0]  s_axi_arprot,  // 输入：保护属性（本实现未使用）

    output wire        s_axi_rvalid, // 输出：读数据有效
    input  wire        s_axi_rready, // 输入：读数据接收就绪
    output wire [31:0] s_axi_rdata,  // 输出：读数据

    // ------------------------------------------------------------------------
    // AXI Burst 主接口（DMA 数据搬运）
    // ------------------------------------------------------------------------
    output wire        m_axi_awvalid, // 输出：写地址有效
    input  wire        m_axi_awready, // 输入：写地址就绪
    output wire [31:0] m_axi_awaddr,  // 输出：写起始地址
    output wire [7:0]  m_axi_awlen,   // 输出：突发长度（beats-1）
    output wire [2:0]  m_axi_awsize,  // 输出：每 beat 字节数编码（固定 4B）
    output wire [1:0]  m_axi_awburst, // 输出：突发类型（固定 INCR）

    output wire        m_axi_wvalid, // 输出：写数据有效
    input  wire        m_axi_wready, // 输入：写数据就绪
    output wire [31:0] m_axi_wdata,  // 输出：写数据
    output wire [3:0]  m_axi_wstrb,  // 输出：写字节使能（固定 4'hf）
    output wire        m_axi_wlast,  // 输出：本突发最后一个写 beat

    input  wire        m_axi_bvalid, // 输入：写响应有效
    output wire        m_axi_bready, // 输出：写响应接收就绪

    output wire        m_axi_arvalid, // 输出：读地址有效
    input  wire        m_axi_arready, // 输入：读地址就绪
    output wire [31:0] m_axi_araddr,  // 输出：读起始地址
    output wire [7:0]  m_axi_arlen,   // 输出：读突发长度（beats-1）
    output wire [2:0]  m_axi_arsize,  // 输出：每 beat 字节数编码（固定 4B）
    output wire [1:0]  m_axi_arburst, // 输出：突发类型（固定 INCR）

    input  wire        m_axi_rvalid, // 输入：读数据有效
    output wire        m_axi_rready, // 输出：读数据接收就绪
    input  wire [31:0] m_axi_rdata,  // 输入：读数据
    input  wire        m_axi_rlast,  // 输入：本突发最后一个读 beat

    output wire        irq_dma // 输出：DMA 中断请求
);

// ---------------------------------------------------------------------------
// CSR 地址映射（按 word 地址解码，实际 byte 偏移 = index * 4）
// ---------------------------------------------------------------------------
// CTRL   [bit2]=irq_en, [bit1]=soft_reset(W1P), [bit0]=start(W1P)
// STATUS [bit3]=irq_pending, [bit2]=error, [bit1]=done, [bit0]=busy
//        其中 done/error/irq_pending 支持 W1C 清零
localparam [5:0] REG_CTRL         = 6'h00; // 0x00
localparam [5:0] REG_STATUS       = 6'h01; // 0x04
localparam [5:0] REG_SRC_ADDR     = 6'h02; // 0x08
localparam [5:0] REG_DST_ADDR     = 6'h03; // 0x0C
localparam [5:0] REG_BYTE_LEN     = 6'h04; // 0x10
localparam [5:0] REG_ERR_CODE     = 6'h05; // 0x14
localparam [5:0] REG_PERF_CYCLE   = 6'h06; // 0x18
localparam [5:0] REG_PERF_RDWORDS = 6'h07; // 0x1C
localparam [5:0] REG_PERF_WRWORDS = 6'h08; // 0x20
localparam [5:0] REG_BURST_WORDS  = 6'h09; // 0x24

localparam [31:0] ERR_NONE        = 32'h0000_0000;
localparam [31:0] ERR_SRC_ALIGN   = 32'h0000_0001;
localparam [31:0] ERR_DST_ALIGN   = 32'h0000_0002;
localparam [31:0] ERR_LEN_INVALID = 32'h0000_0003;
localparam [31:0] ERR_BUSY_START  = 32'h0000_0004;

// ---------------------------------------------------------------------------
// DMA 状态机
// ---------------------------------------------------------------------------
// ST_IDLE       : 等待 start，做参数合法性检查
// ST_ISSUE_AR   : 发起读地址突发
// ST_READ_BURST : 接收读数据到 burst_buf
// ST_ISSUE_AW   : 发起写地址突发
// ST_WRITE_BURST: 把 burst_buf 连续写回目标地址
// ST_WAIT_B     : 等待写响应，决定结束或下一轮
// ST_DONE       : 单拍收尾，返回 IDLE
localparam [2:0] ST_IDLE        = 3'd0;
localparam [2:0] ST_ISSUE_AR    = 3'd1;
localparam [2:0] ST_READ_BURST  = 3'd2;
localparam [2:0] ST_ISSUE_AW    = 3'd3;
localparam [2:0] ST_WRITE_BURST = 3'd4;
localparam [2:0] ST_WAIT_B      = 3'd5;
localparam [2:0] ST_DONE        = 3'd6;

// AXI-Lite 写地址/写数据分离握手缓存
reg aw_seen;
reg w_seen;
reg [31:0] awaddr_reg;
reg [31:0] wdata_reg;
reg [3:0]  wstrb_reg;
reg bvalid_reg;
reg rvalid_reg;
reg [31:0] rdata_reg;

// CSR 配置寄存器
reg        cfg_irq_en;
reg [7:0]  cfg_burst_words;
reg [31:0] reg_src_addr;
reg [31:0] reg_dst_addr;
reg [31:0] reg_byte_len;

// STATUS 寄存器各状态位
reg        status_busy;
reg        status_done;
reg        status_error;
reg        status_irq_pending;

reg [31:0] reg_err_code;
reg [31:0] reg_perf_cycle;
reg [31:0] reg_perf_rdwords;
reg [31:0] reg_perf_wrwords;

reg        start_req;
reg        soft_reset_req;

reg [2:0]  dma_state;
reg [31:0] cur_src_addr;
reg [31:0] cur_dst_addr;
reg [31:0] rem_words;
reg [7:0]  cur_burst_words;
reg [7:0]  rd_index;
reg [7:0]  wr_index;

// DMA 突发缓存：先读入，再写出
reg [31:0] burst_buf [0:BURST_BUF_WORDS-1];

reg        m_awvalid_reg;
reg [31:0] m_awaddr_reg;
reg [7:0]  m_awlen_reg;

reg        m_wvalid_reg;
reg [31:0] m_wdata_reg;
reg        m_wlast_reg;

reg        m_bready_reg;

reg        m_arvalid_reg;
reg [31:0] m_araddr_reg;
reg [7:0]  m_arlen_reg;

reg        m_rready_reg;

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

function [7:0] clamp_burst_words;
    input [31:0] words_left;
    input [7:0]  cfg_words;
    reg   [7:0]  cfg_eff;
    begin
        cfg_eff = cfg_words;
        if (cfg_eff == 8'd0)
            cfg_eff = 8'd1;
        if (cfg_eff > BURST_BUF_WORDS[7:0])
            cfg_eff = BURST_BUF_WORDS[7:0];
        if (words_left[31:8] != 24'd0)
            clamp_burst_words = cfg_eff;
        else if (words_left[7:0] < cfg_eff)
            clamp_burst_words = words_left[7:0];
        else
            clamp_burst_words = cfg_eff;
    end
endfunction

wire [31:0] ctrl_shadow      = {29'd0, 1'b0, cfg_irq_en, 2'b0};
wire [31:0] status_zero_merge = apply_wstrb(32'h0, wdata_reg, wstrb_reg);
wire [31:0] ctrl_merge_wdata = apply_wstrb(ctrl_shadow, wdata_reg, wstrb_reg);
wire [31:0] burst_merge_wdata = apply_wstrb({24'd0, cfg_burst_words}, wdata_reg, wstrb_reg);

assign s_axi_awready = aresetn && !aw_seen && !bvalid_reg;
assign s_axi_wready  = aresetn && !w_seen && !bvalid_reg;
assign s_axi_bvalid  = bvalid_reg;

assign s_axi_arready = aresetn && !rvalid_reg;
assign s_axi_rvalid  = rvalid_reg;
assign s_axi_rdata   = rdata_reg;

assign m_axi_awvalid = m_awvalid_reg;
assign m_axi_awaddr  = m_awaddr_reg;
assign m_axi_awlen   = m_awlen_reg;
assign m_axi_awsize  = 3'b010; // 4-byte beat（32bit）
assign m_axi_awburst = 2'b01;  // INCR

assign m_axi_wvalid  = m_wvalid_reg;
assign m_axi_wdata   = m_wdata_reg;
assign m_axi_wstrb   = 4'hf;
assign m_axi_wlast   = m_wlast_reg;

assign m_axi_bready  = m_bready_reg;

assign m_axi_arvalid = m_arvalid_reg;
assign m_axi_araddr  = m_araddr_reg;
assign m_axi_arlen   = m_arlen_reg;
assign m_axi_arsize  = 3'b010; // 4-byte beat（32bit）
assign m_axi_arburst = 2'b01;  // INCR

assign m_axi_rready  = m_rready_reg;

// irq_dma 采用“电平型挂起”语义：pending 不清零时保持为 1
assign irq_dma = status_irq_pending;

always @(posedge aclk) begin
    if (!aresetn) begin
        aw_seen            <= 1'b0;
        w_seen             <= 1'b0;
        awaddr_reg         <= 32'h0;
        wdata_reg          <= 32'h0;
        wstrb_reg          <= 4'h0;
        bvalid_reg         <= 1'b0;
        rvalid_reg         <= 1'b0;
        rdata_reg          <= 32'h0;

        cfg_irq_en         <= 1'b0;
        cfg_burst_words    <= 8'd16;
        reg_src_addr       <= 32'h0;
        reg_dst_addr       <= 32'h0;
        reg_byte_len       <= 32'h0;

        status_busy        <= 1'b0;
        status_done        <= 1'b0;
        status_error       <= 1'b0;
        status_irq_pending <= 1'b0;

        reg_err_code       <= ERR_NONE;
        reg_perf_cycle     <= 32'h0;
        reg_perf_rdwords   <= 32'h0;
        reg_perf_wrwords   <= 32'h0;

        start_req          <= 1'b0;
        soft_reset_req     <= 1'b0;

        dma_state          <= ST_IDLE;
        cur_src_addr       <= 32'h0;
        cur_dst_addr       <= 32'h0;
        rem_words          <= 32'h0;
        cur_burst_words    <= 8'd0;
        rd_index           <= 8'd0;
        wr_index           <= 8'd0;

        m_awvalid_reg      <= 1'b0;
        m_awaddr_reg       <= 32'h0;
        m_awlen_reg        <= 8'd0;
        m_wvalid_reg       <= 1'b0;
        m_wdata_reg        <= 32'h0;
        m_wlast_reg        <= 1'b0;
        m_bready_reg       <= 1'b0;
        m_arvalid_reg      <= 1'b0;
        m_araddr_reg       <= 32'h0;
        m_arlen_reg        <= 8'd0;
        m_rready_reg       <= 1'b0;
    end else begin
        // --------------------------------------------------------------------
        // AXI-Lite CSR 控制面
        // --------------------------------------------------------------------
        if (s_axi_awvalid && s_axi_awready) begin
            aw_seen    <= 1'b1;
            awaddr_reg <= s_axi_awaddr;
        end

        if (s_axi_wvalid && s_axi_wready) begin
            w_seen    <= 1'b1;
            wdata_reg <= s_axi_wdata;
            wstrb_reg <= s_axi_wstrb;
        end

        // AW/W 都到齐后执行一次寄存器写入
        if (aw_seen && w_seen && !bvalid_reg) begin
            case (aw_word_addr)
                REG_CTRL: begin
                    cfg_irq_en <= ctrl_merge_wdata[2];
                    if (status_zero_merge[0]) start_req <= 1'b1;      // W1P: start 脉冲
                    if (status_zero_merge[1]) soft_reset_req <= 1'b1; // W1P: soft reset 脉冲
                end
                REG_STATUS: begin
                    if (status_zero_merge[1]) status_done        <= 1'b0; // W1C
                    if (status_zero_merge[2]) status_error       <= 1'b0; // W1C
                    if (status_zero_merge[3]) status_irq_pending <= 1'b0; // W1C
                end
                REG_SRC_ADDR: begin
                    reg_src_addr <= apply_wstrb(reg_src_addr, wdata_reg, wstrb_reg);
                end
                REG_DST_ADDR: begin
                    reg_dst_addr <= apply_wstrb(reg_dst_addr, wdata_reg, wstrb_reg);
                end
                REG_BYTE_LEN: begin
                    reg_byte_len <= apply_wstrb(reg_byte_len, wdata_reg, wstrb_reg);
                end
                REG_BURST_WORDS: begin
                    cfg_burst_words <= burst_merge_wdata[7:0];
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
                REG_CTRL:         rdata_reg <= {29'd0, 1'b0, cfg_irq_en, 2'b0};
                REG_STATUS:       rdata_reg <= {28'd0, status_irq_pending, status_error, status_done, status_busy};
                REG_SRC_ADDR:     rdata_reg <= reg_src_addr;
                REG_DST_ADDR:     rdata_reg <= reg_dst_addr;
                REG_BYTE_LEN:     rdata_reg <= reg_byte_len;
                REG_ERR_CODE:     rdata_reg <= reg_err_code;
                REG_PERF_CYCLE:   rdata_reg <= reg_perf_cycle;
                REG_PERF_RDWORDS: rdata_reg <= reg_perf_rdwords;
                REG_PERF_WRWORDS: rdata_reg <= reg_perf_wrwords;
                REG_BURST_WORDS:  rdata_reg <= {24'd0, cfg_burst_words};
                default:          rdata_reg <= 32'h0;
            endcase
            rvalid_reg <= 1'b1;
        end else if (rvalid_reg && s_axi_rready) begin
            rvalid_reg <= 1'b0;
        end

        // --------------------------------------------------------------------
        // DMA 数据面
        // --------------------------------------------------------------------
        if (soft_reset_req) begin
            soft_reset_req     <= 1'b0;
            start_req          <= 1'b0;
            dma_state          <= ST_IDLE;

            status_busy        <= 1'b0;
            status_done        <= 1'b0;
            status_error       <= 1'b0;
            status_irq_pending <= 1'b0;

            reg_err_code       <= ERR_NONE;
            reg_perf_cycle     <= 32'h0;
            reg_perf_rdwords   <= 32'h0;
            reg_perf_wrwords   <= 32'h0;

            m_awvalid_reg      <= 1'b0;
            m_wvalid_reg       <= 1'b0;
            m_bready_reg       <= 1'b0;
            m_arvalid_reg      <= 1'b0;
            m_rready_reg       <= 1'b0;
            m_wlast_reg        <= 1'b0;
        end else begin
            // busy 周期计数，用于评估吞吐效率
            if (status_busy)
                reg_perf_cycle <= reg_perf_cycle + 1;

            case (dma_state)
                ST_IDLE: begin
                    m_awvalid_reg <= 1'b0;
                    m_wvalid_reg  <= 1'b0;
                    m_bready_reg  <= 1'b0;
                    m_arvalid_reg <= 1'b0;
                    m_rready_reg  <= 1'b0;
                    m_wlast_reg   <= 1'b0;
                    rd_index      <= 8'd0;
                    wr_index      <= 8'd0;

                    // 仅在 IDLE 接收启动；否则报 busy_start 错误
                    if (start_req) begin
                        start_req <= 1'b0;

                        if (status_busy) begin
                            status_error <= 1'b1;
                            reg_err_code <= ERR_BUSY_START;
                            if (cfg_irq_en)
                                status_irq_pending <= 1'b1;
                        end else if (reg_src_addr[1:0] != 2'b00) begin
                            status_error <= 1'b1;
                            status_done  <= 1'b0;
                            reg_err_code <= ERR_SRC_ALIGN;
                            if (cfg_irq_en)
                                status_irq_pending <= 1'b1;
                        end else if (reg_dst_addr[1:0] != 2'b00) begin
                            status_error <= 1'b1;
                            status_done  <= 1'b0;
                            reg_err_code <= ERR_DST_ALIGN;
                            if (cfg_irq_en)
                                status_irq_pending <= 1'b1;
                        end else if ((reg_byte_len == 32'd0) || (reg_byte_len[1:0] != 2'b00)) begin
                            status_error <= 1'b1;
                            status_done  <= 1'b0;
                            reg_err_code <= ERR_LEN_INVALID;
                            if (cfg_irq_en)
                                status_irq_pending <= 1'b1;
                        end else begin
                            status_busy        <= 1'b1;
                            status_done        <= 1'b0;
                            status_error       <= 1'b0;
                            status_irq_pending <= 1'b0;
                            reg_err_code       <= ERR_NONE;
                            reg_perf_cycle     <= 32'h0;
                            reg_perf_rdwords   <= 32'h0;
                            reg_perf_wrwords   <= 32'h0;

                            cur_src_addr       <= reg_src_addr;
                            cur_dst_addr       <= reg_dst_addr;
                            rem_words          <= reg_byte_len >> 2;
                            dma_state          <= ST_ISSUE_AR;
                        end
                    end
                end

                ST_ISSUE_AR: begin
                    // 根据 rem_words 和 cfg_burst_words 计算本轮突发长度
                    if (!m_arvalid_reg) begin
                        cur_burst_words <= clamp_burst_words(rem_words, cfg_burst_words);
                        m_arvalid_reg   <= 1'b1;
                        m_araddr_reg    <= cur_src_addr;
                        m_arlen_reg     <= clamp_burst_words(rem_words, cfg_burst_words) - 8'd1;
                    end
                    if (m_arvalid_reg && m_axi_arready) begin
                        m_arvalid_reg <= 1'b0;
                        m_rready_reg  <= 1'b1;
                        rd_index      <= 8'd0;
                        dma_state     <= ST_READ_BURST;
                    end
                end

                ST_READ_BURST: begin
                    // 把读回数据顺序写入 burst_buf
                    if (m_axi_rvalid && m_rready_reg) begin
                        burst_buf[rd_index] <= m_axi_rdata;
                        reg_perf_rdwords    <= reg_perf_rdwords + 1;
                        rd_index            <= rd_index + 8'd1;

                        if ((rd_index == cur_burst_words - 8'd1) || m_axi_rlast) begin
                            m_rready_reg <= 1'b0;
                            dma_state    <= ST_ISSUE_AW;
                        end
                    end
                end

                ST_ISSUE_AW: begin
                    // 写地址与读地址一一对应（本轮同样突发长度）
                    if (!m_awvalid_reg) begin
                        m_awvalid_reg <= 1'b1;
                        m_awaddr_reg  <= cur_dst_addr;
                        m_awlen_reg   <= cur_burst_words - 8'd1;
                    end
                    if (m_awvalid_reg && m_axi_awready) begin
                        m_awvalid_reg <= 1'b0;
                        wr_index      <= 8'd0;
                        dma_state     <= ST_WRITE_BURST;
                    end
                end

                ST_WRITE_BURST: begin
                    // 连续发送写数据，减少空泡周期
                    if (!m_wvalid_reg && (wr_index < cur_burst_words)) begin
                        m_wvalid_reg <= 1'b1;
                        m_wdata_reg  <= burst_buf[wr_index];
                        m_wlast_reg  <= (wr_index == cur_burst_words - 8'd1);
                    end

                    if (m_wvalid_reg && m_axi_wready) begin
                        reg_perf_wrwords <= reg_perf_wrwords + 1;

                        if (wr_index == cur_burst_words - 8'd1) begin
                            m_wvalid_reg <= 1'b0;
                            m_bready_reg <= 1'b1;
                            m_wlast_reg  <= 1'b0;
                            dma_state    <= ST_WAIT_B;
                        end else begin
                            // 保持 W 通道流式发送，避免每 beat 之间出现气泡
                            wr_index     <= wr_index + 8'd1;
                            m_wvalid_reg <= 1'b1;
                            m_wdata_reg  <= burst_buf[wr_index + 8'd1];
                            m_wlast_reg  <= (wr_index + 8'd1 == cur_burst_words - 8'd1);
                        end
                    end
                end

                ST_WAIT_B: begin
                    // 收到写响应后，决定“结束”还是“下一轮突发”
                    if (m_axi_bvalid && m_bready_reg) begin
                        m_bready_reg <= 1'b0;

                        if (rem_words <= cur_burst_words) begin
                            status_busy <= 1'b0;
                            status_done <= 1'b1;
                            if (cfg_irq_en)
                                status_irq_pending <= 1'b1;
                            dma_state <= ST_DONE;
                        end else begin
                            rem_words    <= rem_words - cur_burst_words;
                            cur_src_addr <= cur_src_addr + {22'd0, cur_burst_words, 2'b00};
                            cur_dst_addr <= cur_dst_addr + {22'd0, cur_burst_words, 2'b00};
                            dma_state    <= ST_ISSUE_AR;
                        end
                    end
                end

                ST_DONE: begin
                    dma_state <= ST_IDLE;
                end

                default: begin
                    dma_state <= ST_IDLE;
                end
            endcase
        end
    end
end

endmodule
