# NPU设计启发汇总（基于参考工程）

更新时间：`2026-03-22`

## 1. 参考范围

本总结基于你给的这些工程代码：

- `g:\TD_project\v11_1\v1280720\v10_27\fpga_prj__\import\Accel_Conv.v` 及其引用模块
- `d:\FPGA\project_1\universal_NPU-CNN_accelerator-main\universal_NPU-CNN_accelerator-main`
- `d:\FPGA\project_1\NPUSoC-main\NPUSoC-main`
- `d:\FPGA\project_1\NPU_on_FPGA-master\NPU_on_FPGA-master`

目标是提炼“对当前赛题三可落地”的启发，而不是直接复用某个工程。

## 2. 结论先行

可用的一句话结论：

1. `Accel_Conv` 适合借鉴“算子流水+量化后处理+多通道并行”的计算核组织方式。  
2. `universal_NPU` 适合借鉴“类型化接口+流水线握手控制+模块拆分规范”。  
3. `NPUSoC-main` 适合借鉴“sequencer + compute + shared memory 仲裁”的任务驱动框架。  
4. `NPU_on_FPGA-master` 适合借鉴“指令/任务描述 + 编译脚本链路 + DDR搬运意识”，但实现风格偏旧。  
5. 你们当前最优路线仍然是：**CPU(AXI-Lite控制) + DMA(AXI4 Burst数据搬运) + NPU本地SRAM计算域**，先用SRAM闭环，再扩展DDR。

## 3. 分工程启发

## 3.1 来自 Accel_Conv 的启发

关键观察（代码证据）：

- `Accel_Conv.v` 顶层已经清晰分成控制接口、数据输入输出、核心计算三部分。
- 数据口采用 `AXI-Lite + AXI-Stream` 组合，控制与数据面天然分离。
- `accel_top.v` 内部链路是典型 CNN 加速流水：
  `sub_zero_point -> conv_kernel -> acc -> quant -> relu -> pool -> ofm_store`。
- 多处 `*_1x8` 模块（如 `module_quant_1x8.v`、`module_pool_kernel_1x8.v`）体现了“按通道并行复制”的工程思路。

对你们可直接吸收的点：

- NPU核心内部模块化命名应按功能拆分，避免一个大 always 块把控制/计算/存储混在一起。
- 后处理单元（量化、激活、池化）应独立，便于后续替换和资源评估。
- 使用固定并行度参数（如 `LANE_NUM`）而不是硬编码 8 路，便于赛后扩展。

不建议直接照搬的点：

- `Accel_Conv` 偏“特定CNN数据流”，接口与时序强绑定，不适合直接做通用NPU子系统。
- 大量端口硬展开（几十上百个信号）会放大集成复杂度，建议改成总线化/结构化接口。

## 3.2 来自 universal_NPU-CNN_accelerator-main 的启发

关键观察（代码证据）：

- `npu_v2/RTL/common/mac_pkg.sv` 用 `package + typedef struct` 组织数据与配置，接口语义清晰。
- `npu_v2/RTL/common/pipe_ctrl.sv` 提供可复用的 ready/valid 流水控制。
- `npu_v2/RTL/MAC/mac.sv` 体现了 `preprocess -> lane array -> accumulator` 的经典拆分。
- `npu_v2/TB/MAC/tb_mac.sv` 存在 `matrix_multiply` 引用但缺少实现，说明工程尚未完全收敛。
- `npu_v1` 模块更偏固定流程和硬连线控制（`step/en_read/en_bias` 等），灵活性较弱。

对你们可直接吸收的点：

- 先定义“接口类型和数据格式”，再写模块，实现协同成本会显著降低。
- 把 `pipe_ctrl` 这一类通用握手模块沉淀成公共库，后续 DMA/NPU/后处理都能复用。
- 计算阵列模块按“前处理、计算、累加、异常监控”分层，验证可并行推进。

不建议直接照搬的点：

- `npu_v2` 当前更像计算核试验田，不是可直接上板的 SoC 级方案。
- 测试基线不完整，不能作为你们“最终可交付版本”的主干。

## 3.3 来自 NPUSoC-main 的启发

关键观察（代码证据）：

- `rtl/top.v` 明确体现了 `sequencer + compute + memory` 三者解耦。
- 通过 `mem_client_qmem/smem/cmem` 做共享存储访问仲裁，结构简单直接。
- `rtl/sequencer.v`（含 Chisel 生成逻辑）体现了“任务流驱动执行”的方法。

对你们可直接吸收的点：

- 把“任务调度”和“算子执行”拆成两个层级：`cmd_ctrl` 与 `npu_core`。
- 给共享存储访问设计明确优先级与状态机，而不是分散在各模块临时仲裁。

不建议直接照搬的点：

- 该工程总线与存储组织更偏自定义简化接口，和你们当前 AXI SoC 架构不一致。

## 3.4 来自 NPU_on_FPGA-master 的启发

关键观察（代码证据）：

- `npu_inst_excutor.v / npu_inst_fsm.v` 是典型“指令驱动NPU”设计，128-bit指令编码较完整。
- 工程有“训练/导出参数/生成指令/仿真评估”的端到端脚本思路。
- 模块里明确考虑了 DDR 读写与 FIFO 缓冲，体现了数据搬运瓶颈意识。

对你们可直接吸收的点：

- 你们可以把“复杂 ISA”简化成“任务描述符（descriptor）”，同样能保留可编程性。
- 软硬协同链路（脚本生成权重、配置、测试向量）必须尽早建立，不然后期联调会卡死。

不建议直接照搬的点：

- 工具链年代较早、实现风格偏重状态机大块逻辑，可维护性一般。
- 对当前赛题目标来说，完整 ISA 化不是第一优先，先保证性能和可验证性更重要。

## 4. 对当前项目最有价值的统一启发

## 4.1 架构层

- 控制面和数据面必须彻底分离。  
控制面走 `AXI-Lite CSR`，数据面走 `AXI4 Burst(DMA)`，NPU核内走本地 SRAM 接口。
- NPU 不直接承担“系统级搬运复杂度”，DMA 承担跨地址空间搬运，NPU专注计算。
- 先用片上 SRAM 完成 MNIST 闭环，再扩展 DDR，不影响控制面定义。

## 4.2 模块层

建议固定为以下边界（便于并行分工）：

- `npu_csr_if`：寄存器映射与中断状态。
- `npu_cmd_ctrl`：任务生命周期（IDLE/BUSY/DONE/ERR）。
- `npu_dma_if`：仅做 DMA 任务描述下发与状态回读（或后续并入全局DMA）。
- `npu_buf_mgr`：本地 SRAM bank / ping-pong 管理。
- `npu_preproc`：零点/格式转换/排布。
- `npu_core`：MAC阵列与累加。
- `npu_postproc`：量化/激活/裁剪。
- `npu_store`：结果写回本地缓冲或触发回搬运。
- `npu_irq_perf`：中断与性能计数器。

## 4.3 验证层

- 单模块 testbench（先功能） + 子系统 testbench（再吞吐）。
- 统一 PASS/FAIL 约定，避免只看波形不出结论。
- 性能计数器至少包含：`cycle_total`、`cycle_stall_mem`、`cycle_stall_core`、`dma_bytes`、`mac_ops`。

## 5. 你们下一步可执行动作（建议）

1. 冻结 `NPU CSR` 地址与字段，不再频繁改控制面。  
2. 按上面模块边界分配队员并行开发。  
3. 先做“单层卷积 + ReLU + 量化 + 回写”最小闭环。  
4. 在 AXI DMA 上补齐 INCR Burst 正确性测试和带宽统计。  
5. 最后再决定 DDR 接入节奏（赛题分数冲刺阶段再上）。  

---

如果你同意，我下一步可以直接再生成一份《NPU模块分工任务单.md》（按3人或4人团队版本），你可以直接发给队员执行。
