`timescale 1 ns / 1 ps

module testbench_cpu;
	localparam integer MEM_WORDS = 16384;
	localparam [31:0] MMIO_UART = 32'h1000_0000;
	localparam [31:0] MMIO_EXIT = 32'h1000_0004;

	reg clk = 1'b0;
	reg resetn = 1'b0;
	wire trap;

	wire        mem_valid;
	wire        mem_instr;
	reg         mem_ready = 1'b0;
	wire [31:0] mem_addr;
	wire [31:0] mem_wdata;
	wire [3:0]  mem_wstrb;
	reg  [31:0] mem_rdata = 32'h0;

	reg [31:0] memory [0:MEM_WORDS-1];
	reg [1023:0] firmware_file;
	integer i;
	integer max_cycles;
	integer cycle_counter;

	always #5 clk = ~clk;

	initial begin
		for (i = 0; i < MEM_WORDS; i = i + 1)
			memory[i] = 32'h00000013;

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
			$display("[TB] load firmware: %0s", firmware_file);
			$readmemh(firmware_file, memory);
		end else begin
			$display("[TB] no +firmware specified, use built-in demo program");
			memory[0] = 32'h3fc00093; // li x1,1020
			memory[1] = 32'h0000a023; // sw x0,0(x1)
			memory[2] = 32'h0000a103; // loop: lw x2,0(x1)
			memory[3] = 32'h00110113; // addi x2,x2,1
			memory[4] = 32'h0020a023; // sw x2,0(x1)
			memory[5] = 32'hff5ff06f; // j loop
		end

		max_cycles = 200000;
		if (!$value$plusargs("maxcycles=%d", max_cycles)) begin
			// Keep default max_cycles.
		end

		if ($test$plusargs("vcd")) begin
			$dumpfile("testbench_cpu.vcd");
			$dumpvars(0, testbench_cpu);
		end

		repeat (20) @(posedge clk);
		resetn <= 1'b1;
	end

	always @(posedge clk) begin
		if (!resetn)
			cycle_counter <= 0;
		else
			cycle_counter <= cycle_counter + 1;

		if (resetn && cycle_counter > max_cycles) begin
			$display("[TB] TIMEOUT at cycle %0d", cycle_counter);
			$finish;
		end

		if (resetn && trap) begin
			$display("[TB] CPU trap at cycle %0d", cycle_counter);
			$finish;
		end
	end

	always @(posedge clk) begin
		mem_ready <= 1'b0;

		if (mem_valid && !mem_ready) begin
			if (mem_addr[31:2] < MEM_WORDS) begin
				mem_ready <= 1'b1;
				mem_rdata <= memory[mem_addr[31:2]];

				if (mem_wstrb[0]) memory[mem_addr[31:2]][7:0]   <= mem_wdata[7:0];
				if (mem_wstrb[1]) memory[mem_addr[31:2]][15:8]  <= mem_wdata[15:8];
				if (mem_wstrb[2]) memory[mem_addr[31:2]][23:16] <= mem_wdata[23:16];
				if (mem_wstrb[3]) memory[mem_addr[31:2]][31:24] <= mem_wdata[31:24];
			end else if (mem_addr == MMIO_UART) begin
				mem_ready <= 1'b1;
				mem_rdata <= 32'h0;
				if (|mem_wstrb)
					$write("%c", mem_wdata[7:0]);
			end else if (mem_addr == MMIO_EXIT) begin
				mem_ready <= 1'b1;
				mem_rdata <= 32'h0;
				if (|mem_wstrb) begin
					if (mem_wdata == 32'h0)
						$display("\n[TB] PASS (exit code 0) at cycle %0d", cycle_counter);
					else
						$display("\n[TB] FAIL (exit code %0d) at cycle %0d", mem_wdata, cycle_counter);
					$finish;
				end
			end else begin
				mem_ready <= 1'b1;
				mem_rdata <= 32'h0;
			end
		end
	end

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