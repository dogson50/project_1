# NPU子系统模块划分与接口清单（赛题达标版）

更新时间：`2026-03-23`

## 1. 结论先行

1. `npu_core_4x4` 只能作为 **计算 tile**，不能单独作为“达标 NPU”。  
2. 赛题三要求的“合格 NPU”必须同时具备：
- 矩阵/向量乘（MAC 阵列）
- 累加（psum）与截断/饱和
- 偏置加
- 激活（至少 ReLU）
- 控制面（CSR + 状态机 + 中断）
- 数据面（AXI Burst 搬运 + 本地 SRAM）
3. 算力达标必须采用 **多 tile 并行（core cluster）**，必要时叠加 **PE 内 SIMD**。

---

## 2. 算力约束与最小并行度

设：

- 每个 `4x4` tile 每拍可做 `16 x SIMD_PER_PE` 次 MAC  
- 1 MAC 按 2 ops（乘+加）计
- tile 数量 `CORE_NUM`
- 主频 `f_clk`

则峰值算力：

\[
TOPS_{peak} = \frac{CORE\_NUM \cdot 16 \cdot SIMD\_PER\_PE \cdot 2 \cdot f\_{clk}}{10^{12}}
\]

等效约束：

\[
CORE\_NUM \cdot SIMD\_PER\_PE \ge \frac{0.5 \cdot 10^{12}}{32 \cdot f\_{clk}}
\]

常见频点对应下限：

- `200MHz`：`CORE_NUM * SIMD_PER_PE >= 79`
- `250MHz`：`CORE_NUM * SIMD_PER_PE >= 63`
- `300MHz`：`CORE_NUM * SIMD_PER_PE >= 53`

可行组合（示例）：

- `CORE_NUM=16, SIMD_PER_PE=4, f=250MHz` -> `0.512 TOPS`
- `CORE_NUM=20, SIMD_PER_PE=4, f=200MHz` -> `0.512 TOPS`
- `CORE_NUM=12, SIMD_PER_PE=6, f=250MHz` -> `0.576 TOPS`

---

## 3. 子系统分层（达标架构）

- 控制面：`npu_csr_if`、`npu_cmd_ctrl`
- 调度面：`npu_dispatch_sched`
- 计算面：`npu_core_tile_4x4`、`npu_core_cluster`
- 后处理面：`npu_acc_bias_act_quant`
- 数据面：`npu_local_buf_bank`（banked SRAM）+ SoC `AXI_DMA`
- 观测与功耗：`npu_irq_perf`、`npu_clk_dfs_ctrl`

```mermaid
flowchart LR
    CPU[picorv32_axi]
    CSR[npu_csr_if]
    CMD[npu_cmd_ctrl]
    SCH[npu_dispatch_sched]
    CLU[npu_core_cluster]
    PP[npu_acc_bias_act_quant]
    BUF[npu_local_buf_bank]
    DMA[AXI_DMA(SoC)]
    PERF[npu_irq_perf]
    PWR[npu_clk_dfs_ctrl]
    IRQ[irq_npu]

    CPU --> CSR
    CSR --> CMD
    CMD --> SCH
    SCH --> CLU
    CLU --> PP
    PP --> BUF
    BUF --> SCH
    CPU --> DMA
    DMA --> BUF
    BUF --> DMA
    CMD --> PERF
    CLU --> PERF
    SCH --> PERF
    CSR --> PWR
    PWR --> CLU
    PERF --> IRQ
```

---

## 4. 顶层模块 `npu_subsys_v2`（达标版）

### 模块功能

- 对外暴露 AXI-Lite（控制）+ 本地 SRAM 端口（数据）
- 对内串接 CSR/调度/cluster/后处理/统计与功耗模块

### 端口定义（逐端口）

```verilog
module npu_subsys_v2 #(
    parameter integer DATA_W      = 32, // 数据位宽
    parameter integer LOCAL_AW    = 16, // 本地地址位宽（word）
    parameter integer CORE_NUM    = 16, // 4x4 tile 个数
    parameter integer SIMD_PER_PE = 4   // 每个 PE 的 SIMD 因子
)(
    input  wire                 clk,            // 输入：系统时钟
    input  wire                 resetn,         // 输入：低有效复位

    // AXI-Lite CSR
    input  wire                 s_axi_awvalid,  // 输入：写地址有效
    output wire                 s_axi_awready,  // 输出：写地址ready
    input  wire [31:0]          s_axi_awaddr,   // 输入：写地址
    input  wire [2:0]           s_axi_awprot,   // 输入：保护属性
    input  wire                 s_axi_wvalid,   // 输入：写数据有效
    output wire                 s_axi_wready,   // 输出：写数据ready
    input  wire [31:0]          s_axi_wdata,    // 输入：写数据
    input  wire [3:0]           s_axi_wstrb,    // 输入：字节使能
    output wire                 s_axi_bvalid,   // 输出：写响应有效
    input  wire                 s_axi_bready,   // 输入：写响应ready
    input  wire                 s_axi_arvalid,  // 输入：读地址有效
    output wire                 s_axi_arready,  // 输出：读地址ready
    input  wire [31:0]          s_axi_araddr,   // 输入：读地址
    input  wire [2:0]           s_axi_arprot,   // 输入：保护属性
    output wire                 s_axi_rvalid,   // 输出：读数据有效
    input  wire                 s_axi_rready,   // 输入：读数据ready
    output wire [31:0]          s_axi_rdata,    // 输出：读数据

    // 本地 SRAM 口（由 SoC DMA 和 NPU 共享）
    output wire                 rd0_en,         // 输出：读口0使能（feature）
    output wire [LOCAL_AW-1:0]  rd0_addr,       // 输出：读口0地址
    input  wire [DATA_W-1:0]    rd0_data,       // 输入：读口0数据
    output wire                 rd1_en,         // 输出：读口1使能（weight）
    output wire [LOCAL_AW-1:0]  rd1_addr,       // 输出：读口1地址
    input  wire [DATA_W-1:0]    rd1_data,       // 输入：读口1数据
    output wire                 wr_en,          // 输出：写口使能（result）
    output wire [LOCAL_AW-1:0]  wr_addr,        // 输出：写口地址
    output wire [DATA_W-1:0]    wr_data,        // 输出：写口数据
    output wire [DATA_W/8-1:0]  wr_strb,        // 输出：写口字节使能

    output wire                 irq_npu         // 输出：NPU 中断
);
```

---

## 5. 子模块 `npu_csr_if`

### 模块功能

- AXI-Lite 寄存器终端
- 输出任务参数和低功耗配置
- 产生 `start/soft_reset`（W1P）与 `W1C` 清除请求

### 当前实现状态

- 已落地 RTL：`picorv32-main/picorv32-main/HDL_src/NPU_design/npu_csr_if.v`
- 已实现冻结版 CSR 地址映射：`0x00 ~ 0x50`
- 已实现 `CAPABILITY=32'h0000_003F`
- 已实现 `VERSION=32'h2026_0323`
- `status_* / err_code / PERF_*` 当前按镜像输入只读，`W1C` 通过清除脉冲输出给后级状态机消费

### 端口定义（逐端口）

```verilog
module npu_csr_if (
    input  wire         clk,                   // 输入：CSR 时钟
    input  wire         resetn,                // 输入：低有效复位

    // AXI-Lite
    input  wire         s_axi_awvalid,         // 输入：写地址有效
    output wire         s_axi_awready,         // 输出：写地址ready
    input  wire [31:0]  s_axi_awaddr,          // 输入：写地址
    input  wire [2:0]   s_axi_awprot,          // 输入：保护属性
    input  wire         s_axi_wvalid,          // 输入：写数据有效
    output wire         s_axi_wready,          // 输出：写数据ready
    input  wire [31:0]  s_axi_wdata,           // 输入：写数据
    input  wire [3:0]   s_axi_wstrb,           // 输入：字节使能
    output wire         s_axi_bvalid,          // 输出：写响应有效
    input  wire         s_axi_bready,          // 输入：写响应ready
    input  wire         s_axi_arvalid,         // 输入：读地址有效
    output wire         s_axi_arready,         // 输出：读地址ready
    input  wire [31:0]  s_axi_araddr,          // 输入：读地址
    input  wire [2:0]   s_axi_arprot,          // 输入：保护属性
    output wire         s_axi_rvalid,          // 输出：读数据有效
    input  wire         s_axi_rready,          // 输入：读数据ready
    output wire [31:0]  s_axi_rdata,           // 输出：读数据

    // 状态镜像输入
    input  wire         status_busy_i,         // 输入：busy
    input  wire         status_done_i,         // 输入：done
    input  wire         status_error_i,        // 输入：error
    input  wire         status_irq_pending_i,  // 输入：irq_pending
    input  wire [31:0]  err_code_i,            // 输入：错误码
    input  wire [31:0]  perf_cycle_i,          // 输入：总周期
    input  wire [31:0]  perf_mac_i,            // 输入：MAC计数
    input  wire [31:0]  perf_stall_mem_i,      // 输入：访存stall
    input  wire [31:0]  perf_stall_pipe_i,     // 输入：流水stall
    input  wire [31:0]  perf_dma_data_cyc_i,   // 输入：DMA有效周期
    input  wire [31:0]  perf_dma_win_cyc_i,    // 输入：DMA统计窗口周期

    // 任务配置输出
    output wire         cfg_start_pulse_o,     // 输出：启动脉冲(W1P)
    output wire         cfg_soft_reset_pulse_o,// 输出：软复位脉冲(W1P)
    output wire         cfg_irq_en_o,          // 输出：中断使能
    output wire         cfg_clk_gate_en_o,     // 输出：门控使能
    output wire         cfg_dfs_en_o,          // 输出：DFS使能
    output wire [1:0]   cfg_dfs_level_o,       // 输出：DFS档位
    output wire [7:0]   cfg_core_num_active_o, // 输出：启用tile数
    output wire [3:0]   cfg_simd_mode_o,       // 输出：SIMD模式（每PE并行度）
    output wire [3:0]   cfg_op_mode_o,         // 输出：算子模式
    output wire [3:0]   cfg_act_mode_o,        // 输出：激活模式
    output wire [31:0]  cfg_src0_base_o,       // 输出：src0基址
    output wire [31:0]  cfg_src1_base_o,       // 输出：src1基址
    output wire [31:0]  cfg_dst_base_o,        // 输出：dst基址
    output wire [15:0]  cfg_dim_m_o,           // 输出：M
    output wire [15:0]  cfg_dim_n_o,           // 输出：N
    output wire [15:0]  cfg_dim_k_o,           // 输出：K
    output wire [7:0]   cfg_stride_o,          // 输出：stride
    output wire [7:0]   cfg_pad_o,             // 输出：pad
    output wire [15:0]  cfg_qscale_o,          // 输出：qscale
    output wire [7:0]   cfg_qshift_o,          // 输出：qshift
    output wire [7:0]   cfg_qzp_o,             // 输出：qzp

    // W1C 清除输出
    output wire         w1c_done_o,            // 输出：清done
    output wire         w1c_error_o,           // 输出：清error
    output wire         w1c_irq_pending_o      // 输出：清irq_pending
);
```

---

## 6. 子模块 `npu_cmd_ctrl`

### 模块功能

- 任务状态机（IDLE/CHECK/RUN/DONE/ERR）
- 参数检查（维度、地址、模式、core_num_active）
- 锁存 job，避免运行中寄存器被改影响一致性

### 端口定义（逐端口）

```verilog
module npu_cmd_ctrl (
    input  wire         clk,                     // 输入：控制时钟
    input  wire         resetn,                  // 输入：低有效复位

    // CSR 输入
    input  wire         cfg_start_pulse_i,       // 输入：启动脉冲
    input  wire         cfg_soft_reset_pulse_i,  // 输入：软复位脉冲
    input  wire [7:0]   cfg_core_num_active_i,   // 输入：有效核数
    input  wire [3:0]   cfg_simd_mode_i,         // 输入：SIMD模式
    input  wire [3:0]   cfg_op_mode_i,           // 输入：算子模式
    input  wire [3:0]   cfg_act_mode_i,          // 输入：激活模式
    input  wire [31:0]  cfg_src0_base_i,         // 输入：src0
    input  wire [31:0]  cfg_src1_base_i,         // 输入：src1
    input  wire [31:0]  cfg_dst_base_i,          // 输入：dst
    input  wire [15:0]  cfg_dim_m_i,             // 输入：M
    input  wire [15:0]  cfg_dim_n_i,             // 输入：N
    input  wire [15:0]  cfg_dim_k_i,             // 输入：K
    input  wire [7:0]   cfg_stride_i,            // 输入：stride
    input  wire [7:0]   cfg_pad_i,               // 输入：pad
    input  wire [15:0]  cfg_qscale_i,            // 输入：qscale
    input  wire [7:0]   cfg_qshift_i,            // 输入：qshift
    input  wire [7:0]   cfg_qzp_i,               // 输入：qzp

    // Cluster/后处理反馈
    input  wire         cluster_done_i,          // 输入：cluster完成
    input  wire         cluster_error_i,         // 输入：cluster错误
    input  wire [31:0]  cluster_err_code_i,      // 输入：cluster错误码
    input  wire         post_done_i,             // 输入：后处理完成
    input  wire         post_error_i,            // 输入：后处理错误

    // W1C 清除
    input  wire         w1c_done_i,              // 输入：清done
    input  wire         w1c_error_i,             // 输入：清error
    input  wire         w1c_irq_pending_i,       // 输入：清irq_pending

    // 输出到调度/cluster
    output wire         run_start_o,             // 输出：任务启动
    output wire         job_valid_o,             // 输出：job有效
    output wire [7:0]   job_core_num_active_o,   // 输出：有效核数
    output wire [3:0]   job_simd_mode_o,         // 输出：SIMD模式
    output wire [3:0]   job_op_mode_o,           // 输出：算子模式
    output wire [3:0]   job_act_mode_o,          // 输出：激活模式
    output wire [31:0]  job_src0_base_o,         // 输出：src0
    output wire [31:0]  job_src1_base_o,         // 输出：src1
    output wire [31:0]  job_dst_base_o,          // 输出：dst
    output wire [15:0]  job_dim_m_o,             // 输出：M
    output wire [15:0]  job_dim_n_o,             // 输出：N
    output wire [15:0]  job_dim_k_o,             // 输出：K
    output wire [7:0]   job_stride_o,            // 输出：stride
    output wire [7:0]   job_pad_o,               // 输出：pad
    output wire [15:0]  job_qscale_o,            // 输出：qscale
    output wire [7:0]   job_qshift_o,            // 输出：qshift
    output wire [7:0]   job_qzp_o,               // 输出：qzp

    // 状态输出
    output wire         status_busy_o,           // 输出：busy
    output wire         status_done_o,           // 输出：done(W1C)
    output wire         status_error_o,          // 输出：error(W1C)
    output wire         status_irq_pending_o,    // 输出：irq_pending(W1C)
    output wire [31:0]  err_code_o               // 输出：错误码
);
```

---

## 7. 子模块 `npu_dispatch_sched`

### 模块功能

- 把一个大矩阵任务切成多个 tile 子任务。
- 轮询/并行向 `npu_core_cluster` 下发子任务。
- 管理 cluster 写回地址和任务完成聚合。

### 端口定义（逐端口）

```verilog
module npu_dispatch_sched #(
    parameter integer CORE_NUM = 16
)(
    input  wire         clk,                  // 输入：调度时钟
    input  wire         resetn,               // 输入：低有效复位
    input  wire         run_start_i,          // 输入：任务开始
    input  wire         job_valid_i,          // 输入：job有效
    input  wire [7:0]   job_core_num_active_i,// 输入：有效核数
    input  wire [31:0]  job_src0_base_i,      // 输入：src0基址
    input  wire [31:0]  job_src1_base_i,      // 输入：src1基址
    input  wire [31:0]  job_dst_base_i,       // 输入：dst基址
    input  wire [15:0]  job_dim_m_i,          // 输入：M
    input  wire [15:0]  job_dim_n_i,          // 输入：N
    input  wire [15:0]  job_dim_k_i,          // 输入：K

    // 对 cluster 的子任务下发
    output wire                 tile_cmd_valid_o,    // 输出：子任务有效
    input  wire                 tile_cmd_ready_i,    // 输入：cluster可接收
    output wire [31:0]          tile_src0_base_o,    // 输出：子任务src0
    output wire [31:0]          tile_src1_base_o,    // 输出：子任务src1
    output wire [31:0]          tile_dst_base_o,     // 输出：子任务dst
    output wire [15:0]          tile_dim_m_o,        // 输出：子任务M
    output wire [15:0]          tile_dim_n_o,        // 输出：子任务N
    output wire [15:0]          tile_dim_k_o,        // 输出：子任务K
    output wire [7:0]           tile_core_mask_o,    // 输出：核使能mask（低8示例）

    // cluster 完成反馈
    input  wire                 tile_done_i,         // 输入：子任务完成
    input  wire                 tile_error_i,        // 输入：子任务错误
    input  wire [31:0]          tile_err_code_i,     // 输入：子任务错误码

    output wire                 sched_done_o,        // 输出：总任务完成
    output wire                 sched_error_o,       // 输出：总任务错误
    output wire [31:0]          sched_err_code_o,    // 输出：总任务错误码
    output wire                 stall_sched_pulse_o  // 输出：调度等待脉冲
);
```

---

## 8. 子模块 `npu_core_tile_4x4`

### 模块功能

- 单个 `4x4` 脉动阵列 tile。
- 读入分块数据，输出局部部分和（partial sum）。

### 端口定义（逐端口）

```verilog
module npu_core_tile_4x4 #(
    parameter integer DATA_W      = 32, // 输入打包位宽
    parameter integer PSUM_W      = 40, // 累加位宽
    parameter integer LOCAL_AW    = 16, // 地址位宽
    parameter integer SIMD_PER_PE = 4   // 每PE并行度
)(
    input  wire                 clk,               // 输入：tile时钟
    input  wire                 resetn,            // 输入：低有效复位
    input  wire                 core_clk_en_i,     // 输入：门控使能
    input  wire                 tile_start_i,      // 输入：tile启动
    input  wire [31:0]          tile_src0_base_i,  // 输入：tile src0基址
    input  wire [31:0]          tile_src1_base_i,  // 输入：tile src1基址
    input  wire [15:0]          tile_dim_k_i,      // 输入：tile K维

    // 本地读口（由 cluster 复用/仲裁）
    output wire                 rd0_en_o,          // 输出：读口0使能
    output wire [LOCAL_AW-1:0]  rd0_addr_o,        // 输出：读口0地址
    input  wire [DATA_W-1:0]    rd0_data_i,        // 输入：读口0数据
    output wire                 rd1_en_o,          // 输出：读口1使能
    output wire [LOCAL_AW-1:0]  rd1_addr_o,        // 输出：读口1地址
    input  wire [DATA_W-1:0]    rd1_data_i,        // 输入：读口1数据

    // psum 输出
    output wire                 psum_valid_o,       // 输出：psum有效
    output wire [PSUM_W-1:0]    psum_data_o,        // 输出：psum数据
    output wire [LOCAL_AW-1:0]  psum_addr_o,        // 输出：psum写地址

    output wire                 tile_done_o,        // 输出：tile完成
    output wire                 tile_error_o,       // 输出：tile错误
    output wire [31:0]          tile_err_code_o,    // 输出：tile错误码
    output wire                 mac_event_pulse_o,  // 输出：MAC事件
    output wire                 stall_mem_pulse_o,  // 输出：访存stall
    output wire                 stall_pipe_pulse_o  // 输出：流水stall
);
```

---

## 9. 子模块 `npu_core_cluster`

### 模块功能

- 管理多个 `npu_core_tile_4x4` 并行运行。
- 完成 tile 级输出聚合与完成信号归约。

### 端口定义（逐端口）

```verilog
module npu_core_cluster #(
    parameter integer CORE_NUM = 16
)(
    input  wire         clk,                 // 输入：cluster时钟
    input  wire         resetn,              // 输入：低有效复位
    input  wire         core_clk_en_i,       // 输入：时钟使能
    input  wire [7:0]   core_num_active_i,   // 输入：启用核数
    input  wire [3:0]   simd_mode_i,         // 输入：SIMD模式

    // 子任务输入
    input  wire         tile_cmd_valid_i,    // 输入：子任务有效
    output wire         tile_cmd_ready_o,    // 输出：可接收子任务
    input  wire [31:0]  tile_src0_base_i,    // 输入：子任务src0
    input  wire [31:0]  tile_src1_base_i,    // 输入：子任务src1
    input  wire [31:0]  tile_dst_base_i,     // 输入：子任务dst
    input  wire [15:0]  tile_dim_m_i,        // 输入：子任务M
    input  wire [15:0]  tile_dim_n_i,        // 输入：子任务N
    input  wire [15:0]  tile_dim_k_i,        // 输入：子任务K
    input  wire [7:0]   tile_core_mask_i,    // 输入：核使能mask

    // 对外本地 SRAM 接口（可由cluster内部仲裁复用）
    output wire                 rd0_en_o,          // 输出：读口0使能
    output wire [15:0]          rd0_addr_o,        // 输出：读口0地址
    input  wire [31:0]          rd0_data_i,        // 输入：读口0数据
    output wire                 rd1_en_o,          // 输出：读口1使能
    output wire [15:0]          rd1_addr_o,        // 输出：读口1地址
    input  wire [31:0]          rd1_data_i,        // 输入：读口1数据

    // 输出到后处理
    output wire                 clus_out_valid_o,  // 输出：cluster输出有效
    output wire [39:0]          clus_out_psum_o,   // 输出：cluster部分和
    output wire [15:0]          clus_out_addr_o,   // 输出：cluster输出地址

    output wire                 clus_done_o,       // 输出：cluster完成
    output wire                 clus_error_o,      // 输出：cluster错误
    output wire [31:0]          clus_err_code_o,   // 输出：cluster错误码
    output wire                 mac_event_pulse_o, // 输出：MAC事件归约
    output wire                 stall_mem_pulse_o, // 输出：访存stall归约
    output wire                 stall_pipe_pulse_o // 输出：流水stall归约
);
```

---

## 10. 子模块 `npu_acc_bias_act_quant`

### 模块功能

- 完成“累加/偏置/激活/量化/饱和截断”完整链路。  
- 这是“合格 NPU”与“仅 MAC 阵列”的关键分界模块。

### 端口定义（逐端口）

```verilog
module npu_acc_bias_act_quant #(
    parameter integer IN_PSUM_W = 40,
    parameter integer OUT_W     = 32,
    parameter integer LOCAL_AW  = 16
)(
    input  wire                 clk,              // 输入：后处理时钟
    input  wire                 resetn,           // 输入：低有效复位
    input  wire [3:0]           act_mode_i,       // 输入：激活模式
    input  wire [15:0]          qscale_i,         // 输入：量化scale
    input  wire [7:0]           qshift_i,         // 输入：量化shift
    input  wire [7:0]           qzp_i,            // 输入：量化zero-point
    input  wire                 sat_en_i,         // 输入：饱和使能

    // cluster psum 输入
    input  wire                 clus_out_valid_i, // 输入：psum有效
    input  wire [IN_PSUM_W-1:0] clus_out_psum_i,  // 输入：psum
    input  wire [LOCAL_AW-1:0]  clus_out_addr_i,  // 输入：地址

    // 偏置输入（可来自 local_buf 或常量缓存）
    input  wire                 bias_valid_i,     // 输入：偏置有效
    input  wire [OUT_W-1:0]     bias_data_i,      // 输入：偏置值

    // 写回输出
    output wire                 out_valid_o,      // 输出：结果有效
    output wire [OUT_W-1:0]     out_data_o,       // 输出：结果数据
    output wire [LOCAL_AW-1:0]  out_addr_o,       // 输出：结果地址
    output wire [OUT_W/8-1:0]   out_strb_o,       // 输出：字节使能
    output wire                 post_done_o,      // 输出：后处理完成
    output wire                 post_error_o       // 输出：后处理错误
);
```

---

## 11. 子模块 `npu_local_buf_bank`

### 模块功能

- Banked SRAM 管理（减少访存冲突，提高 Burst 利用率）
- 支持 DMA 与 NPU 共享访问

### 端口定义（逐端口）

```verilog
module npu_local_buf_bank #(
    parameter integer DATA_W      = 32,
    parameter integer LOCAL_AW    = 16,
    parameter integer BANK_NUM    = 8,
    parameter integer DEPTH_WORDS = 65536
)(
    input  wire                 clk,              // 输入：缓冲时钟

    // DMA 写
    input  wire                 dma_wr_en_i,      // 输入：DMA写使能
    input  wire [LOCAL_AW-1:0]  dma_wr_addr_i,    // 输入：DMA写地址
    input  wire [DATA_W-1:0]    dma_wr_data_i,    // 输入：DMA写数据
    input  wire [DATA_W/8-1:0]  dma_wr_strb_i,    // 输入：DMA写strobe

    // DMA 读
    input  wire                 dma_rd_en_i,      // 输入：DMA读使能
    input  wire [LOCAL_AW-1:0]  dma_rd_addr_i,    // 输入：DMA读地址
    output wire [DATA_W-1:0]    dma_rd_data_o,    // 输出：DMA读数据

    // NPU 读口0
    input  wire                 npu_rd0_en_i,     // 输入：NPU读0使能
    input  wire [LOCAL_AW-1:0]  npu_rd0_addr_i,   // 输入：NPU读0地址
    output wire [DATA_W-1:0]    npu_rd0_data_o,   // 输出：NPU读0数据

    // NPU 读口1
    input  wire                 npu_rd1_en_i,     // 输入：NPU读1使能
    input  wire [LOCAL_AW-1:0]  npu_rd1_addr_i,   // 输入：NPU读1地址
    output wire [DATA_W-1:0]    npu_rd1_data_o,   // 输出：NPU读1数据

    // NPU 写
    input  wire                 npu_wr_en_i,      // 输入：NPU写使能
    input  wire [LOCAL_AW-1:0]  npu_wr_addr_i,    // 输入：NPU写地址
    input  wire [DATA_W-1:0]    npu_wr_data_i,    // 输入：NPU写数据
    input  wire [DATA_W/8-1:0]  npu_wr_strb_i,    // 输入：NPU写strobe

    // 冲突/性能统计
    output wire                 bank_conflict_pulse_o // 输出：bank冲突事件
);
```

---

## 12. 子模块 `npu_irq_perf`

### 模块功能

- 中断聚合与性能计数。
- 为赛题报告提供：`TOPS`、`总线利用率` 统计字段。

### 端口定义（逐端口）

```verilog
module npu_irq_perf (
    input  wire         clk,                   // 输入：统计时钟
    input  wire         resetn,                // 输入：低有效复位
    input  wire         cfg_irq_en_i,          // 输入：中断使能
    input  wire         status_busy_i,         // 输入：busy
    input  wire         status_done_i,         // 输入：done
    input  wire         status_error_i,        // 输入：error
    input  wire         w1c_done_i,            // 输入：清done
    input  wire         w1c_error_i,           // 输入：清error
    input  wire         w1c_irq_pending_i,     // 输入：清irq_pending
    input  wire         mac_event_pulse_i,     // 输入：MAC事件
    input  wire         stall_mem_pulse_i,     // 输入：访存stall
    input  wire         stall_pipe_pulse_i,    // 输入：流水stall
    input  wire         dma_data_beat_pulse_i, // 输入：DMA有效beat事件
    input  wire         dma_window_cyc_pulse_i,// 输入：DMA统计窗口事件

    output wire         irq_npu_o,             // 输出：中断请求
    output wire [31:0]  perf_cycle_o,          // 输出：总周期
    output wire [31:0]  perf_mac_o,            // 输出：MAC计数
    output wire [31:0]  perf_stall_mem_o,      // 输出：访存stall
    output wire [31:0]  perf_stall_pipe_o,     // 输出：流水stall
    output wire [31:0]  perf_dma_data_cyc_o,   // 输出：DMA有效周期
    output wire [31:0]  perf_dma_win_cyc_o     // 输出：DMA窗口周期
);
```

---

## 13. 子模块 `npu_clk_dfs_ctrl`

### 模块功能

- 门控 + DFS 统一控制
- 空闲关阵列时钟，忙时自动打开

### 端口定义（逐端口）

```verilog
module npu_clk_dfs_ctrl (
    input  wire       clk,                 // 输入：系统时钟
    input  wire       resetn,              // 输入：低有效复位
    input  wire       cfg_clk_gate_en_i,   // 输入：门控使能
    input  wire       cfg_dfs_en_i,        // 输入：DFS使能
    input  wire [1:0] cfg_dfs_level_i,     // 输入：DFS档位
    input  wire       status_busy_i,       // 输入：忙状态
    input  wire       dbg_force_clk_on_i,  // 输入：调试强制开时钟
    output wire       core_clk_en_o,       // 输出：核心时钟使能
    output wire [1:0] core_clk_div_sel_o   // 输出：核心分频选择
);
```

---

## 14. 合格 NPU 判定清单（功能完整性）

必须全满足：

- `矩阵/向量乘`：`npu_core_cluster` + `npu_core_tile_4x4`
- `MAC 阵列`：tile 内 PE 阵列
- `累加`：`npu_acc_bias_act_quant` 中 psum 累加路径
- `偏置`：`bias_data_i` 有效路径
- `激活`：`act_mode` 至少支持 ReLU
- `截断/饱和`：`sat_en` 路径
- `写回`：`out_valid/out_data/out_addr/out_strb`

只实现 MAC 而无后处理链路，不算合格 NPU。

---

## 15. 与赛题分值项对齐

| 赛题项 | 对应模块 |
|---|---|
| 4x4 脉动阵列（20分） | `npu_core_tile_4x4` |
| 动态可调阵列（25分） | `npu_core_cluster`（`core_num_active` + `simd_mode`） |
| AXI 共享总线互连（5分） | SoC `AXI_Interconnect_*` |
| DMA 控制器（5分） | SoC `AXI_DMA` + `npu_local_buf_bank` |
| 低功耗（5分） | `npu_clk_dfs_ctrl` |

---

## 16. 实施建议（按周推进）

1. 先锁定本文件端口，不再随意改名。  
2. 先做 `CORE_NUM=1` 功能闭环，验证完整链路。  
3. 再升到 `CORE_NUM>1` 并行，加入调度和统计。  
4. 最后冲刺 `CORE_NUM*SIMD` 达标并做带宽利用率优化。  
