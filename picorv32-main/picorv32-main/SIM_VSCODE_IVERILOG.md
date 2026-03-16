# VS Code + Icarus Verilog 联合仿真指南（赛题三）

## 1）先装工具（Windows）

你要的三个命令里：

- `iverilog`：编译器
- `vvp`：运行器（通常和 `iverilog` 一起安装）
- `gtkwave`：波形查看器

可选：

- `covered`：覆盖率统计工具

### 方案 A（推荐，最省事）

安装 Icarus Verilog Windows 发行版（通常会同时带上 `iverilog` 和 `vvp`，很多版本也带 GTKWave）。

安装后优先检查：

```powershell
where.exe iverilog
where.exe vvp
where.exe gtkwave
```

如果 `gtkwave` 没找到，再单独安装 GTKWave。

### 方案 B（分开装）

1. 安装 Icarus Verilog（得到 `iverilog` + `vvp`）。
2. 单独安装 GTKWave（得到 `gtkwave`）。

---

## 2）把工具目录加到 PATH（具体命令）

下面命令会把常见安装路径追加到“用户 PATH”（不需要管理员）：

```powershell
$candidates = @(
  "C:\\iverilog\\bin",
  "C:\\iverilog\\gtkwave\\bin",
  "C:\\Program Files\\GTKWave\\bin",
  "C:\\Program Files (x86)\\GTKWave\\bin"
)

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ([string]::IsNullOrWhiteSpace($userPath)) { $userPath = "" }

foreach ($p in $candidates) {
  if ((Test-Path $p) -and ($userPath -notlike "*$p*")) {
    if ($userPath.Length -gt 0 -and -not $userPath.EndsWith(";")) {
      $userPath += ";"
    }
    $userPath += $p
  }
}

[Environment]::SetEnvironmentVariable("Path", $userPath, "User")
Write-Host "User PATH updated. Please reopen terminal/VS Code."
```

然后关闭并重新打开 VS Code 终端，再验证：

```powershell
iverilog -V
vvp -V
gtkwave --version
```

---

## 3）`covered`（覆盖率）怎么装

`covered` 在 Windows 原生环境通常不如 Linux/WSL 方便，建议放到 WSL 里跑覆盖率。

### 推荐：WSL 安装（只做覆盖率统计）

1. 安装 WSL（若未安装）：

```powershell
wsl --install -d Ubuntu
```

2. 在 Ubuntu 里安装：

```bash
sudo apt update
sudo apt install -y iverilog gtkwave covered
```

3. 验证：

```bash
iverilog -V
vvp -V
gtkwave --version
covered --version
```

---

## 4）VS Code 里直接跑

本工程已配置任务文件：

- [tasks.json](d:/FPGA/project_1/.vscode/tasks.json)

打开工作区 `d:\FPGA\project_1`，执行：

1. `Terminal -> Run Task`
2. 先选 `sim:ez:run`
3. 再选 `sim:ez:wave`

任务说明：

- `sim:check-tools`：检查 `iverilog/vvp`
- `sim:ez:build`：编译最小 testbench
- `sim:ez:run`：运行最小仿真
- `sim:ez:vcd`：生成 VCD
- `sim:ez:wave`：打开波形
- `sim:std:test_vcd`：运行仓库标准回归（需要 RISC-V 工具链）

---

## 5）赛题三覆盖率（95%）建议流程

Icarus 负责编译运行，`covered` 负责覆盖率统计：

1. 每个用例输出一个 VCD（如 `vcd/axi_burst_inc.vcd`）
2. `covered score` 分别打分
3. `covered merge` 合并
4. `covered report` 出总报告

示例：

```powershell
covered score -t testbench -v tb_soc_axi_burst.v -v your_soc_top.v -v picorv32.v -vcd vcd/reset.vcd -o cov/reset.cdd
covered score -t testbench -v tb_soc_axi_burst.v -v your_soc_top.v -v picorv32.v -vcd vcd/axi_single.vcd -o cov/axi_single.cdd
covered score -t testbench -v tb_soc_axi_burst.v -v your_soc_top.v -v picorv32.v -vcd vcd/axi_burst_inc.vcd -o cov/axi_burst_inc.cdd

covered merge -o cov/all.cdd cov/reset.cdd cov/axi_single.cdd cov/axi_burst_inc.cdd cov/cpu_npu_coop.cdd cov/illegal_boundary.cdd
covered report -m ltcf -o cov/coverage_report.txt cov/all.cdd
```
