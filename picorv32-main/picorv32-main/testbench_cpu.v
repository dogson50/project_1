`timescale 1 ns / 1 ps

// =============================================================================
// testbench_cpu.v
// -----------------------------------------------------------------------------
// 这是一个“CPU 内核级”最小仿真平台，直接例化 picorv32 原生内存接口版本：
// - 不使用 AXI 封装（相比 testbench.v 更轻量）
// - 用片内行为 RAM + 两个简单 MMIO 地址构成仿真环境
// - 支持通过 plusargs 选择程序来源、自测模式、超时和退出行为
//
// 常用 plusargs：
//   +selftest_alu              运行内置 ALU 自测程序（无需外部 firmware）
//   +firmware=<path>           从 hex 文件加载程序到 memory[]
//   +maxcycles=<N>             设置仿真超时周期（默认 200000）
//   +vcd                       导出 testbench_cpu.vcd 波形
//   +ignore_exit               忽略 MMIO 退出口写入（继续仿真）
//   +ignore_trap               忽略 trap（仅打印一次提示并继续）
// =============================================================================
module testbench_cpu;
	// 内存深度：16384 words * 4B = 64KB。
	localparam integer MEM_WORDS = 16384;
	// 简单 MMIO 地址映射：
	//   0x1000_0000: UART 输出（写低 8 位字符）
	//   0x1000_0004: 退出码（0=PASS，非0=FAIL）
	localparam [31:0] MMIO_UART = 32'h1000_0000;
	localparam [31:0] MMIO_EXIT = 32'h1000_0004;

	// 全局时钟/复位与 trap 监视信号。
	reg clk = 1'b0;
	reg resetn = 1'b0;
	wire trap;

	// picorv32 原生内存接口（valid/ready 单拍握手）。
	// mem_instr=1 表示取指访问，=0 表示数据访问。
	wire        mem_valid;
	wire        mem_instr;
	reg         mem_ready = 1'b0;
	wire [31:0] mem_addr;
	wire [31:0] mem_wdata;
	wire [3:0]  mem_wstrb;
	reg  [31:0] mem_rdata = 32'h0;

	// 行为内存：32 位字寻址数组。
	reg [31:0] memory [0:MEM_WORDS-1];
	// 用于接收 +firmware=<path> 的字符串缓冲。
	reg [1023:0] firmware_file;

	// 仿真辅助变量。
	integer i;
	integer max_cycles;
	integer cycle_counter;
	reg ignore_exit;
	reg ignore_trap;
	reg trap_reported;

	// 100MHz 等效时钟（周期 10ns）。
	always #5 clk = ~clk;

	// ----------------------------------------------------------------------------
	// 初始化阶段：
	// 1) RAM 先填 NOP（addi x0, x0, 0）
	// 2) 根据 plusargs 选择程序来源
	// 3) 解析仿真控制参数
	// 4) 可选导出 VCD
	// 5) 延迟若干拍后释放复位
	// ----------------------------------------------------------------------------
	initial begin
		// 默认把所有内存填成 NOP，避免未初始化区域出现 X 传播。
		for (i = 0; i < MEM_WORDS; i = i + 1)
			memory[i] = 32'h00000013;

		// 内置最小 ALU 自测：
		// 期望 x3 = x1 + x2 = 12，正确则写 MMIO_EXIT=0，错误写 1。
		if ($test$plusargs("selftest_alu")) begin
			$display("[TB] run built-in selftest_alu");
			memory[0]  = 32'h00500093; // addi x1, x0, 5
			memory[1]  = 32'h00700113; // addi x2, x0, 7
			memory[2]  = 32'h002081b3; // add  x3, x1, x2
			memory[3]  = 32'h00c00213; // addi x4, x0, 12
			memory[4]  = 32'h00419863; // bne  x3, x4, fail
			memory[5]  = 32'h10000537; // lui  x10, 0x10000
			memory[6]  = 32'h00450513; // addi x10, x10, 4
			memory[7]  = 32'h00052023; // sw   x0, 0(x10) => PASS
			memory[8]  = 32'h10000537; // fail: lui  x10, 0x10000
			memory[9]  = 32'h00450513; // addi x10, x10, 4
			memory[10] = 32'h00100293; // addi x5, x0, 1
			memory[11] = 32'h00552023; // sw   x5, 0(x10) => FAIL
		end else if ($value$plusargs("firmware=%s", firmware_file)) begin
			// 指定了外部 firmware 文件：直接读入 memory[]。
			$display("[TB] load firmware: %0s", firmware_file);
			$readmemh(firmware_file, memory);
		end else begin
			// 未指定 firmware 且未启用 selftest 时，运行一个内置 demo：
			// 持续对地址 1020 进行读改写循环，便于观察基本总线行为。
			$display("[TB] no +firmware specified, use built-in demo program");
			memory[0] = 32'h3fc00093; // li x1,1020
			memory[1] = 32'h0000a023; // sw x0,0(x1)
			memory[2] = 32'h0000a103; // loop: lw x2,0(x1)
			memory[3] = 32'h00110113; // addi x2,x2,1
			memory[4] = 32'h0020a023; // sw x2,0(x1)
			memory[5] = 32'hff5ff06f; // j loop
		end

		// 仿真超时保护：避免死循环导致仿真无法退出。
		max_cycles = 200000;
		if (!$value$plusargs("maxcycles=%d", max_cycles)) begin
			// Keep default max_cycles.
		end

		// 退出策略控制：
		// - ignore_exit: 忽略软件写 MMIO_EXIT 触发的 finish
		// - ignore_trap: 忽略 trap 触发的 finish
		ignore_exit = $test$plusargs("ignore_exit");
		ignore_trap = $test$plusargs("ignore_trap");
		trap_reported = 1'b0;

		if (ignore_exit)
			$display("[TB] +ignore_exit enabled");
		if (ignore_trap)
			$display("[TB] +ignore_trap enabled");

		// 可选波形导出，便于 GTKWave/Vivado 查看时序。
		if ($test$plusargs("vcd")) begin
			$dumpfile("testbench_cpu.vcd");
			$dumpvars(0, testbench_cpu);
		end

		// 给系统留一点复位稳定时间，再释放 resetn。
		repeat (20) @(posedge clk);
		resetn <= 1'b1;
	end

	// ----------------------------------------------------------------------------
	// 周期计数、超时与 trap 行为控制
	// ----------------------------------------------------------------------------
	always @(posedge clk) begin
		if (!resetn)
			cycle_counter <= 0;
		else
			cycle_counter <= cycle_counter + 1;

		// 超时结束：用于发现卡死、异常等待等问题。
		if (resetn && cycle_counter > max_cycles) begin
			$display("[TB] TIMEOUT at cycle %0d", cycle_counter);
			$finish;
		end

		// trap 处理策略：
		// 默认 trap 即结束；ignore_trap 时只提示一次并继续仿真。
		if (resetn && trap) begin
			if (!ignore_trap) begin
				$display("[TB] CPU trap at cycle %0d", cycle_counter);
				$finish;
			end else if (!trap_reported) begin
				$display("[TB] CPU trap at cycle %0d (ignored)", cycle_counter);
				trap_reported <= 1'b1;
			end
		end
	end

	// ----------------------------------------------------------------------------
	// 原生内存接口模型（同步单拍 ready 风格）：
	// - 每个周期先把 mem_ready 拉低
	// - 检测到 mem_valid 后，根据地址类型返回数据/执行写入
	// - 对 RAM、UART、EXIT 各自处理
	// ----------------------------------------------------------------------------
	always @(posedge clk) begin
		// 缺省不应答，只有命中一次请求才在该拍拉高 ready。
		mem_ready <= 1'b0;

		// 这里只处理“当前还未应答”的请求，避免同一请求重复执行。
		if (mem_valid && !mem_ready) begin
			// -----------------------
			// 普通 RAM 区域访问
			// -----------------------
			if (mem_addr[31:2] < MEM_WORDS) begin
				mem_ready <= 1'b1;
				// 读路径：总是返回当前字。
				mem_rdata <= memory[mem_addr[31:2]];

				// 写路径：按字节写使能 mem_wstrb 更新对应 byte lane。
				if (mem_wstrb[0]) memory[mem_addr[31:2]][7:0]   <= mem_wdata[7:0];
				if (mem_wstrb[1]) memory[mem_addr[31:2]][15:8]  <= mem_wdata[15:8];
				if (mem_wstrb[2]) memory[mem_addr[31:2]][23:16] <= mem_wdata[23:16];
				if (mem_wstrb[3]) memory[mem_addr[31:2]][31:24] <= mem_wdata[31:24];
			// -----------------------
			// UART 输出口（字符打印）
			// -----------------------
			end else if (mem_addr == MMIO_UART) begin
				mem_ready <= 1'b1;
				mem_rdata <= 32'h0;
				if (|mem_wstrb)
					$write("%c", mem_wdata[7:0]);
			// -----------------------
			// EXIT 退出口（测试结果上报）
			// -----------------------
			end else if (mem_addr == MMIO_EXIT) begin
				mem_ready <= 1'b1;
				mem_rdata <= 32'h0;
				if (|mem_wstrb) begin
					if (mem_wdata == 32'h0)
						$display("\n[TB] PASS (exit code 0) at cycle %0d", cycle_counter);
					else
						$display("\n[TB] FAIL (exit code %0d) at cycle %0d", mem_wdata, cycle_counter);
					if (!ignore_exit)
						$finish;
					else
						$display("[TB] MMIO exit ignored, continue simulation");
				end
			end else begin
				// 未映射地址：这里选择“应答 + 返回 0”，不直接报错中止。
				mem_ready <= 1'b1;
				mem_rdata <= 32'h0;
			end
		end
	end

	// ----------------------------------------------------------------------------
	// 被测设计（DUT）：
	// 直接例化 picorv32 核心，连接原生内存接口。
	// ----------------------------------------------------------------------------
	picorv32 uut (
		.clk       (clk),
		.resetn    (resetn),
		.trap      (trap),
		.mem_valid (mem_valid),
		.mem_instr (mem_instr),
		.mem_ready (mem_ready),
		.mem_addr  (mem_addr),
		.mem_wdata (mem_wdata),
		.mem_wstrb (mem_wstrb),
		.mem_rdata (mem_rdata)
	);

endmodule
