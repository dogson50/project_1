# project_1 总览

本仓库是一个 FPGA + CPU + NPU 的综合实验工作区，包含 PicoRV32 CPU 核验证、SoC 架构资料、多套 NPU 参考工程，以及 Vivado 工程文件。

当前根工程文件为：
- project_1.xpr

## 1. 仓库结构

- picorv32-main/picorv32-main
  - PicoRV32 官方主仓（含 picorv32、picorv32_axi、picorv32_wb）
  - 已可直接用于 Icarus 仿真和 Vivado 仿真
  - 本地新增了 CPU 仿真平台：testbench_cpu.v
- ft_3_md/飞腾杯赛题三/SOC框架
  - 赛题三 SoC 设计文档（AXI、DDR、IRQ、NPU、picorv32_axi 等）
- NPUSoC-main/NPUSoC-main
  - 一套 NPU SoC 相关 RTL/仿真/测试数据工程
- NPU_on_FPGA-master/NPU_on_FPGA-master
  - 较完整的 NPU 设计与 Python 生成流程（偏 Intel/ModelSim 工具链）
- universal_NPU-CNN_accelerator-main/universal_NPU-CNN_accelerator-main
  - 通用 NPU/CNN 加速器草案与模块说明

## 2. 推荐开发入口

如果你当前目标是 CPU 指令与总线验证，建议从 PicoRV32 子目录开始：

- 工作目录：picorv32-main/picorv32-main
- 核心文件：picorv32.v
- 基础仿真：testbench_ez.v
- CPU 指令级仿真：testbench_cpu.v

## 3. 快速开始（Icarus Verilog）

在 VS Code 中可直接使用已配置任务：

1. sim:check-tools
2. sim:ez:run
3. sim:ez:vcd
4. sim:ez:wave

也可手动执行（当前目录为 picorv32-main/picorv32-main）：

1. iverilog -g2012 -o .sim/testbench_cpu.vvp testbench_cpu.v picorv32.v
2. vvp -N .sim/testbench_cpu.vvp +selftest_alu +maxcycles=2000

说明：
- selftest_alu 为内置指令级自测程序，PASS/FAIL 通过 MMIO 退出口回报。
- 也可加载外部固件：
  - vvp -N .sim/testbench_cpu.vvp +firmware=firmware/firmware.hex +maxcycles=200000
- 导出波形：增加 +vcd 参数。

## 4. Vivado 仿真建议（XSim）

Vivado 工程已经存在，可直接在仿真源中添加以下文件：

- picorv32-main/picorv32-main/picorv32.v
- picorv32-main/picorv32-main/testbench_cpu.v

然后将仿真顶层设置为 testbench_cpu，运行 Behavioral Simulation。

若要传入 plusargs，可在 Simulation Settings 中添加：

- -testplusarg selftest_alu
- -testplusarg maxcycles=2000
- -testplusarg firmware=D:/FPGA/project_1/picorv32-main/picorv32-main/firmware/xxx.hex

建议 firmware 使用绝对路径，避免仿真工作目录变化导致找不到文件。

## 5. 文档导航

- PicoRV32 中文文档：picorv32-main/picorv32-main/README.zh-CN.md
- VS Code + Icarus 仿真指南：picorv32-main/picorv32-main/SIM_VSCODE_IVERILOG.md
- SoC 架构文档目录：ft_3_md/飞腾杯赛题三/SOC框架

## 6. 当前工程事实（便于协作）

- project_1.xpr 显示器件型号为 xa7a12tcpg238-2I。
- 工程中已引用 picorv32-main/picorv32-main/picorv32.v。
- sources_1/sim_1 默认顶层为 picorv32_axi（如需跑 testbench_cpu，请在仿真集手动改顶层）。

## 7. 后续建议

建议按下面顺序推进验证：

1. 跑通 selftest_alu，确认 CPU 指令执行路径正常。
2. 增加更多自测（分支、访存、乘除、中断）。
3. 将 picorv32_axi 接入赛题三 SoC 子模块（AXI-Lite CSR、DMA、IRQ）。
4. 再推进 NPU 指令/数据通路协同验证。

## 8. 许可证说明

本工作区包含多个来源不同的子工程，请分别以各子目录内 LICENSE 或原始说明为准。
