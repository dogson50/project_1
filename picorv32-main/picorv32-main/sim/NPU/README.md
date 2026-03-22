# NPU Tile 仿真说明

本目录用于仿真 `HDL_src/NPU_design/npu_core_tile_4x4.v`。

## 文件

- `tb_npu_core_tile_4x4.v`：testbench（包含 PASS/FAIL 自检）
- `filelist_npu.f`：iverilog 文件列表
- `run_iverilog_npu.ps1`：Icarus 一键仿真脚本
- `run_vivado_npu.tcl`：Vivado/XSim 一键仿真脚本
- `tb_npu_core_cluster.v`：多 tile 并行 cluster testbench
- `filelist_npu_cluster.f`：cluster 的 iverilog 文件列表
- `run_iverilog_npu_cluster.ps1`：cluster Icarus 一键仿真脚本
- `run_vivado_npu_cluster.tcl`：cluster Vivado/XSim 一键仿真脚本

## 一键命令

在仓库根目录 `D:\FPGA\project_1` 执行：

### 1) Icarus Verilog（命令行）

```powershell
powershell -ExecutionPolicy Bypass -File .\picorv32-main\picorv32-main\sim\NPU\run_iverilog_npu.ps1
```

带波形导出（VCD）：

```powershell
powershell -ExecutionPolicy Bypass -File .\picorv32-main\picorv32-main\sim\NPU\run_iverilog_npu.ps1 -Wave
```

### 2) Vivado/XSim（Batch）

```powershell
vivado -mode batch -source .\picorv32-main\picorv32-main\sim\NPU\run_vivado_npu.tcl
```

### 3) Vivado/XSim（GUI）

```powershell
vivado -source .\picorv32-main\picorv32-main\sim\NPU\run_vivado_npu.tcl -tclargs gui
```

## npu_core_cluster 一键命令

### 1) Icarus Verilog（命令行）

```powershell
powershell -ExecutionPolicy Bypass -File .\picorv32-main\picorv32-main\sim\NPU\run_iverilog_npu_cluster.ps1
```

带波形导出（VCD）：

```powershell
powershell -ExecutionPolicy Bypass -File .\picorv32-main\picorv32-main\sim\NPU\run_iverilog_npu_cluster.ps1 -Wave
```

### 2) Vivado/XSim（Batch）

```powershell
vivado -mode batch -source .\picorv32-main\picorv32-main\sim\NPU\run_vivado_npu_cluster.tcl
```

### 3) Vivado/XSim（GUI）

```powershell
vivado -source .\picorv32-main\picorv32-main\sim\NPU\run_vivado_npu_cluster.tcl -tclargs gui
```
