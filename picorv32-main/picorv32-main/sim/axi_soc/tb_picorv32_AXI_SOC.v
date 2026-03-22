`timescale 1 ns / 1 ps

// =============================================================================
// tb_picorv32_AXI_SOC
// -----------------------------------------------------------------------------
// 这是 AXI Demo SoC 的顶层仿真 testbench，核心职责是：
// 1) 产生时钟/复位并驱动 SoC 运行；
// 2) 通过参数 PROG_MEM_INIT_FILE 指定程序镜像（hex）；
// 3) 监视 trap 信号，在程序结束时给出 PASS/FAIL；
// 4) 提供超时保护，防止仿真卡死；
// 5) 按需导出 VCD 波形。
//
// 说明：
// - 这里不再用 testbench 自己去 $readmemh，而是把 hex 路径传给 SoC 参数；
// - SoC 内部 Program RAM 再用该参数完成初始化。
// =============================================================================
module tb_picorv32_AXI_SOC #(
    // 程序存储器初始化文件路径（相对工程根目录）
    // 默认使用 sim/axi_soc/sw/demo.hex
    parameter PROG_MEM_INIT_FILE = "sim/axi_soc/sw/demo.hex"
);

// Data RAM 词深度（与 SoC 里 DATA_ADDR_WIDTH=14 对应，2^14 个 32-bit word）
localparam integer DATA_WORDS = 1 << 14;

// 基本激励信号
reg clk = 1'b0;
reg resetn = 1'b0;

// 当前 demo 暂不注入中断，先固定全 0
reg [31:0] irq = 32'h0;

// 从 DUT 观察到的状态/调试信号
wire [31:0] eoi;
wire trap;
wire trace_valid;
wire [35:0] trace_data;

// testbench 内部控制变量
integer i;
integer cycle_counter;
integer max_cycles;
reg ignore_trap;

// 100MHz 时钟：周期 10ns（#5 翻转一次）
always #5 clk = ~clk;

// -----------------------------------------------------------------------------
// DUT 实例化
// 将 testbench 参数 PROG_MEM_INIT_FILE 透传到 SoC 顶层
// -----------------------------------------------------------------------------
picorv32_AXI_SOC #(
    .PROG_MEM_INIT_FILE(PROG_MEM_INIT_FILE)
) dut (
    .clk(clk),
    .resetn(resetn),
    .irq(irq),
    .eoi(eoi),
    .trap(trap),
    .trace_valid(trace_valid),
    .trace_data(trace_data)
);

// -----------------------------------------------------------------------------
// Debug aliases for "Fetch-Decode-Execute" study.
// These map deep internal CPU signals to TB top level so they are easy to add
// in Vivado wave window and in auto wave presets.
// -----------------------------------------------------------------------------
wire [7:0]  dbg_cpu_state        = dut.u_cpu.picorv32_core.cpu_state;
wire        dbg_decoder_trigger  = dut.u_cpu.picorv32_core.decoder_trigger;
wire        dbg_decoder_trigger_q = dut.u_cpu.picorv32_core.decoder_trigger_q;
wire        dbg_mem_do_rinst     = dut.u_cpu.picorv32_core.mem_do_rinst;
wire        dbg_mem_do_rdata     = dut.u_cpu.picorv32_core.mem_do_rdata;
wire        dbg_mem_do_wdata     = dut.u_cpu.picorv32_core.mem_do_wdata;
wire [31:0] dbg_reg_pc           = dut.u_cpu.picorv32_core.reg_pc;
wire [31:0] dbg_reg_next_pc      = dut.u_cpu.picorv32_core.reg_next_pc;
wire [5:0]  dbg_decoded_rd       = dut.u_cpu.picorv32_core.decoded_rd;
wire [5:0]  dbg_decoded_rs1      = dut.u_cpu.picorv32_core.decoded_rs1;
wire [4:0]  dbg_decoded_rs2      = dut.u_cpu.picorv32_core.decoded_rs2;
wire [31:0] dbg_decoded_imm      = dut.u_cpu.picorv32_core.decoded_imm;
wire        dbg_instr_jal        = dut.u_cpu.picorv32_core.instr_jal;
wire        dbg_instr_addi       = dut.u_cpu.picorv32_core.instr_addi;
wire        dbg_instr_sw         = dut.u_cpu.picorv32_core.instr_sw;
wire        dbg_instr_ecall_ebreak = dut.u_cpu.picorv32_core.instr_ecall_ebreak;

// DMA debug aliases
wire        dbg_dma_irq_pending  = dut.u_dma.status_irq_pending;
wire        dbg_dma_busy         = dut.u_dma.status_busy;
wire        dbg_dma_done         = dut.u_dma.status_done;
wire        dbg_dma_error        = dut.u_dma.status_error;
wire [31:0] dbg_dma_src_addr     = dut.u_dma.reg_src_addr;
wire [31:0] dbg_dma_dst_addr     = dut.u_dma.reg_dst_addr;
wire [31:0] dbg_dma_byte_len     = dut.u_dma.reg_byte_len;
wire [31:0] dbg_dma_err_code     = dut.u_dma.reg_err_code;
wire [3:0]  dbg_dma_state        = dut.u_dma.dma_state;
wire [31:0] dbg_dma_perf_cycle   = dut.u_dma.reg_perf_cycle;
wire [31:0] dbg_dma_perf_rdwords = dut.u_dma.reg_perf_rdwords;
wire [31:0] dbg_dma_perf_wrwords = dut.u_dma.reg_perf_wrwords;
wire [7:0]  dbg_dma_burst_words  = dut.u_dma.cfg_burst_words;

integer dma_busy_cycles;
integer dma_rd_beats;
integer dma_wr_beats;

// -----------------------------------------------------------------------------
// 初始过程：参数读取、RAM 清理、可选波形、释放复位
// -----------------------------------------------------------------------------
initial begin
    // 周期计数器清零
    cycle_counter = 0;
    dma_busy_cycles = 0;
    dma_rd_beats = 0;
    dma_wr_beats = 0;

    // 默认超时周期；可用 +maxcycles=xxx 覆盖
    max_cycles = 200000;
    if (!$value$plusargs("maxcycles=%d", max_cycles)) begin
        // 未传入 plusarg 时使用默认值
    end

    // +ignore_trap：遇到 trap 不立即退出（便于继续观察波形）
    ignore_trap = $test$plusargs("ignore_trap");

    // 仿真启动时清空 Data RAM，保证 PASS/FAIL 判定起点一致
    for (i = 0; i < DATA_WORDS; i = i + 1)
        dut.u_data_mem.mem[i] = 32'h0;

    // 打印当前程序镜像路径，便于确认加载的 hex 是否正确
    $display("[TB_AXI_SOC] program init file: %0s", PROG_MEM_INIT_FILE);

    // +vcd：开启波形导出
    if ($test$plusargs("vcd")) begin
        $dumpfile("tb_picorv32_AXI_SOC.vcd");
        $dumpvars(0, tb_picorv32_AXI_SOC);
    end

    // 保持复位 20 个时钟周期，等待系统稳定后再启动
    repeat (20) @(posedge clk);
    resetn <= 1'b1;
end

// -----------------------------------------------------------------------------
// 主监控过程：计数、超时保护、trap 结果判定
// -----------------------------------------------------------------------------
always @(posedge clk) begin
    // 复位期间计数器保持 0；释放复位后每拍 +1
    if (!resetn)
        cycle_counter <= 0;
    else
        cycle_counter <= cycle_counter + 1;

    // 超时退出：程序异常跑飞时终止仿真
    if (resetn && cycle_counter > max_cycles) begin
        $display("[TB_AXI_SOC] TIMEOUT at cycle %0d", cycle_counter);
        $finish;
    end

    // trap 代表 CPU 进入终止状态（此 demo 把它当作“程序结束点”）
    if (resetn && trap) begin
        $display("[TB_AXI_SOC] trap at cycle %0d", cycle_counter);
        $display("[TB_AXI_SOC] data_mem[0]=0x%08x", dut.u_data_mem.mem[0]);
        $display("[TB_AXI_SOC] DMA burst_words=%0d perf_cycle=%0d rdwords=%0d wrwords=%0d",
                 dbg_dma_burst_words, dbg_dma_perf_cycle, dbg_dma_perf_rdwords, dbg_dma_perf_wrwords);
        if (dbg_dma_perf_cycle != 0) begin
            $display("[TB_AXI_SOC] DMA payload utilization= %0d%% (%0d beats / %0d cycles)",
                     ((dbg_dma_perf_rdwords + dbg_dma_perf_wrwords) * 100) / dbg_dma_perf_cycle,
                     (dbg_dma_perf_rdwords + dbg_dma_perf_wrwords),
                     dbg_dma_perf_cycle);
        end
        if (dma_busy_cycles != 0) begin
            $display("[TB_AXI_SOC] DMA observed utilization= %0d%% (rd=%0d wr=%0d, busy_cycles=%0d)",
                     ((dma_rd_beats + dma_wr_beats) * 100) / dma_busy_cycles,
                     dma_rd_beats, dma_wr_beats, dma_busy_cycles);
        end

        // demo 约定：程序结束时应把 12 写入 data_mem[0]
        // 满足则 PASS，否则 FAIL
        if (dut.u_data_mem.mem[0] == 32'd12)
            $display("[TB_AXI_SOC] PASS");
        else
            $display("[TB_AXI_SOC] FAIL (unexpected data_mem[0])");

        // 默认 trap 后结束仿真；传 +ignore_trap 可继续运行
        if (!ignore_trap)
            $finish;
    end
end

// -----------------------------------------------------------------------------
// DMA burst utilization observers
// -----------------------------------------------------------------------------
always @(posedge clk) begin
    if (!resetn) begin
        dma_busy_cycles <= 0;
        dma_rd_beats <= 0;
        dma_wr_beats <= 0;
    end else begin
        if (dbg_dma_busy)
            dma_busy_cycles <= dma_busy_cycles + 1;
        if (dut.dma_mem_axi_rvalid && dut.dma_mem_axi_rready)
            dma_rd_beats <= dma_rd_beats + 1;
        if (dut.dma_mem_axi_wvalid && dut.dma_mem_axi_wready)
            dma_wr_beats <= dma_wr_beats + 1;
    end
end

endmodule
