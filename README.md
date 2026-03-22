# project_1 总览

本仓库是一个 FPGA/SoC + NPU 的联合开发工作区。  
当前主线已经包含：

- PicoRV32 AXI SoC（已有基础互连、RAM、DMA 模块）
- `npu_core_tile_4x4`（4x4 脉动阵列 tile，`SIMD_PER_PE` 可参数化）
- `npu_core_cluster`（多 tile 并行簇）
- Icarus/Vivado 一键仿真入口（已统一到 NPU 方向）

根工程文件：`project_1.xpr`

## 1. 目录结构（当前主线）

- `picorv32-main/picorv32-main/HDL_src`
  - `NPU_design/npu_mac_lane.v`：lane 级乘法通道
  - `NPU_design/npu_pe.v`：单个 PE（支持 SIMD 并行 lane）
  - `NPU_design/npu_core_tile_4x4.v`：16 PE 组成的 4x4 tile
  - `NPU_design/npu_core_cluster.v`：多 tile 并行封装
  - 其余 AXI SoC 相关模块（`AXI_*`, `picorv32_AXI_SOC.v`）

- `picorv32-main/picorv32-main/sim/NPU`
  - `tb_npu_core_tile_4x4.v`：tile 自检 testbench（PASS/FAIL）
  - `tb_npu_core_cluster.v`：cluster 自检 testbench（PASS/FAIL）
  - `run_iverilog_npu*.ps1`：Icarus 一键脚本
  - `run_vivado_npu*.tcl`：Vivado 一键脚本
  - `README.md`：NPU 仿真子说明

- `ft_3_md/飞腾杯赛题三/NPU设计`
  - NPU 模块划分、接口、控制面、架构图、设计要求等文档

## 2. 已实现的 NPU 计算骨架

### 2.1 `npu_core_tile_4x4`

- 输入：4 行 A 向量（西侧）+ 4 列 B 向量（北侧）
- 数据流：A 向右脉动、B 向下脉动
- 每个 PE：
  - 内部 `SIMD_PER_PE` 条 MAC lane（当前默认建议值 2）
  - 对 lane 乘积求和后累加到 `acc`
- 输出：16 个累加结果（`4x4`，行优先打包）

### 2.2 `npu_core_cluster`

- 支持 `CORE_NUM` 个 tile 并行
- 每个 tile 独立 `in_valid/clear_acc`
- 输出按 tile 拼接，便于调度器后续接入

## 3. 仿真说明

当前 testbench 均为“自检式”：

- `tb_npu_core_tile_4x4.v`
  - 斜向注入（skewed feed）驱动脉动阵列
  - 检查首轮矩阵输出
  - 不清零再注入一次，检查累加翻倍

- `tb_npu_core_cluster.v`
  - 两个 tile 并行输入不同数据
  - 分别检查两个 tile 的矩阵输出
  - 二次注入检查两个 tile 同时翻倍

## 4. 一键仿真（推荐）

在仓库根目录 `D:\FPGA\project_1` 执行：

### 4.1 Icarus

```powershell
powershell -ExecutionPolicy Bypass -File .\picorv32-main\picorv32-main\sim\NPU\run_iverilog_npu.ps1
powershell -ExecutionPolicy Bypass -File .\picorv32-main\picorv32-main\sim\NPU\run_iverilog_npu.ps1 -Wave

powershell -ExecutionPolicy Bypass -File .\picorv32-main\picorv32-main\sim\NPU\run_iverilog_npu_cluster.ps1
powershell -ExecutionPolicy Bypass -File .\picorv32-main\picorv32-main\sim\NPU\run_iverilog_npu_cluster.ps1 -Wave
```

### 4.2 Vivado/XSim

```powershell
vivado -mode batch -source .\picorv32-main\picorv32-main\sim\NPU\run_vivado_npu.tcl
vivado -source .\picorv32-main\picorv32-main\sim\NPU\run_vivado_npu.tcl -tclargs gui

vivado -mode batch -source .\picorv32-main\picorv32-main\sim\NPU\run_vivado_npu_cluster.tcl
vivado -source .\picorv32-main\picorv32-main\sim\NPU\run_vivado_npu_cluster.tcl -tclargs gui
```

## 5. VS Code Tasks

已统一到 `.vscode/tasks.json`（NPU 主线）：

- `run:npu:iverilog:one-click`
- `run:npu:iverilog:one-click:wave`
- `run:npu:cluster:iverilog:one-click`
- `run:npu:cluster:iverilog:one-click:wave`
- `run:npu:vivado:one-click:batch`
- `run:npu:vivado:one-click:gui`
- `run:npu:cluster:vivado:one-click:batch`
- `run:npu:cluster:vivado:one-click:gui`

## 6. 下一步建议

- 接入 `npu_dispatch_sched`（任务切片与 tile 分发）
- 接入 `npu_acc_bias_act_quant`（偏置/激活/量化）
- 将 `npu_core_cluster` 接入 SoC 控制面（AXI-Lite CSR + IRQ）
- 增加 perf counter（MAC/cycle、带宽利用率）用于赛题指标打分

