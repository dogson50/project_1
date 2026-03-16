[![.github/workflows/ci.yml](https://github.com/YosysHQ/picorv32/actions/workflows/ci.yml/badge.svg)](https://github.com/YosysHQ/picorv32/actions/workflows/ci.yml)

PicoRV32 - 面向面积优化的 RISC-V CPU
===================================

PicoRV32 是一个实现了 [RISC-V RV32IMC 指令集](http://riscv.org/) 的 CPU 软核。
它可以配置为 RV32E、RV32I、RV32IC、RV32IM 或 RV32IMC，并且可选内建中断控制器。

可通过 [RISC-V 网站](https://riscv.org/software-status/) 获取工具链（gcc、binutils 等）。
PicoRV32 自带示例默认假设已安装多种 RV32 工具链到 `/opt/riscv32i[m][c]`。
详见下文 [构建纯 RV32I 工具链](#构建纯-rv32i-工具链)。
很多 Linux 发行版已包含 RISC-V 工具（例如 Ubuntu 20.04 提供 `gcc-riscv64-unknown-elf`）。你
若使用这类工具，请按实际前缀设置 `TOOLCHAIN_PREFIX`（例如：`make TOOLCHAIN_PREFIX=riscv64-unknown-elf-`）。

PicoRV32 是免费开源硬件，采用 [ISC license](http://en.wikipedia.org/wiki/ISC_license)
（条款与 MIT 或 2-Clause BSD 类似）。

#### 目录

- [特性与典型应用](#特性与典型应用)
- [仓库文件说明](#仓库文件说明)
- [Verilog 模块参数](#verilog-模块参数)
- [每条指令周期性能](#每条指令周期性能)
- [PicoRV32 原生内存接口](#picorv32-原生内存接口)
- [Pico 协处理器接口（PCPI）](#pico-协处理器接口pcpi)
- [用于 IRQ 处理的自定义指令](#用于-irq-处理的自定义指令)
- [构建纯 RV32I 工具链](#构建纯-rv32i-工具链)
- [在 PicoRV32 上使用 newlib 链接二进制](#在-picorv32-上使用-newlib-链接二进制)
- [评估：Xilinx 7 系列 FPGA 上的时序与资源](#评估xilinx-7-系列-fpga-上的时序与资源)


特性与典型应用
--------------

- 小面积（Xilinx 7 系列大约 750-2000 LUT）
- 高主频（Xilinx 7 系列大约 250-450 MHz）
- 可选原生内存接口或 AXI4-Lite 主机接口
- 可选 IRQ 支持（使用一组简单自定义 ISA）
- 可选协处理器接口（PCPI）

该 CPU 主要面向 FPGA/ASIC 设计中的辅助处理器场景。由于 fmax 较高，
通常可直接集成进现有设计而无需跨时钟域。若在较低频率运行，会有较大时序裕量，
更易集成且不影响整体收敛。

若追求更小面积，可以关闭寄存器 `x16`..`x31` 以及
`RDCYCLE[H]`、`RDTIME[H]`、`RDINSTRET[H]` 指令支持，使其工作为 RV32E。

另外可在双端口寄存器堆与单端口寄存器堆间选择：
前者性能更好，后者面积更小。

*注意：若目标架构（如很多 FPGA）将寄存器堆实现为专用存储资源，
关闭高 16 个寄存器或改为单端口不一定继续减小核心面积。*

核心有 3 个变体：`picorv32`、`picorv32_axi`、`picorv32_wb`。
`picorv32` 提供简单的原生内存接口，适合简单系统；
`picorv32_axi` 提供 AXI4-Lite 主机接口，便于接入现有 AXI 系统；
`picorv32_wb` 提供 Wishbone 主机接口。

另有 `picorv32_axi_adapter`，用于在原生内存接口与 AXI4-Lite 之间桥接。
这使你可以构建含一个或多个 PicoRV32 内核、并带本地 RAM/ROM/MMIO 外设的自定义 SoC：
内部用原生接口互联，对外用 AXI4 通信。

可选 IRQ 特性可用于响应外部事件、实现故障处理，或捕获更大 ISA 中的指令并在软件中模拟。

可选 PCPI（Pico Co-Processor Interface）可用于在外部协处理器中实现非分支类指令。
仓库中已包含实现标准 M 扩展中 `MUL[H[SU|U]]` 与 `DIV[U]/REM[U]` 的 PCPI 模块。


仓库文件说明
------------

#### README.md

你正在阅读它。

#### picorv32.v

此 Verilog 文件包含下列模块：

| 模块                     | 说明                                                            |
| ------------------------ | --------------------------------------------------------------- |
| `picorv32`               | PicoRV32 CPU 核心                                               |
| `picorv32_axi`           | 带 AXI4-Lite 接口的 CPU 版本                                    |
| `picorv32_axi_adapter`   | PicoRV32 原生内存接口到 AXI4-Lite 的适配器                      |
| `picorv32_wb`            | 带 Wishbone 主机接口的 CPU 版本                                 |
| `picorv32_pcpi_mul`      | 实现 `MUL[H[SU\|U]]` 指令的 PCPI 核心                           |
| `picorv32_pcpi_fast_mul` | `picorv32_pcpi_mul` 的单周期乘法器版本                          |
| `picorv32_pcpi_div`      | 实现 `DIV[U]/REM[U]` 指令的 PCPI 核心                           |

把这个文件直接拷进你的工程即可。

#### Makefile 与测试平台

仓库提供了基础测试环境。
运行 `make test` 会在标准配置下执行标准 testbench（`testbench.v`）。
还有更多 testbench/配置，详见 Makefile 中 `test_*` 目标。

运行 `make test_ez` 会执行 `testbench_ez.v`，这是一个非常简单的 testbench，
不依赖外部 firmware `.hex` 文件。若你当前没有 RISC-V 编译工具链，这个模式很有用。

*注意：testbench 使用 Icarus Verilog。
文档编写当时 Icarus Verilog 0.9.7（当时最新发布版）存在几个 bug，
会导致 testbench 无法运行。建议升级到 Icarus Verilog 的较新版本。*

#### firmware/

一个简单测试固件。会运行 `tests/` 里的基础测试、一些 C 代码，
以及 IRQ 与乘法 PCPI 核心测试。

`firmware/` 下代码是公有领域（public domain），可按需直接复用。

#### tests/

来自 [riscv-tests](https://github.com/riscv/riscv-tests) 的指令级简单测试。

#### dhrystone/

另一个简单固件，用于运行 Dhrystone 基准。

#### picosoc/

基于 PicoRV32 的简单 SoC 示例，可直接从 memory-mapped SPI Flash 执行代码。

#### scripts/

包含针对不同综合工具和硬件架构的脚本/示例。


Verilog 模块参数
----------------

以下参数可用于配置 PicoRV32 核心。

#### ENABLE_COUNTERS (default = 1)

启用 `RDCYCLE[H]`、`RDTIME[H]`、`RDINSTRET[H]` 指令支持。
若设为 0，这些指令会触发硬件陷阱（与其它不支持指令类似）。

*注意：严格来说，`RDCYCLE[H]`、`RDTIME[H]`、`RDINSTRET[H]`
对 RV32I 并非可选；但在应用调试/性能分析完成后，很多场景可不需要它们。
它们对 RV32E 是可选项。*

#### ENABLE_COUNTERS64 (default = 1)

启用 `RDCYCLEH`、`RDTIMEH`、`RDINSTRETH` 指令。
若该参数为 0 且 `ENABLE_COUNTERS` 为 1，则仅支持
`RDCYCLE`、`RDTIME`、`RDINSTRET`（低 32 位）。

#### ENABLE_REGS_16_31 (default = 1)

启用寄存器 `x16`..`x31`。RV32E 不包含这些寄存器。
不过 RV32E 规范要求访问这些寄存器时产生硬件 trap，
这点在 PicoRV32 中未实现。

#### ENABLE_REGS_DUALPORT (default = 1)

寄存器堆可实现为双读端口或单读端口。
双端口性能更好，但可能增加面积。

#### LATCHED_MEM_RDATA (default = 0)

若外部电路在一次访问之后持续保持 `mem_rdata` 稳定，则设为 1。
默认配置下，PicoRV32 只要求 `mem_rdata` 在 `mem_valid && mem_ready`
那个周期有效，并在核内自行锁存。

此参数仅适用于 `picorv32` 核。
在 `picorv32_axi` 与 `picorv32_wb` 中等效固定为 0。

#### TWO_STAGE_SHIFT (default = 1)

默认移位运算分两阶段执行：先按 4-bit 粒度，再按 1-bit 粒度。
这样可提高移位性能，但会增加额外硬件。
设为 0 可关闭两级移位，以进一步减小面积。

#### BARREL_SHIFTER (default = 0)

默认采用逐步移位（见 `TWO_STAGE_SHIFT`）。
设为 1 时启用桶形移位器。

#### TWO_CYCLE_COMPARE (default = 0)

在条件分支比较路径上增加一级 FF，缩短最长组合路径，
代价是条件分支增加 1 个时钟周期延迟。

*注意：开启该参数并配合综合中的重定时（register balancing）通常效果更好。*

#### TWO_CYCLE_ALU (default = 0)

在 ALU 数据路径增加一级 FF，提高时序裕量；
代价是所有使用 ALU 的指令都增加 1 个时钟周期。

*注意：开启该参数并配合综合中的重定时（register balancing）通常效果更好。*

#### COMPRESSED_ISA (default = 0)

启用 RISC-V 压缩指令集（C 扩展）支持。

#### CATCH_MISALIGN (default = 1)

设为 0 可关闭“非对齐内存访问检测”电路。

#### CATCH_ILLINSN (default = 1)

设为 0 可关闭“非法指令检测”电路。

即便设为 0，`EBREAK` 仍会让处理器进入 trap。
若启用了 IRQ，`EBREAK` 通常触发 IRQ 1；
而当该参数为 0 时，`EBREAK` 只会 trap，不触发中断。

#### ENABLE_PCPI (default = 0)

设为 1 以启用“外部”PCPI 接口。
对于内部 PCPI 核（如 `picorv32_pcpi_mul`），不要求必须打开该外部接口。

#### ENABLE_MUL (default = 0)

该参数会在内部启用 PCPI，并实例化 `picorv32_pcpi_mul`，
实现 `MUL[H[SU|U]]` 指令。
外部 PCPI 只有在 `ENABLE_PCPI` 也为 1 时才可用。

#### ENABLE_FAST_MUL (default = 0)

该参数会在内部启用 PCPI，并实例化 `picorv32_pcpi_fast_mul`，
实现 `MUL[H[SU|U]]` 指令。
外部 PCPI 只有在 `ENABLE_PCPI` 也为 1 时才可用。

若 `ENABLE_MUL` 与 `ENABLE_FAST_MUL` 同时为 1，
则忽略 `ENABLE_MUL`，优先使用快速乘法核。

#### ENABLE_DIV (default = 0)

该参数会在内部启用 PCPI，并实例化 `picorv32_pcpi_div`，
实现 `DIV[U]/REM[U]` 指令。
外部 PCPI 只有在 `ENABLE_PCPI` 也为 1 时才可用。

#### ENABLE_IRQ (default = 0)

设为 1 以启用 IRQ（见下文“用于 IRQ 处理的自定义指令”）。

#### ENABLE_IRQ_QREGS (default = 1)

设为 0 可关闭 `getq`、`setq` 指令支持。
若无 q-register，IRQ 返回地址将存于 x3（gp），IRQ 位掩码存于 x4（tp）。
按 RISC-V ABI，它们分别是全局指针与线程指针；普通 C 代码一般不会碰这些寄存器。

当 `ENABLE_IRQ=0` 时，q-register 支持总是关闭。

#### ENABLE_IRQ_TIMER (default = 1)

设为 0 可关闭 `timer` 指令支持。
当 `ENABLE_IRQ=0` 时，timer 支持总是关闭。

#### ENABLE_TRACE (default = 0)

通过 `trace_valid` 与 `trace_data` 输出执行跟踪。
演示方式：
先运行 `make test_vcd` 生成 trace，
再运行 `python3 showtrace.py testbench.trace firmware/firmware.elf` 解码。

#### REGS_INIT_ZERO (default = 0)

设为 1 时，会在 Verilog `initial` 块中将所有寄存器初始化为 0。
这对仿真或形式验证有帮助。

#### MASKED_IRQ (default = 32'h 0000_0000)

该位掩码中为 1 的 IRQ 位会被永久禁用。

#### LATCHED_IRQ (default = 32'h ffff_ffff)

该位掩码中为 1 的 IRQ 位表示“锁存型中断”：
对应 IRQ 线即使只拉高 1 个周期，中断也会保持 pending，
直到中断处理程序被调用（脉冲/边沿触发语义）。

将某位设为 0，可把对应 IRQ 改成电平敏感型。

#### PROGADDR_RESET (default = 32'h 0000_0000)

程序启动地址（复位后 PC）。

#### PROGADDR_IRQ (default = 32'h 0000_0010)

中断处理入口地址。

#### STACKADDR (default = 32'h ffff_ffff)

若参数值不是 `0xffffffff`，则复位时把寄存器 `x2`（栈指针）初始化为该值
（其他寄存器保持未初始化）。
注意按 RISC-V 调用约定，栈指针应满足 16 字节对齐
（RV32I soft-float ABI 下常见为 4 字节对齐）。


每条指令周期性能
----------------

*提醒：该核心优化目标是面积与 fmax，而非纯性能。*

除非特别说明，下列数据基于启用 `ENABLE_REGS_DUALPORT`，
且连接到可在 1 个周期内响应访问的存储器。

平均 CPI 约为 4（与代码指令混合有关）。
各指令 CPI 见下表；“CPI (SP)”为关闭 `ENABLE_REGS_DUALPORT`（单端口）时的数据。

| 指令                  |  CPI | CPI (SP) |
| ---------------------| ----:| --------:|
| 直接跳转 (jal)        |    3 |        3 |
| ALU 寄存器+立即数     |    3 |        3 |
| ALU 寄存器+寄存器     |    3 |        4 |
| 分支（不跳转）         |    3 |        4 |
| 内存读                |    5 |        5 |
| 内存写                |    5 |        6 |
| 分支（跳转）           |    5 |        6 |
| 间接跳转 (jalr)       |    6 |        6 |
| 移位操作              | 4-14 |     4-15 |

启用 `ENABLE_MUL` 后：
`MUL` 约 40 周期，`MULH[SU|U]` 约 72 周期。

启用 `ENABLE_DIV` 后：
`DIV[U]/REM[U]` 约 40 周期。

启用 `BARREL_SHIFTER` 后：
移位指令耗时与普通 ALU 指令接近。

下述 Dhrystone 数据来自启用 `ENABLE_FAST_MUL`、`ENABLE_DIV`、`BARREL_SHIFTER` 的配置。

Dhrystone：0.516 DMIPS/MHz（908 Dhrystones/Second/MHz）

该场景平均 CPI 为 4.100。

若不使用前瞻（look-ahead）内存接口（通常会影响最高频率），
结果降至 0.305 DMIPS/MHz，平均 CPI 升至 5.232。


PicoRV32 原生内存接口
---------------------

PicoRV32 的原生内存接口是“单事务 valid-ready”协议：

    output        mem_valid
    output        mem_instr
    input         mem_ready

    output [31:0] mem_addr
    output [31:0] mem_wdata
    output [ 3:0] mem_wstrb
    input  [31:0] mem_rdata

核心通过拉高 `mem_valid` 发起一次内存事务。
在 `mem_ready` 拉高前，`mem_valid` 保持为高，且核心输出保持稳定。
若该事务是取指，核心会拉高 `mem_instr`。

#### 读事务（Read Transfer）

读事务中 `mem_wstrb=0`，`mem_wdata` 无效。

存储器读取 `mem_addr` 指向的数据，并在 `mem_ready` 为高的周期将数据放到 `mem_rdata`。

通常无需额外等待周期。
存储器可异步实现，即 `mem_ready` 与 `mem_valid` 同周期拉高；
也可将 `mem_ready` 常量拉高为 1。

#### 写事务（Write Transfer）

写事务中 `mem_wstrb!=0`，`mem_rdata` 无效。
存储器将 `mem_wdata` 写入 `mem_addr`，并通过拉高 `mem_ready` 应答。

`mem_wstrb` 的 4 位对应字内 4 个字节写使能。
只会出现以下 8 种值：`0000`、`1111`、`1100`、`0011`、
`1000`、`0100`、`0010`、`0001`。
即：不写、写 32 位、写高 16 位、写低 16 位，或写单字节。

同样通常无需外部等待周期。
存储器可在 `mem_valid` 同周期立即应答，或将 `mem_ready` 常高。

#### 前瞻接口（Look-Ahead Interface）

PicoRV32 还提供“前瞻内存接口”，可比普通接口提前 1 个周期给出下一次事务信息：

    output        mem_la_read
    output        mem_la_write
    output [31:0] mem_la_addr
    output [31:0] mem_la_wdata
    output [ 3:0] mem_la_wstrb

在 `mem_valid` 拉高前一个周期，该接口会在 `mem_la_read` 或 `mem_la_write`
输出一个脉冲，表示下一周期将发起读/写事务。

*注意：`mem_la_read`、`mem_la_write`、`mem_la_addr` 由核内组合逻辑驱动。
与普通接口相比，使用前瞻接口可能更难做时序收敛。*


Pico 协处理器接口（PCPI）
-------------------------

PCPI 可用于在外部核心实现“非分支类”指令：

    output        pcpi_valid
    output [31:0] pcpi_insn
    output [31:0] pcpi_rs1
    output [31:0] pcpi_rs2
    input         pcpi_wr
    input  [31:0] pcpi_rd
    input         pcpi_wait
    input         pcpi_ready

当核心遇到不支持的指令，且已启用 PCPI（见 `ENABLE_PCPI`），
会拉高 `pcpi_valid`，并输出：
- 指令字到 `pcpi_insn`
- 译码后的 `rs1`、`rs2` 寄存器值到 `pcpi_rs1`、`pcpi_rs2`

外部 PCPI 核可据此译码并执行，完成后拉高 `pcpi_ready`。
若需写回结果，外部核同时给出 `pcpi_rd` 并拉高 `pcpi_wr`；
PicoRV32 将按指令的 `rd` 字段把 `pcpi_rd` 写回对应寄存器。

若 16 个时钟周期内没有任何外部 PCPI 核确认该指令，
核心会触发非法指令异常并进入相应中断处理流程。

若外部 PCPI 指令执行需要较多周期，建议在识别到目标指令后尽早拉高 `pcpi_wait`，
并保持到 `pcpi_ready` 拉高为止，以阻止 PicoRV32 过早触发非法指令异常。


用于 IRQ 处理的自定义指令
-------------------------

*注意：PicoRV32 的 IRQ 机制不遵循 RISC-V Privileged ISA 规范。
它使用一组非常简单的自定义指令，以最小硬件开销实现中断处理。*

下面这些自定义指令仅在 `ENABLE_IRQ=1` 时可用。

PicoRV32 内建 32 路中断输入。你可通过拉高核心 `irq` 输入中相应位触发中断。

进入中断处理时，对应已处理中断的 `eoi`（End Of Interrupt）位会拉高；
中断返回时 `eoi` 重新拉低。

IRQ 0-2 还可由下列内建源触发：

| IRQ | 中断源                               |
| ---:| ------------------------------------ |
|   0 | 定时器中断                           |
|   1 | EBREAK/ECALL 或非法指令              |
|   2 | 总线错误（非对齐内存访问）           |

这些中断也可由外部源触发，例如通过 PCPI 连接的协处理器。

核心有 4 个额外 32 位寄存器 `q0..q3` 用于 IRQ 处理：
- 进入 IRQ 处理时，`q0` 保存返回地址，`q1` 保存待处理 IRQ 位掩码
- 若 `q1` 多个位为 1，一次 IRQ 入口可能需要处理多个中断

启用压缩指令时，若被打断指令是压缩指令，`q0` 的 LSB 会被置位。
IRQ 处理代码可据此决定是否需要按压缩指令格式解码被打断指令。

`q2`、`q3` 上电未初始化，可在保存/恢复寄存器时作临时存储。

以下指令都编码在 `custom0` opcode 下，且 `f3`、`rs2` 字段均被忽略。

GNU 汇编宏见 [firmware/custom_ops.S](firmware/custom_ops.S)。
中断处理包装示例见 [firmware/start.S](firmware/start.S)，
实际 IRQ handler 示例见 [firmware/irq.c](firmware/irq.c)。

#### getq rd, qs

将 q 寄存器拷贝到通用寄存器：

    0000000 ----- 000XX --- XXXXX 0001011
    f7      rs2   qs    f3  rd    opcode

示例：

    getq x5, q2

#### setq qd, rs

将通用寄存器拷贝到 q 寄存器：

    0000001 ----- XXXXX --- 000XX 0001011
    f7      rs2   rs    f3  qd    opcode

示例：

    setq q2, x5

#### retirq

中断返回。该指令将 `q0` 写回 PC，并重新使能中断：

    0000010 ----- 00000 --- 00000 0001011
    f7      rs2   rs    f3  rd    opcode

示例：

    retirq

#### maskirq

IRQ Mask 寄存器保存“被屏蔽（禁用）中断”的位掩码。
该指令写入新掩码，同时把旧值读到 `rd`：

    0000011 ----- XXXXX --- XXXXX 0001011
    f7      rs2   rs    f3  rd    opcode

示例：

    maskirq x1, x2

处理器上电时默认所有中断都被禁用。

若非法指令或总线错误发生时，对应中断也处于禁用状态，
处理器会停止运行。

#### waitirq

暂停执行，直到有中断挂起。挂起 IRQ 位掩码写入 `rd`：

    0000100 ----- 00000 --- XXXXX 0001011
    f7      rs2   rs    f3  rd    opcode

示例：

    waitirq x1

#### timer

将定时器计数器重置为新值。计数器按时钟周期递减，
从 1 变为 0 时触发定时器中断。
将计数器设为 0 表示关闭定时器。
旧计数值写入 `rd`：

    0000101 ----- XXXXX --- XXXXX 0001011
    f7      rs2   rs    f3  rd    opcode

示例：

    timer x1, x2


构建纯 RV32I 工具链
-------------------

TL;DR：执行以下命令可构建完整工具链：

    make download-tools
    make -j$(nproc) build-tools

[riscv-tools](https://github.com/riscv/riscv-tools) 默认脚本可构建支持任意 RISC-V ISA
的编译器/汇编器/链接器，但库文件默认面向 RV32G/RV64G。
若你需要完整面向纯 RV32I（含库）的工具链，可按下述步骤。

以下命令会构建面向纯 RV32I 的 RISC-V GNU 工具链和库，
并安装到 `/opt/riscv32i`：

    # Ubuntu packages needed:
    sudo apt-get install autoconf automake autotools-dev curl libmpc-dev \
            libmpfr-dev libgmp-dev gawk build-essential bison flex texinfo \
	    gperf libtool patchutils bc zlib1g-dev git libexpat1-dev

    sudo mkdir /opt/riscv32i
    sudo chown $USER /opt/riscv32i

    git clone https://github.com/riscv/riscv-gnu-toolchain riscv-gnu-toolchain-rv32i
    cd riscv-gnu-toolchain-rv32i
    git checkout 411d134
    git submodule update --init --recursive

    mkdir build; cd build
    ../configure --with-arch=rv32i --prefix=/opt/riscv32i
    make -j$(nproc)

上述工具前缀为 `riscv32-unknown-elf-`，
可与默认前缀 `riscv64-unknown-elf-` 的工具并存安装。

你也可以直接使用 PicoRV32 Makefile 的目标构建 `RV32I[M][C]` 工具链。
仍需先安装上面提到的依赖包，然后在 PicoRV32 源码目录执行：

| 命令                                     | 安装目录          | ISA      |
|:---------------------------------------- |:----------------- |:-------- |
| `make -j$(nproc) build-riscv32i-tools`   | `/opt/riscv32i/`  | `RV32I`  |
| `make -j$(nproc) build-riscv32ic-tools`  | `/opt/riscv32ic/` | `RV32IC` |
| `make -j$(nproc) build-riscv32im-tools`  | `/opt/riscv32im/` | `RV32IM` |
| `make -j$(nproc) build-riscv32imc-tools` | `/opt/riscv32imc/`| `RV32IMC`|

或直接运行 `make -j$(nproc) build-tools` 一次构建全部四套工具链。

默认情况下，上述目标会（重新）下载工具链源码。
你也可提前执行 `make download-tools`，
把源码先缓存到 `/var/cache/distfiles/`。

*注意：以上步骤对应 `riscv-gnu-toolchain` 的 git 版本 411d134（2018-02-14）。*


在 PicoRV32 上使用 newlib 链接二进制
-----------------------------------

上节安装的工具链自带 newlib C 标准库。

请使用链接脚本 [firmware/riscv.ld](firmware/riscv.ld) 与 newlib 链接。
该脚本会生成入口点固定在 `0x10000` 的二进制。
（默认链接脚本没有静态入口点，因此需要 ELF loader 在加载时动态解析入口地址。）

newlib 提供了一些 syscall stub。
你需要自行实现这些 syscall，并在链接时覆盖 newlib 默认 stub。
可参考 [scripts/cxxdemo/](scripts/cxxdemo/) 下的 `syscalls.c` 示例。


评估：Xilinx 7 系列 FPGA 上的时序与资源
--------------------------------------

以下评估使用 Vivado 2017.3。

#### Xilinx 7 系列时序

针对启用 `TWO_CYCLE_ALU` 的 `picorv32_axi`，
作者在 Artix-7T、Kintex-7T、Virtex-7T、Kintex UltraScale、Virtex UltraScale
各速度等级器件上进行了布局布线，并用二分搜索得到满足时序的最短时钟周期。

可参考 [scripts/vivado/](scripts/vivado/) 下 `make table.txt`。

| 器件系列                  | 器件型号              | 速度等级 | 时钟周期（频率）         |
|:------------------------- |:--------------------- |:-------:| -----------------------:|
| Xilinx Kintex-7T          | xc7k70t-fbg676-2      | -2      |     2.4 ns (416 MHz)    |
| Xilinx Kintex-7T          | xc7k70t-fbg676-3      | -3      |     2.2 ns (454 MHz)    |
| Xilinx Virtex-7T          | xc7v585t-ffg1761-2    | -2      |     2.3 ns (434 MHz)    |
| Xilinx Virtex-7T          | xc7v585t-ffg1761-3    | -3      |     2.2 ns (454 MHz)    |
| Xilinx Kintex UltraScale  | xcku035-fbva676-2-e   | -2      |     2.0 ns (500 MHz)    |
| Xilinx Kintex UltraScale  | xcku035-fbva676-3-e   | -3      |     1.8 ns (555 MHz)    |
| Xilinx Virtex UltraScale  | xcvu065-ffvc1517-2-e  | -2      |     2.1 ns (476 MHz)    |
| Xilinx Virtex UltraScale  | xcvu065-ffvc1517-3-e  | -3      |     2.0 ns (500 MHz)    |
| Xilinx Kintex UltraScale+ | xcku3p-ffva676-2-e    | -2      |     1.4 ns (714 MHz)    |
| Xilinx Kintex UltraScale+ | xcku3p-ffva676-3-e    | -3      |     1.3 ns (769 MHz)    |
| Xilinx Virtex UltraScale+ | xcvu3p-ffvc1517-2-e   | -2      |     1.5 ns (666 MHz)    |
| Xilinx Virtex UltraScale+ | xcvu3p-ffvc1517-3-e   | -3      |     1.4 ns (714 MHz)    |

#### Xilinx 7 系列资源占用

下表给出“面积优化综合”下三种配置的资源使用：

- **PicoRV32（small）**：
  `picorv32`，关闭计数器、关闭两级移位、`mem_rdata` 由外部锁存、
  且关闭非对齐访问与非法指令检测。
- **PicoRV32（regular）**：`picorv32` 默认配置。
- **PicoRV32（large）**：
  启用 PCPI、IRQ、MUL、DIV、BARREL_SHIFTER、COMPRESSED_ISA。

可参考 [scripts/vivado/](scripts/vivado/) 下 `make area`。

| 核心配置             | Slice LUTs | LUTs as Memory | Slice Registers |
|:-------------------- | ----------:| --------------:| ---------------:|
| PicoRV32 (small)     |        761 |             48 |             442 |
| PicoRV32 (regular)   |        917 |             48 |             583 |
| PicoRV32 (large)     |       2019 |             88 |            1085 |
