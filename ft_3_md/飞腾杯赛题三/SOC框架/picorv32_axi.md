# picorv32_axi（当前 SoC 控制核）

## 模块定位

`picorv32_axi` 是当前 SoC 的唯一主控 CPU，负责：

- 从 Program RAM 取指执行
- 通过 AXI-Lite 访问 Data RAM 与 DMA CSR
- 处理外部中断与 DMA 中断

## 在顶层中的关键配置

在 `picorv32_AXI_SOC.v` 中当前启用：

- `ENABLE_IRQ = 1`
- `ENABLE_MUL = 1`
- `ENABLE_DIV = 1`
- `ENABLE_TRACE = 1`

对应输出可直接在 testbench 观察：

- `trap`
- `trace_valid / trace_data`
- `eoi[31:0]`

## 中断连接关系

```text
cpu_irq = irq | {31'd0, irq_dma}
```

即 `irq_dma` 汇入 `irq[0]` 位与外部中断一起送入 CPU。

## 软件控制路径（当前）

1. CPU 初始化栈和运行时环境
2. 访问 Data RAM 准备测试数据
3. 写 DMA CSR（地址、长度、启动）
4. 等待 `done` 或响应中断
5. 校验结果并写 PASS/FAIL

## 调试建议

- 观察 `dbg_reg_pc / dbg_reg_next_pc` 跟踪取指
- 观察 `dbg_decoder_trigger` 与 `dbg_decoded_*` 跟踪译码
- 观察 `dbg_mem_do_rinst/rdata/wdata` 跟踪访存与执行
