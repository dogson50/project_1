// ============================================================================
// picorv32_AXI_SOC
// ----------------------------------------------------------------------------
// 这是当前 demo SoC 顶层：
// - picorv32_axi CPU：执行程序，统一通过 AXI-Lite 访问存储器与外设
// - Program RAM：程序存储器，地址段 0x0000_xxxx
// - Data RAM（双口）：A 口给 CPU（AXI-Lite），B 口给 DMA（AXI Burst）
// - AXI_DMA：CPU 配置 DMA 寄存器后，DMA 用 Burst 搬运数据
// - AXI_Interconnect_2M3S：CPU 到 Program/Data/DMA-CSR 的地址路由
//   注意：DMA 数据面已旁路互连，直接连到 Data RAM 的 B 口
//
// Memory map (default):
// - Program RAM : 0x0000_0000 ~ 0x0000_FFFF
// - Data RAM    : 0x2000_0000 ~ 0x2000_FFFF
// - DMA CSR     : 0x4000_0000 ~ 0x4000_FFFF
// ============================================================================
module picorv32_AXI_SOC #(
    parameter integer PROG_ADDR_WIDTH = 14,
    parameter integer DATA_ADDR_WIDTH = 14,
    parameter PROG_MEM_INIT_FILE = "",

    parameter [31:0] PROG_BASE_ADDR = 32'h0000_0000,
    parameter [31:0] PROG_ADDR_MASK = 32'hffff_0000,
    parameter [31:0] DATA_BASE_ADDR = 32'h2000_0000,
    parameter [31:0] DATA_ADDR_MASK = 32'hffff_0000,
    parameter [31:0] DMA_BASE_ADDR  = 32'h4000_0000,
    parameter [31:0] DMA_ADDR_MASK  = 32'hffff_0000
) (
    input  wire        clk,         // 输入：系统时钟
    input  wire        resetn,      // 输入：低有效复位
    input  wire [31:0] irq,         // 输入：外部中断请求位图（送入 CPU）
    output wire [31:0] eoi,         // 输出：CPU 中断结束（End-Of-Interrupt）位图
    output wire        trap,        // 输出：CPU 进入 trap/终止状态
    output wire        trace_valid, // 输出：trace_data 有效标志
    output wire [35:0] trace_data   // 输出：CPU 指令执行跟踪信息
);

// ----------------------------------------------------------------------------
// CPU master AXI-Lite signals
// ----------------------------------------------------------------------------
wire        cpu_axi_awvalid;
wire        cpu_axi_awready;
wire [31:0] cpu_axi_awaddr;
wire [2:0]  cpu_axi_awprot;
wire        cpu_axi_wvalid;
wire        cpu_axi_wready;
wire [31:0] cpu_axi_wdata;
wire [3:0]  cpu_axi_wstrb;
wire        cpu_axi_bvalid;
wire        cpu_axi_bready;
wire        cpu_axi_arvalid;
wire        cpu_axi_arready;
wire [31:0] cpu_axi_araddr;
wire [2:0]  cpu_axi_arprot;
wire        cpu_axi_rvalid;
wire        cpu_axi_rready;
wire [31:0] cpu_axi_rdata;

// ----------------------------------------------------------------------------
// DMA master AXI Burst signals (to Data RAM Port-B)
// ----------------------------------------------------------------------------
wire        dma_mem_axi_awvalid;
wire        dma_mem_axi_awready;
wire [31:0] dma_mem_axi_awaddr;
wire [7:0]  dma_mem_axi_awlen;
wire [2:0]  dma_mem_axi_awsize;
wire [1:0]  dma_mem_axi_awburst;
wire        dma_mem_axi_wvalid;
wire        dma_mem_axi_wready;
wire [31:0] dma_mem_axi_wdata;
wire [3:0]  dma_mem_axi_wstrb;
wire        dma_mem_axi_wlast;
wire        dma_mem_axi_bvalid;
wire        dma_mem_axi_bready;
wire        dma_mem_axi_arvalid;
wire        dma_mem_axi_arready;
wire [31:0] dma_mem_axi_araddr;
wire [7:0]  dma_mem_axi_arlen;
wire [2:0]  dma_mem_axi_arsize;
wire [1:0]  dma_mem_axi_arburst;
wire        dma_mem_axi_rvalid;
wire        dma_mem_axi_rready;
wire [31:0] dma_mem_axi_rdata;
wire        dma_mem_axi_rlast;

// ----------------------------------------------------------------------------
// Slave 0: Program RAM port
// ----------------------------------------------------------------------------
wire        p0_axi_awvalid;
wire        p0_axi_awready;
wire [31:0] p0_axi_awaddr;
wire [2:0]  p0_axi_awprot;
wire        p0_axi_wvalid;
wire        p0_axi_wready;
wire [31:0] p0_axi_wdata;
wire [3:0]  p0_axi_wstrb;
wire        p0_axi_bvalid;
wire        p0_axi_bready;
wire        p0_axi_arvalid;
wire        p0_axi_arready;
wire [31:0] p0_axi_araddr;
wire [2:0]  p0_axi_arprot;
wire        p0_axi_rvalid;
wire        p0_axi_rready;
wire [31:0] p0_axi_rdata;

// ----------------------------------------------------------------------------
// Slave 1: Data RAM port
// ----------------------------------------------------------------------------
wire        p1_axi_awvalid;
wire        p1_axi_awready;
wire [31:0] p1_axi_awaddr;
wire [2:0]  p1_axi_awprot;
wire        p1_axi_wvalid;
wire        p1_axi_wready;
wire [31:0] p1_axi_wdata;
wire [3:0]  p1_axi_wstrb;
wire        p1_axi_bvalid;
wire        p1_axi_bready;
wire        p1_axi_arvalid;
wire        p1_axi_arready;
wire [31:0] p1_axi_araddr;
wire [2:0]  p1_axi_arprot;
wire        p1_axi_rvalid;
wire        p1_axi_rready;
wire [31:0] p1_axi_rdata;

// ----------------------------------------------------------------------------
// Slave 2: DMA CSR port
// ----------------------------------------------------------------------------
wire        p2_axi_awvalid;
wire        p2_axi_awready;
wire [31:0] p2_axi_awaddr;
wire [2:0]  p2_axi_awprot;
wire        p2_axi_wvalid;
wire        p2_axi_wready;
wire [31:0] p2_axi_wdata;
wire [3:0]  p2_axi_wstrb;
wire        p2_axi_bvalid;
wire        p2_axi_bready;
wire        p2_axi_arvalid;
wire        p2_axi_arready;
wire [31:0] p2_axi_araddr;
wire [2:0]  p2_axi_arprot;
wire        p2_axi_rvalid;
wire        p2_axi_rready;
wire [31:0] p2_axi_rdata;

wire        pcpi_valid;
wire [31:0] pcpi_insn;
wire [31:0] pcpi_rs1;
wire [31:0] pcpi_rs2;

wire irq_dma;
wire [31:0] cpu_irq = irq | {31'd0, irq_dma};

// ----------------------------------------------------------------------------
// 模块1：picorv32_axi（CPU 内核）
// 功能说明：
// 1) 从 Program RAM 取指并执行 RV32IM 指令；
// 2) 通过 AXI-Lite 主接口访问 Data RAM / DMA CSR；
// 3) 对外输出 trap、trace、eoi 等调试/中断相关信号。
// ----------------------------------------------------------------------------
picorv32_axi #(
    .ENABLE_COUNTERS      (1),
    .ENABLE_COUNTERS64    (1),
    .ENABLE_REGS_16_31    (1),
    .ENABLE_REGS_DUALPORT (1),
    .TWO_STAGE_SHIFT      (1),
    .BARREL_SHIFTER       (0),
    .TWO_CYCLE_COMPARE    (0),
    .TWO_CYCLE_ALU        (0),
    .COMPRESSED_ISA       (0),
    .CATCH_MISALIGN       (1),
    .CATCH_ILLINSN        (1),
    .ENABLE_PCPI          (0),
    .ENABLE_MUL           (1),
    .ENABLE_FAST_MUL      (0),
    .ENABLE_DIV           (1),
    .ENABLE_IRQ           (1),
    .ENABLE_IRQ_QREGS     (1),
    .ENABLE_IRQ_TIMER     (1),
    .ENABLE_TRACE         (1),
    .REGS_INIT_ZERO       (0),
    .MASKED_IRQ           (32'h0000_0000),
    .LATCHED_IRQ          (32'hffff_ffff),
    .PROGADDR_RESET       (PROG_BASE_ADDR),
    .PROGADDR_IRQ         (32'h0000_0010),
    .STACKADDR            (DATA_BASE_ADDR + (1 << (DATA_ADDR_WIDTH + 2)) - 4)
) u_cpu (
    // 时钟复位与运行状态
    .clk             (clk),          // 输入：CPU 时钟
    .resetn          (resetn),       // 输入：CPU 低有效复位
    .trap            (trap),         // 输出：CPU trap

    // AXI-Lite 主接口（CPU 发请求，互连返回响应）
    .mem_axi_awvalid (cpu_axi_awvalid),
    .mem_axi_awready (cpu_axi_awready),
    .mem_axi_awaddr  (cpu_axi_awaddr),
    .mem_axi_awprot  (cpu_axi_awprot),
    .mem_axi_wvalid  (cpu_axi_wvalid),
    .mem_axi_wready  (cpu_axi_wready),
    .mem_axi_wdata   (cpu_axi_wdata),
    .mem_axi_wstrb   (cpu_axi_wstrb),
    .mem_axi_bvalid  (cpu_axi_bvalid),
    .mem_axi_bready  (cpu_axi_bready),
    .mem_axi_arvalid (cpu_axi_arvalid),
    .mem_axi_arready (cpu_axi_arready),
    .mem_axi_araddr  (cpu_axi_araddr),
    .mem_axi_arprot  (cpu_axi_arprot),
    .mem_axi_rvalid  (cpu_axi_rvalid),
    .mem_axi_rready  (cpu_axi_rready),
    .mem_axi_rdata   (cpu_axi_rdata),

    // PCPI 扩展协处理器接口（当前未使用，固定关闭）
    .pcpi_valid      (pcpi_valid),
    .pcpi_insn       (pcpi_insn),
    .pcpi_rs1        (pcpi_rs1),
    .pcpi_rs2        (pcpi_rs2),
    .pcpi_wr         (1'b0),
    .pcpi_rd         (32'h0),
    .pcpi_wait       (1'b0),
    .pcpi_ready      (1'b0),

    // 中断接口
    .irq             (cpu_irq),      // 输入：外部 IRQ 与 DMA IRQ 的合并结果
    .eoi             (eoi),          // 输出：中断结束位图

    // trace 调试接口
    .trace_valid     (trace_valid),
    .trace_data      (trace_data)
);

// ----------------------------------------------------------------------------
// 模块2：AXI_DMA（DMA 控制器）
// 功能说明：
// 1) 从 AXI-Lite CSR 口接收 CPU 配置（src/dst/len/start 等）；
// 2) 通过 AXI Burst 主口在 Data RAM 内做高速搬运；
// 3) 搬运结束后产生 irq_dma 给 CPU。
// ----------------------------------------------------------------------------
AXI_DMA #(
    .BURST_BUF_WORDS  (64)
) u_dma (
    // 时钟复位
    .aclk            (clk),          // 输入：DMA 时钟
    .aresetn         (resetn),       // 输入：DMA 低有效复位

    // AXI-Lite 从接口（CPU 访问 DMA CSR）
    .s_axi_awvalid   (p2_axi_awvalid),
    .s_axi_awready   (p2_axi_awready),
    .s_axi_awaddr    (p2_axi_awaddr),
    .s_axi_awprot    (p2_axi_awprot),
    .s_axi_wvalid    (p2_axi_wvalid),
    .s_axi_wready    (p2_axi_wready),
    .s_axi_wdata     (p2_axi_wdata),
    .s_axi_wstrb     (p2_axi_wstrb),
    .s_axi_bvalid    (p2_axi_bvalid),
    .s_axi_bready    (p2_axi_bready),
    .s_axi_arvalid   (p2_axi_arvalid),
    .s_axi_arready   (p2_axi_arready),
    .s_axi_araddr    (p2_axi_araddr),
    .s_axi_arprot    (p2_axi_arprot),
    .s_axi_rvalid    (p2_axi_rvalid),
    .s_axi_rready    (p2_axi_rready),
    .s_axi_rdata     (p2_axi_rdata),

    // AXI Burst 主接口（DMA 读写 Data RAM B 口）
    .m_axi_awvalid   (dma_mem_axi_awvalid),
    .m_axi_awready   (dma_mem_axi_awready),
    .m_axi_awaddr    (dma_mem_axi_awaddr),
    .m_axi_awlen     (dma_mem_axi_awlen),
    .m_axi_awsize    (dma_mem_axi_awsize),
    .m_axi_awburst   (dma_mem_axi_awburst),
    .m_axi_wvalid    (dma_mem_axi_wvalid),
    .m_axi_wready    (dma_mem_axi_wready),
    .m_axi_wdata     (dma_mem_axi_wdata),
    .m_axi_wstrb     (dma_mem_axi_wstrb),
    .m_axi_wlast     (dma_mem_axi_wlast),
    .m_axi_bvalid    (dma_mem_axi_bvalid),
    .m_axi_bready    (dma_mem_axi_bready),
    .m_axi_arvalid   (dma_mem_axi_arvalid),
    .m_axi_arready   (dma_mem_axi_arready),
    .m_axi_araddr    (dma_mem_axi_araddr),
    .m_axi_arlen     (dma_mem_axi_arlen),
    .m_axi_arsize    (dma_mem_axi_arsize),
    .m_axi_arburst   (dma_mem_axi_arburst),
    .m_axi_rvalid    (dma_mem_axi_rvalid),
    .m_axi_rready    (dma_mem_axi_rready),
    .m_axi_rdata     (dma_mem_axi_rdata),
    .m_axi_rlast     (dma_mem_axi_rlast),

    .irq_dma         (irq_dma)       // 输出：DMA 中断请求
);

// ----------------------------------------------------------------------------
// 模块3：AXI_Interconnect_2M3S（2主3从互连）
// 功能说明：
// 1) 根据地址把 CPU 请求路由到 Program RAM / Data RAM / DMA CSR；
// 2) 处理握手与返回路径；
// 3) 当前 m1 端口未用（DMA 数据面已旁路互连）。
// ----------------------------------------------------------------------------
AXI_Interconnect_2M3S #(
    .PORT0_BASE      (PROG_BASE_ADDR),
    .PORT0_MASK      (PROG_ADDR_MASK),
    .PORT1_BASE      (DATA_BASE_ADDR),
    .PORT1_MASK      (DATA_ADDR_MASK),
    .PORT2_BASE      (DMA_BASE_ADDR),
    .PORT2_MASK      (DMA_ADDR_MASK)
) u_interconnect (
    // 时钟复位
    .aclk            (clk),          // 输入：互连时钟
    .aresetn         (resetn),       // 输入：互连低有效复位

    // Master 0：CPU AXI-Lite 主口
    .m0_axi_awvalid  (cpu_axi_awvalid),
    .m0_axi_awready  (cpu_axi_awready),
    .m0_axi_awaddr   (cpu_axi_awaddr),
    .m0_axi_awprot   (cpu_axi_awprot),
    .m0_axi_wvalid   (cpu_axi_wvalid),
    .m0_axi_wready   (cpu_axi_wready),
    .m0_axi_wdata    (cpu_axi_wdata),
    .m0_axi_wstrb    (cpu_axi_wstrb),
    .m0_axi_bvalid   (cpu_axi_bvalid),
    .m0_axi_bready   (cpu_axi_bready),
    .m0_axi_arvalid  (cpu_axi_arvalid),
    .m0_axi_arready  (cpu_axi_arready),
    .m0_axi_araddr   (cpu_axi_araddr),
    .m0_axi_arprot   (cpu_axi_arprot),
    .m0_axi_rvalid   (cpu_axi_rvalid),
    .m0_axi_rready   (cpu_axi_rready),
    .m0_axi_rdata    (cpu_axi_rdata),

    // Master 1：预留/禁用（本版本 DMA 不走互连）
    .m1_axi_awvalid  (1'b0),
    .m1_axi_awready  (),
    .m1_axi_awaddr   (32'h0),
    .m1_axi_awprot   (3'b0),
    .m1_axi_wvalid   (1'b0),
    .m1_axi_wready   (),
    .m1_axi_wdata    (32'h0),
    .m1_axi_wstrb    (4'h0),
    .m1_axi_bvalid   (),
    .m1_axi_bready   (1'b0),
    .m1_axi_arvalid  (1'b0),
    .m1_axi_arready  (),
    .m1_axi_araddr   (32'h0),
    .m1_axi_arprot   (3'b0),
    .m1_axi_rvalid   (),
    .m1_axi_rready   (1'b0),
    .m1_axi_rdata    (),

    // Slave 0：Program RAM 端口
    .s0_axi_awvalid  (p0_axi_awvalid),
    .s0_axi_awready  (p0_axi_awready),
    .s0_axi_awaddr   (p0_axi_awaddr),
    .s0_axi_awprot   (p0_axi_awprot),
    .s0_axi_wvalid   (p0_axi_wvalid),
    .s0_axi_wready   (p0_axi_wready),
    .s0_axi_wdata    (p0_axi_wdata),
    .s0_axi_wstrb    (p0_axi_wstrb),
    .s0_axi_bvalid   (p0_axi_bvalid),
    .s0_axi_bready   (p0_axi_bready),
    .s0_axi_arvalid  (p0_axi_arvalid),
    .s0_axi_arready  (p0_axi_arready),
    .s0_axi_araddr   (p0_axi_araddr),
    .s0_axi_arprot   (p0_axi_arprot),
    .s0_axi_rvalid   (p0_axi_rvalid),
    .s0_axi_rready   (p0_axi_rready),
    .s0_axi_rdata    (p0_axi_rdata),

    // Slave 1：Data RAM Port-A 端口
    .s1_axi_awvalid  (p1_axi_awvalid),
    .s1_axi_awready  (p1_axi_awready),
    .s1_axi_awaddr   (p1_axi_awaddr),
    .s1_axi_awprot   (p1_axi_awprot),
    .s1_axi_wvalid   (p1_axi_wvalid),
    .s1_axi_wready   (p1_axi_wready),
    .s1_axi_wdata    (p1_axi_wdata),
    .s1_axi_wstrb    (p1_axi_wstrb),
    .s1_axi_bvalid   (p1_axi_bvalid),
    .s1_axi_bready   (p1_axi_bready),
    .s1_axi_arvalid  (p1_axi_arvalid),
    .s1_axi_arready  (p1_axi_arready),
    .s1_axi_araddr   (p1_axi_araddr),
    .s1_axi_arprot   (p1_axi_arprot),
    .s1_axi_rvalid   (p1_axi_rvalid),
    .s1_axi_rready   (p1_axi_rready),
    .s1_axi_rdata    (p1_axi_rdata),

    // Slave 2：DMA CSR 端口
    .s2_axi_awvalid  (p2_axi_awvalid),
    .s2_axi_awready  (p2_axi_awready),
    .s2_axi_awaddr   (p2_axi_awaddr),
    .s2_axi_awprot   (p2_axi_awprot),
    .s2_axi_wvalid   (p2_axi_wvalid),
    .s2_axi_wready   (p2_axi_wready),
    .s2_axi_wdata    (p2_axi_wdata),
    .s2_axi_wstrb    (p2_axi_wstrb),
    .s2_axi_bvalid   (p2_axi_bvalid),
    .s2_axi_bready   (p2_axi_bready),
    .s2_axi_arvalid  (p2_axi_arvalid),
    .s2_axi_arready  (p2_axi_arready),
    .s2_axi_araddr   (p2_axi_araddr),
    .s2_axi_arprot   (p2_axi_arprot),
    .s2_axi_rvalid   (p2_axi_rvalid),
    .s2_axi_rready   (p2_axi_rready),
    .s2_axi_rdata    (p2_axi_rdata)
);

// ----------------------------------------------------------------------------
// 模块4：AXI_Block_RAM（Program RAM）
// 功能说明：
// 1) 作为程序存储器（可由 PROG_MEM_INIT_FILE 初始化）；
// 2) 通过 AXI-Lite 被 CPU 访问（主要读指令，也支持写）。
// ----------------------------------------------------------------------------
AXI_Block_RAM #(
    .ADDR_WIDTH       (PROG_ADDR_WIDTH),
    .INIT_FILE        (PROG_MEM_INIT_FILE)
) u_prog_mem (
    .aclk             (clk),          // 输入：RAM 时钟
    .aresetn          (resetn),       // 输入：RAM 低有效复位

    // AXI-Lite 从接口（连接互连 s0）
    .s_axi_awvalid    (p0_axi_awvalid),
    .s_axi_awready    (p0_axi_awready),
    .s_axi_awaddr     (p0_axi_awaddr),
    .s_axi_awprot     (p0_axi_awprot),
    .s_axi_wvalid     (p0_axi_wvalid),
    .s_axi_wready     (p0_axi_wready),
    .s_axi_wdata      (p0_axi_wdata),
    .s_axi_wstrb      (p0_axi_wstrb),
    .s_axi_bvalid     (p0_axi_bvalid),
    .s_axi_bready     (p0_axi_bready),
    .s_axi_arvalid    (p0_axi_arvalid),
    .s_axi_arready    (p0_axi_arready),
    .s_axi_araddr     (p0_axi_araddr),
    .s_axi_arprot     (p0_axi_arprot),
    .s_axi_rvalid     (p0_axi_rvalid),
    .s_axi_rready     (p0_axi_rready),
    .s_axi_rdata      (p0_axi_rdata)
);

// ----------------------------------------------------------------------------
// 模块5：AXI_DualPort_RAM（Data RAM）
// 功能说明：
// 1) A 口（AXI-Lite）给 CPU 正常 load/store；
// 2) B 口（AXI Burst）给 DMA 高吞吐搬运；
// 3) 通过双口结构避免 CPU 与 DMA 在数据面争同一端口。
// ----------------------------------------------------------------------------
AXI_DualPort_RAM #(
    .ADDR_WIDTH       (DATA_ADDR_WIDTH),
    .INIT_FILE        ("")
) u_data_mem (
    .aclk             (clk),          // 输入：RAM 时钟
    .aresetn          (resetn),       // 输入：RAM 低有效复位

    // Port-A（AXI-Lite 从接口）：CPU 访问 Data RAM
    .s0_axi_awvalid   (p1_axi_awvalid),
    .s0_axi_awready   (p1_axi_awready),
    .s0_axi_awaddr    (p1_axi_awaddr),
    .s0_axi_awprot    (p1_axi_awprot),
    .s0_axi_wvalid    (p1_axi_wvalid),
    .s0_axi_wready    (p1_axi_wready),
    .s0_axi_wdata     (p1_axi_wdata),
    .s0_axi_wstrb     (p1_axi_wstrb),
    .s0_axi_bvalid    (p1_axi_bvalid),
    .s0_axi_bready    (p1_axi_bready),
    .s0_axi_arvalid   (p1_axi_arvalid),
    .s0_axi_arready   (p1_axi_arready),
    .s0_axi_araddr    (p1_axi_araddr),
    .s0_axi_arprot    (p1_axi_arprot),
    .s0_axi_rvalid    (p1_axi_rvalid),
    .s0_axi_rready    (p1_axi_rready),
    .s0_axi_rdata     (p1_axi_rdata),

    // Port-B（AXI Burst 从接口）：DMA 直连高速搬运
    .s1_axi_awvalid   (dma_mem_axi_awvalid),
    .s1_axi_awready   (dma_mem_axi_awready),
    .s1_axi_awaddr    (dma_mem_axi_awaddr),
    .s1_axi_awlen     (dma_mem_axi_awlen),
    .s1_axi_awsize    (dma_mem_axi_awsize),
    .s1_axi_awburst   (dma_mem_axi_awburst),
    .s1_axi_wvalid    (dma_mem_axi_wvalid),
    .s1_axi_wready    (dma_mem_axi_wready),
    .s1_axi_wdata     (dma_mem_axi_wdata),
    .s1_axi_wstrb     (dma_mem_axi_wstrb),
    .s1_axi_wlast     (dma_mem_axi_wlast),
    .s1_axi_bvalid    (dma_mem_axi_bvalid),
    .s1_axi_bready    (dma_mem_axi_bready),
    .s1_axi_arvalid   (dma_mem_axi_arvalid),
    .s1_axi_arready   (dma_mem_axi_arready),
    .s1_axi_araddr    (dma_mem_axi_araddr),
    .s1_axi_arlen     (dma_mem_axi_arlen),
    .s1_axi_arsize    (dma_mem_axi_arsize),
    .s1_axi_arburst   (dma_mem_axi_arburst),
    .s1_axi_rvalid    (dma_mem_axi_rvalid),
    .s1_axi_rready    (dma_mem_axi_rready),
    .s1_axi_rdata     (dma_mem_axi_rdata),
    .s1_axi_rlast     (dma_mem_axi_rlast)
);

endmodule
