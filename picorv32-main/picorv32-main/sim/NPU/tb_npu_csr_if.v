`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 文件名: tb_npu_csr_if.v
// 功能  : npu_csr_if 的基础自检
//////////////////////////////////////////////////////////////////////////////////
module tb_npu_csr_if;

    localparam [31:0] ADDR_CTRL              = 32'h0000_0000;
    localparam [31:0] ADDR_STATUS            = 32'h0000_0004;
    localparam [31:0] ADDR_MODE              = 32'h0000_0008;
    localparam [31:0] ADDR_SRC0_BASE         = 32'h0000_000C;
    localparam [31:0] ADDR_SRC1_BASE         = 32'h0000_0010;
    localparam [31:0] ADDR_DST_BASE          = 32'h0000_0014;
    localparam [31:0] ADDR_DIM_MN            = 32'h0000_0018;
    localparam [31:0] ADDR_DIM_K             = 32'h0000_001C;
    localparam [31:0] ADDR_STRIDE_PAD        = 32'h0000_0020;
    localparam [31:0] ADDR_QNT_CFG           = 32'h0000_0024;
    localparam [31:0] ADDR_CORE_CFG          = 32'h0000_0028;
    localparam [31:0] ADDR_POWER_CFG         = 32'h0000_002C;
    localparam [31:0] ADDR_ERR_CODE          = 32'h0000_0030;
    localparam [31:0] ADDR_PERF_CYCLE        = 32'h0000_0034;
    localparam [31:0] ADDR_PERF_MAC          = 32'h0000_0038;
    localparam [31:0] ADDR_PERF_STALL_MEM    = 32'h0000_003C;
    localparam [31:0] ADDR_PERF_STALL_PIPE   = 32'h0000_0040;
    localparam [31:0] ADDR_PERF_DMA_DATA_CYC = 32'h0000_0044;
    localparam [31:0] ADDR_PERF_DMA_WIN_CYC  = 32'h0000_0048;
    localparam [31:0] ADDR_CAPABILITY        = 32'h0000_004C;
    localparam [31:0] ADDR_VERSION           = 32'h0000_0050;

    localparam [31:0] CAPABILITY_EXP         = 32'h0000_003F;
    localparam [31:0] VERSION_EXP            = 32'h2026_0323;

    reg         clk;
    reg         resetn;

    reg         s_axi_awvalid;
    wire        s_axi_awready;
    reg [31:0]  s_axi_awaddr;
    reg [2:0]   s_axi_awprot;
    reg         s_axi_wvalid;
    wire        s_axi_wready;
    reg [31:0]  s_axi_wdata;
    reg [3:0]   s_axi_wstrb;
    wire        s_axi_bvalid;
    reg         s_axi_bready;
    reg         s_axi_arvalid;
    wire        s_axi_arready;
    reg [31:0]  s_axi_araddr;
    reg [2:0]   s_axi_arprot;
    wire        s_axi_rvalid;
    reg         s_axi_rready;
    wire [31:0] s_axi_rdata;

    reg         status_busy_i;
    reg         status_done_i;
    reg         status_error_i;
    reg         status_irq_pending_i;
    reg [31:0]  err_code_i;
    reg [31:0]  perf_cycle_i;
    reg [31:0]  perf_mac_i;
    reg [31:0]  perf_stall_mem_i;
    reg [31:0]  perf_stall_pipe_i;
    reg [31:0]  perf_dma_data_cyc_i;
    reg [31:0]  perf_dma_win_cyc_i;

    wire        cfg_start_pulse_o;
    wire        cfg_soft_reset_pulse_o;
    wire        cfg_irq_en_o;
    wire        cfg_clk_gate_en_o;
    wire        cfg_dfs_en_o;
    wire [1:0]  cfg_dfs_level_o;
    wire [7:0]  cfg_core_num_active_o;
    wire [3:0]  cfg_simd_mode_o;
    wire [3:0]  cfg_op_mode_o;
    wire [3:0]  cfg_act_mode_o;
    wire [31:0] cfg_src0_base_o;
    wire [31:0] cfg_src1_base_o;
    wire [31:0] cfg_dst_base_o;
    wire [15:0] cfg_dim_m_o;
    wire [15:0] cfg_dim_n_o;
    wire [15:0] cfg_dim_k_o;
    wire [7:0]  cfg_stride_o;
    wire [7:0]  cfg_pad_o;
    wire [15:0] cfg_qscale_o;
    wire [7:0]  cfg_qshift_o;
    wire [7:0]  cfg_qzp_o;
    wire        w1c_done_o;
    wire        w1c_error_o;
    wire        w1c_irq_pending_o;

    reg [31:0] rd_data;

    npu_csr_if dut (
        .clk(clk),
        .resetn(resetn),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awprot(s_axi_awprot),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arprot(s_axi_arprot),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .s_axi_rdata(s_axi_rdata),
        .status_busy_i(status_busy_i),
        .status_done_i(status_done_i),
        .status_error_i(status_error_i),
        .status_irq_pending_i(status_irq_pending_i),
        .err_code_i(err_code_i),
        .perf_cycle_i(perf_cycle_i),
        .perf_mac_i(perf_mac_i),
        .perf_stall_mem_i(perf_stall_mem_i),
        .perf_stall_pipe_i(perf_stall_pipe_i),
        .perf_dma_data_cyc_i(perf_dma_data_cyc_i),
        .perf_dma_win_cyc_i(perf_dma_win_cyc_i),
        .cfg_start_pulse_o(cfg_start_pulse_o),
        .cfg_soft_reset_pulse_o(cfg_soft_reset_pulse_o),
        .cfg_irq_en_o(cfg_irq_en_o),
        .cfg_clk_gate_en_o(cfg_clk_gate_en_o),
        .cfg_dfs_en_o(cfg_dfs_en_o),
        .cfg_dfs_level_o(cfg_dfs_level_o),
        .cfg_core_num_active_o(cfg_core_num_active_o),
        .cfg_simd_mode_o(cfg_simd_mode_o),
        .cfg_op_mode_o(cfg_op_mode_o),
        .cfg_act_mode_o(cfg_act_mode_o),
        .cfg_src0_base_o(cfg_src0_base_o),
        .cfg_src1_base_o(cfg_src1_base_o),
        .cfg_dst_base_o(cfg_dst_base_o),
        .cfg_dim_m_o(cfg_dim_m_o),
        .cfg_dim_n_o(cfg_dim_n_o),
        .cfg_dim_k_o(cfg_dim_k_o),
        .cfg_stride_o(cfg_stride_o),
        .cfg_pad_o(cfg_pad_o),
        .cfg_qscale_o(cfg_qscale_o),
        .cfg_qshift_o(cfg_qshift_o),
        .cfg_qzp_o(cfg_qzp_o),
        .w1c_done_o(w1c_done_o),
        .w1c_error_o(w1c_error_o),
        .w1c_irq_pending_o(w1c_irq_pending_o)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic check_eq32(
        input [31:0] got,
        input [31:0] exp,
        input [255:0] name
    );
        begin
            if (got !== exp) begin
                $display("[TB] FAIL %0s got=0x%08x exp=0x%08x", name, got, exp);
                $finish(1);
            end else begin
                $display("[TB] PASS %0s = 0x%08x", name, got);
            end
        end
    endtask

    task automatic check_bit(
        input got,
        input exp,
        input [255:0] name
    );
        begin
            if (got !== exp) begin
                $display("[TB] FAIL %0s got=%0d exp=%0d", name, got, exp);
                $finish(1);
            end else begin
                $display("[TB] PASS %0s = %0d", name, got);
            end
        end
    endtask

    task automatic axi_write(
        input [31:0] addr,
        input [31:0] data,
        input [3:0]  strb
    );
        reg aw_done;
        reg w_done;
        begin
            aw_done = 1'b0;
            w_done  = 1'b0;

            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1'b1;
            s_axi_wdata   <= data;
            s_axi_wstrb   <= strb;
            s_axi_wvalid  <= 1'b1;

            while (!aw_done || !w_done) begin
                @(posedge clk);
                if (!aw_done && s_axi_awready) begin
                    aw_done       = 1'b1;
                    s_axi_awvalid <= 1'b0;
                end
                if (!w_done && s_axi_wready) begin
                    w_done       = 1'b1;
                    s_axi_wvalid <= 1'b0;
                end
            end

            s_axi_bready <= 1'b1;
            while (!s_axi_bvalid)
                @(posedge clk);
            @(posedge clk);
            s_axi_bready <= 1'b0;
        end
    endtask

    task automatic axi_read(
        input  [31:0] addr,
        output [31:0] data
    );
        reg ar_done;
        begin
            ar_done = 1'b0;

            s_axi_araddr  <= addr;
            s_axi_arvalid <= 1'b1;
            s_axi_rready  <= 1'b1;

            while (!ar_done) begin
                @(posedge clk);
                if (s_axi_arready) begin
                    ar_done       = 1'b1;
                    s_axi_arvalid <= 1'b0;
                end
            end

            while (!s_axi_rvalid)
                @(posedge clk);
            data = s_axi_rdata;
            @(posedge clk);
            s_axi_rready <= 1'b0;
        end
    endtask

    task automatic write_ctrl_expect_pulse(
        input [31:0] data,
        input        exp_start,
        input        exp_soft_reset
    );
        reg aw_done;
        reg w_done;
        begin
            aw_done = 1'b0;
            w_done  = 1'b0;

            s_axi_awaddr  <= ADDR_CTRL;
            s_axi_awvalid <= 1'b1;
            s_axi_wdata   <= data;
            s_axi_wstrb   <= 4'hf;
            s_axi_wvalid  <= 1'b1;

            while (!aw_done || !w_done) begin
                @(posedge clk);
                if (!aw_done && s_axi_awready) begin
                    aw_done       = 1'b1;
                    s_axi_awvalid <= 1'b0;
                end
                if (!w_done && s_axi_wready) begin
                    w_done       = 1'b1;
                    s_axi_wvalid <= 1'b0;
                end
            end

            s_axi_bready <= 1'b1;
            while (!s_axi_bvalid)
                @(posedge clk);

            check_bit(cfg_start_pulse_o, exp_start, "ctrl.start_pulse");
            check_bit(cfg_soft_reset_pulse_o, exp_soft_reset, "ctrl.soft_reset_pulse");

            @(posedge clk);
            s_axi_bready <= 1'b0;

            check_bit(cfg_start_pulse_o, 1'b0, "ctrl.start_pulse_clear");
            check_bit(cfg_soft_reset_pulse_o, 1'b0, "ctrl.soft_reset_pulse_clear");
        end
    endtask

    task automatic write_status_expect_w1c(
        input [31:0] data,
        input        exp_done,
        input        exp_error,
        input        exp_irq
    );
        reg aw_done;
        reg w_done;
        begin
            aw_done = 1'b0;
            w_done  = 1'b0;

            s_axi_awaddr  <= ADDR_STATUS;
            s_axi_awvalid <= 1'b1;
            s_axi_wdata   <= data;
            s_axi_wstrb   <= 4'hf;
            s_axi_wvalid  <= 1'b1;

            while (!aw_done || !w_done) begin
                @(posedge clk);
                if (!aw_done && s_axi_awready) begin
                    aw_done       = 1'b1;
                    s_axi_awvalid <= 1'b0;
                end
                if (!w_done && s_axi_wready) begin
                    w_done       = 1'b1;
                    s_axi_wvalid <= 1'b0;
                end
            end

            s_axi_bready <= 1'b1;
            while (!s_axi_bvalid)
                @(posedge clk);

            check_bit(w1c_done_o, exp_done, "status.w1c_done");
            check_bit(w1c_error_o, exp_error, "status.w1c_error");
            check_bit(w1c_irq_pending_o, exp_irq, "status.w1c_irq_pending");

            @(posedge clk);
            s_axi_bready <= 1'b0;

            check_bit(w1c_done_o, 1'b0, "status.w1c_done_clear");
            check_bit(w1c_error_o, 1'b0, "status.w1c_error_clear");
            check_bit(w1c_irq_pending_o, 1'b0, "status.w1c_irq_pending_clear");
        end
    endtask

    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_npu_csr_if.vcd");
            $dumpvars(0, tb_npu_csr_if);
        end

        resetn               = 1'b0;
        s_axi_awvalid        = 1'b0;
        s_axi_awaddr         = 32'h0;
        s_axi_awprot         = 3'b000;
        s_axi_wvalid         = 1'b0;
        s_axi_wdata          = 32'h0;
        s_axi_wstrb          = 4'h0;
        s_axi_bready         = 1'b0;
        s_axi_arvalid        = 1'b0;
        s_axi_araddr         = 32'h0;
        s_axi_arprot         = 3'b000;
        s_axi_rready         = 1'b0;

        status_busy_i        = 1'b0;
        status_done_i        = 1'b0;
        status_error_i       = 1'b0;
        status_irq_pending_i = 1'b0;
        err_code_i           = 32'h0;
        perf_cycle_i         = 32'h0;
        perf_mac_i           = 32'h0;
        perf_stall_mem_i     = 32'h0;
        perf_stall_pipe_i    = 32'h0;
        perf_dma_data_cyc_i  = 32'h0;
        perf_dma_win_cyc_i   = 32'h0;

        repeat (3) @(posedge clk);
        resetn <= 1'b1;
        repeat (2) @(posedge clk);

        check_bit(cfg_irq_en_o, 1'b0, "reset.irq_en");
        check_bit(cfg_clk_gate_en_o, 1'b0, "reset.clk_gate_en");
        check_bit(cfg_dfs_en_o, 1'b0, "reset.dfs_en");

        axi_read(ADDR_STATUS, rd_data);
        check_eq32(rd_data, 32'h0000_0010, "status.idle_after_reset");

        axi_read(ADDR_CAPABILITY, rd_data);
        check_eq32(rd_data, CAPABILITY_EXP, "capability");

        axi_read(ADDR_VERSION, rd_data);
        check_eq32(rd_data, VERSION_EXP, "version");

        axi_write(ADDR_MODE, 32'h0000_005A, 4'hf);
        axi_read(ADDR_MODE, rd_data);
        check_eq32(rd_data, 32'h0000_005A, "mode.readback");

        axi_write(ADDR_SRC0_BASE, 32'h1000_0040, 4'hf);
        axi_write(ADDR_SRC1_BASE, 32'h1000_0080, 4'hf);
        axi_write(ADDR_DST_BASE,  32'h1000_00C0, 4'hf);
        axi_write(ADDR_DIM_MN,    32'h0010_0020, 4'hf);
        axi_write(ADDR_DIM_K,     32'h0000_0030, 4'hf);
        axi_write(ADDR_STRIDE_PAD,32'h0000_0201, 4'hf);
        axi_write(ADDR_QNT_CFG,   32'h0706_1234, 4'hf);
        axi_write(ADDR_CORE_CFG,  32'h0000_0304, 4'hf);
        axi_write(ADDR_POWER_CFG, 32'h0000_000D, 4'hf);

        check_eq32(cfg_src0_base_o, 32'h1000_0040, "cfg.src0_base");
        check_eq32(cfg_src1_base_o, 32'h1000_0080, "cfg.src1_base");
        check_eq32(cfg_dst_base_o,  32'h1000_00C0, "cfg.dst_base");
        check_eq32({16'd0, cfg_dim_m_o}, 32'h0000_0010, "cfg.dim_m");
        check_eq32({16'd0, cfg_dim_n_o}, 32'h0000_0020, "cfg.dim_n");
        check_eq32({16'd0, cfg_dim_k_o}, 32'h0000_0030, "cfg.dim_k");
        check_eq32({24'd0, cfg_stride_o}, 32'h0000_0001, "cfg.stride");
        check_eq32({24'd0, cfg_pad_o}, 32'h0000_0002, "cfg.pad");
        check_eq32({16'd0, cfg_qscale_o}, 32'h0000_1234, "cfg.qscale");
        check_eq32({24'd0, cfg_qshift_o}, 32'h0000_0006, "cfg.qshift");
        check_eq32({24'd0, cfg_qzp_o}, 32'h0000_0007, "cfg.qzp");
        check_eq32({24'd0, cfg_core_num_active_o}, 32'h0000_0004, "cfg.core_num_active");
        check_eq32({28'd0, cfg_simd_mode_o}, 32'h0000_0003, "cfg.simd_mode");
        check_bit(cfg_clk_gate_en_o, 1'b1, "cfg.clk_gate_en");
        check_bit(cfg_dfs_en_o, 1'b0, "cfg.dfs_en");
        check_eq32({30'd0, cfg_dfs_level_o}, 32'h0000_0003, "cfg.dfs_level");

        write_ctrl_expect_pulse(32'h0000_0005, 1'b1, 1'b0);
        check_bit(cfg_irq_en_o, 1'b1, "ctrl.irq_en_latched");
        axi_read(ADDR_CTRL, rd_data);
        check_eq32(rd_data, 32'h0000_0004, "ctrl.readback_after_start");

        write_ctrl_expect_pulse(32'h0000_0006, 1'b0, 1'b1);
        check_bit(cfg_irq_en_o, 1'b1, "ctrl.irq_en_kept");

        status_busy_i        = 1'b1;
        status_done_i        = 1'b1;
        status_error_i       = 1'b1;
        status_irq_pending_i = 1'b1;
        err_code_i           = 32'h0000_0003;
        perf_cycle_i         = 32'h0000_0100;
        perf_mac_i           = 32'h0000_0200;
        perf_stall_mem_i     = 32'h0000_0300;
        perf_stall_pipe_i    = 32'h0000_0400;
        perf_dma_data_cyc_i  = 32'h0000_0500;
        perf_dma_win_cyc_i   = 32'h0000_0600;
        @(posedge clk);

        axi_read(ADDR_STATUS, rd_data);
        check_eq32(rd_data, 32'h0000_000F, "status.mirror_busy");
        axi_read(ADDR_ERR_CODE, rd_data);
        check_eq32(rd_data, 32'h0000_0003, "err_code.mirror");
        axi_read(ADDR_PERF_CYCLE, rd_data);
        check_eq32(rd_data, 32'h0000_0100, "perf_cycle.mirror");
        axi_read(ADDR_PERF_MAC, rd_data);
        check_eq32(rd_data, 32'h0000_0200, "perf_mac.mirror");
        axi_read(ADDR_PERF_STALL_MEM, rd_data);
        check_eq32(rd_data, 32'h0000_0300, "perf_stall_mem.mirror");
        axi_read(ADDR_PERF_STALL_PIPE, rd_data);
        check_eq32(rd_data, 32'h0000_0400, "perf_stall_pipe.mirror");
        axi_read(ADDR_PERF_DMA_DATA_CYC, rd_data);
        check_eq32(rd_data, 32'h0000_0500, "perf_dma_data_cyc.mirror");
        axi_read(ADDR_PERF_DMA_WIN_CYC, rd_data);
        check_eq32(rd_data, 32'h0000_0600, "perf_dma_win_cyc.mirror");

        write_status_expect_w1c(32'h0000_000E, 1'b1, 1'b1, 1'b1);

        $display("[TB] ALL PASS.");
        $finish(0);
    end

endmodule
