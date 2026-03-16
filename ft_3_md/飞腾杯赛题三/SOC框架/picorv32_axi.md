# picorv32_axi

## 作用
`picorv32_axi` 是 SoC 的控制 CPU，负责：
- 初始化各外设寄存器；
- 下发 NPU 任务参数（地址、长度、模式）；
- 处理中断并调度下一任务。

它更偏“控制面处理器”，大数据搬运由 DMA/NPU 完成。

## 模块关系

```mermaid
flowchart LR
    CPU[picorv32_axi] -->|AXI-Lite| IC[AXI Interconnect]
    IRQ[IRQ Ctrl] -->|irq| CPU
```

## 典型软件流程
1. CPU 写 [[AXI-Lite CSR]]：配置 `src/dst/len/mode`。
2. CPU 写 `start=1` 启动 DMA + NPU。
3. CPU 轮询 `busy/done` 或等待中断。
4. 中断到来后读取状态，清中断，处理下一帧。

## 对接建议
- 使用统一内存映射地址（CSR、DMA、IRQ）。
- 中断采用“电平有效 + 写 1 清除”的寄存器语义。
- 在固件里保留超时机制，防止硬件异常导致死等。

## 验证要点
- 复位后 PC 正常运行到固件入口。
- CPU 可稳定读写 CSR/DMA/IRQ 寄存器。
- 中断触发后，CPU 能进入处理流程并正确返回。

