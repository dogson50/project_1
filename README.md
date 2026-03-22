# project_1 总览

本仓库是一个 FPGA/SoC 联合开发工作区，当前主线已经切到 **PicoRV32 AXI Demo SoC**，支持：
- AXI SoC RTL（程序存储器 + 数据存储器）
- C/汇编生成 `demo.hex`
- Icarus 一键仿真
- Vivado 一键仿真（含自动清理、自动加波形）

根工程文件：`project_1.xpr`

## 1. 当前主线目录

- `picorv32-main/picorv32-main/HDL_src`
  - `picorv32_AXI_SOC.v`（AXI SoC 顶层）
  - `AXI_Interconnect_2M3S.v` / `AXI_DMA.v` / `AXI_Block_RAM.v` / `AXI_DualPort_RAM.v`
- `picorv32-main/picorv32-main/sim/axi_soc`
  - `tb_picorv32_AXI_SOC.v`（主 testbench，含 `dbg_*` 观测别名）
  - `sw/`（`start.S`、`main.c`、`Makefile`、`demo.hex`）
- `.vscode`
  - `tasks.json`（一键编译/仿真任务）
  - `vivado_one_click_axi_soc.tcl`（Vivado 一键脚本）
  - `xsim_axi_soc_waves.tcl` / `xsim_axi_soc_waves_fde.tcl`（波形预置）
- `ft_3_md/飞腾杯赛题三/SOC框架`
  - 当前 SoC 主线文档（架构图、CPU、互连、DMA、CSR）
- `ft_3_md/飞腾杯赛题三/NPU设计`
  - NPU 架构文档与并行设计要求

## 2. AXI SoC 地址映射（当前）

- Program RAM：`0x0000_0000 ~ 0x0000_FFFF`
- Data RAM：`0x2000_0000 ~ 0x2000_FFFF`
- DMA CSR：`0x4000_0000 ~ 0x4000_FFFF`

`demo.hex` 默认路径：
- `picorv32-main/picorv32-main/sim/axi_soc/sw/demo.hex`

## 3. 推荐使用方式（VS Code Tasks）

在 VS Code 执行：`Terminal -> Run Task`

### 3.1 Icarus 一键

- `run:axi-soc:one-click`：编译 `demo.hex` + 编译仿真 + 运行
- `run:axi-soc:one-click:wave`：同上并打开 GTKWave
- `run:iverilog:one-click`：等价 AXI SoC 一键入口

### 3.2 Vivado 一键

- `run:vivado:axi-soc:one-click:gui`
- `run:vivado:axi-soc:one-click:fde:gui`（取指-译码-执行重点波形）
- `run:vivado:axi-soc:one-click:batch`

脚本会先执行：
- `run:vivado:cleanup:sim-axi-soc`

用于关闭残留 `xsim/xelab/xvlog` 进程并清理 `project_1.sim/sim_axi_soc/behav/xsim`，减少 `simulate.log` 被占用导致的报错。

## 4. 手动命令（不走 Tasks）

工作目录：`picorv32-main/picorv32-main`

1. 生成 AXI SoC 演示固件（WSL）  
`wsl --cd /mnt/d/FPGA/project_1/picorv32-main/picorv32-main/sim/axi_soc/sw make demo.hex TOOLCHAIN_PREFIX=riscv64-unknown-elf-`

2. 编译 testbench  
`iverilog -g2012 -o .sim/tb_picorv32_AXI_SOC.vvp sim/axi_soc/tb_picorv32_AXI_SOC.v HDL_src/picorv32_AXI_SOC.v HDL_src/AXI_Interconnect_2M3S.v HDL_src/AXI_DMA.v HDL_src/AXI_Block_RAM.v HDL_src/AXI_DualPort_RAM.v picorv32.v`

3. 运行仿真  
`vvp -N .sim/tb_picorv32_AXI_SOC.vvp +maxcycles=50000`

4. 波形模式  
`vvp -N .sim/tb_picorv32_AXI_SOC.vvp +vcd +maxcycles=50000`

## 5. 波形与调试信号说明

`tb_picorv32_AXI_SOC.v` 顶层暴露了关键 `dbg_*` 信号，便于直接看：
- CPU 状态机：`dbg_cpu_state`
- 译码触发：`dbg_decoder_trigger(_q)`
- 取指/访存动作：`dbg_mem_do_rinst/rdata/wdata`
- PC 与 next PC：`dbg_reg_pc` / `dbg_reg_next_pc`
- 译码结果：`dbg_decoded_rd/rs1/rs2/imm`
- 指令识别脉冲：`dbg_instr_jal/addi/sw/ecall_ebreak`

建议优先使用 `run:vivado:axi-soc:one-click:fde:gui` 观察“取指-译码-执行”流程。

## 6. 文档导航

- AXI SoC 仿真说明：`picorv32-main/picorv32-main/sim/axi_soc/README.md`
- PicoRV32 中文说明：`picorv32-main/picorv32-main/README.zh-CN.md`
- SoC 架构资料：`ft_3_md/飞腾杯赛题三/SOC框架`
- NPU 并行设计要求：`ft_3_md/飞腾杯赛题三/NPU设计/npu设计要求.md`

## 7. 当前项目状态（2026-03）

- 主验证路径已统一到 `tb_picorv32_AXI_SOC`
- AXI SoC 固件已统一到 `sim/axi_soc/sw/demo.hex`
- Vivado 一键脚本已支持：
  - 仿真前清理残留文件/进程
  - GUI 自动加载波形预置
  - FDE 专用波形视图

后续建议：在现有 AXI SoC 基线上接入 NPU AXI-Lite CSR + AXI Master 数据通路，并沿用同一套一键回归流程。
