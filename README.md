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
  - 赛题三 SoC 设计文档（AXI、DDR、IRQ、NPU、picorv32_axi
  -  等）
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

## 2.1 一键仿真速查

在 VS Code 中执行：Terminal -> Run Task。

### Iverilog 一键仿真

推荐任务：

1. run:iverilog:one-click
2. run:iverilog:one-click:wave
3. run:iverilog:wave:long

行为说明：

1. 自动在 WSL 中生成 firmware.hex。
2. 自动用 Iverilog 编译 testbench_cpu。
3. 自动运行 vvp（wave 任务会导出 VCD 并打开 GTKWave）。

首次运行时可能会要求输入：

1. projectRootWsl：例如 /mnt/d/FPGA/project_1
2. toolchainPrefix：默认 riscv64-unknown-elf-
3. firmwarePath：默认 firmware/firmware.hex
4. maxCycles 或 maxCyclesLong：按需要填写

### Vivado 一键仿真

推荐任务：

1. run:vivado:one-click:gui
2. run:vivado:one-click:batch
3. run:vivado:selftest:gui

行为说明：

1. 自动打开项目并设置 sim_1 顶层为 testbench_cpu。
1. 自动打开项目并在独立仿真集 sim_cpu 中设置顶层为 testbench_cpu。
2. 自动写入 testplusarg（firmware 或 selftest）。
3. 自动启动 Behavioral Simulation（batch 任务会在终端输出日志）。

实现细节：

1. 一键脚本会使用独立仿真集 `sim_cpu`（不复用 `sim_1`），降低 `simulate.log` 文件锁冲突概率。

首次运行时可能会要求输入：

1. vivadoCmd：本机 Vivado 启动器绝对路径，建议填写 .../Vivado/bin/vivado.bat
2. firmwarePathVivado：默认相对路径 picorv32-main/picorv32-main/firmware/firmware.hex
3. maxCyclesVivado：默认 200000

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

### 3.1 Windows 窗口 + WSL 后端（推荐）

如果你希望继续使用 Windows 版 VS Code 窗口，同时使用 WSL 内已安装的 RISC-V 工具链，可直接运行下列任务：

1. build:firmware:hex:win-ui
2. sim:cpu:selftest:win-ui
3. sim:cpu:firmware:win-ui

其中 `build:firmware:hex:win-ui` 使用 `wsl --cd ... make ...` 在 WSL 中生成 hex。
若输出 `make: 'firmware/firmware.hex' is up to date.`，表示 hex 已是最新状态。

协作开发提示（首次配置一次）：

1. 任务会提示输入 `projectRootWsl`，请填你自己的 WSL 工程根目录（例如 `/mnt/d/FPGA/project_1`）。
2. 填完后即可直接复用一键任务，不需要修改任务文件。

### 3.2 单按钮全流程任务（KEIL 风格）

已提供一键任务：

1. run:cpu:one-click
2. run:iverilog:one-click
3. run:iverilog:one-click:wave

该任务会自动串行执行：

1. WSL 生成 firmware.hex
2. Icarus 编译 testbench_cpu
3. 运行 firmware 仿真

其中 `run:iverilog:one-click` 是强调 Iverilog 工具链的一键入口，行为与上述流程一致。
若需要自动打开波形，请使用 `run:iverilog:one-click:wave`（会附带 `+vcd` 并调用 GTKWave）。

建议日常直接使用这个任务作为默认 CPU 仿真入口。

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

### 4.1 Vivado 一键仿真任务

已提供基于 Tcl 的一键任务（会自动在 `sim_cpu` 仿真集中设置顶层为 `testbench_cpu` 并写入 plusargs）：

1. run:vivado:one-click:gui
2. run:vivado:one-click:batch
3. run:vivado:selftest:gui

对应 Tcl 脚本：

- .vscode/vivado_one_click_sim.tcl

说明：

- `run:vivado:one-click:gui`：打开 Vivado 并启动 Behavioral Simulation。
- `run:vivado:one-click:batch`：批处理方式运行仿真并在终端输出日志。
- `run:vivado:selftest:gui`：使用内置 selftest 指令程序启动 Vivado 仿真。

实现细节：

1. 一键脚本使用独立仿真集 `sim_cpu`，避免与手工使用的 `sim_1` 互相锁文件。

协作开发提示（首次配置一次）：

1. 任务会提示输入 `vivadoCmd`，建议填写各自机器上的 `.../Vivado/bin/vivado.bat` 绝对路径。
2. `firmwarePathVivado` 默认是相对路径，保持默认即可（项目根目录运行）。

## 5. 文档导航

- PicoRV32 中文文档：picorv32-main/picorv32-main/README.zh-CN.md
- VS Code + Icarus 仿真指南：picorv32-main/picorv32-main/SIM_VSCODE_IVERILOG.md
- SoC 架构文档目录：ft_3_md/飞腾杯赛题三/SOC框架

## 6. VS Code 开发体验（函数跳转）

工程已配置 C/C++ 索引文件与任务，可在 Windows 窗口下使用：

1. F12 跳转定义
2. Shift+F12 查找引用
3. Ctrl+T 全局符号搜索

相关配置文件：

- .vscode/tasks.json
- .vscode/c_cpp_properties.json
- .vscode/settings.json

## 7. 当前工程事实（便于协作）

- project_1.xpr 显示器件型号为 xa7a12tcpg238-2I。
- 工程中已引用 picorv32-main/picorv32-main/picorv32.v。
- sources_1/sim_1 默认顶层为 picorv32_axi（如需跑 testbench_cpu，请在仿真集手动改顶层）。

## 8. 后续建议

建议按下面顺序推进验证：

1. 跑通 selftest_alu，确认 CPU 指令执行路径正常。
2. 增加更多自测（分支、访存、乘除、中断）。
3. 将 picorv32_axi 接入赛题三 SoC 子模块（AXI-Lite CSR、DMA、IRQ）。
4. 再推进 NPU 指令/数据通路协同验证。

## 9. 许可证说明

本工作区包含多个来源不同的子工程，请分别以各子目录内 LICENSE 或原始说明为准。
