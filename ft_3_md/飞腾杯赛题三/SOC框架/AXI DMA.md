# AXI DMA（当前实现对齐 `AXI_DMA.v`）

对应文件：`picorv32-main/picorv32-main/HDL_src/AXI_DMA.v`

## 模块职责

- 控制面：作为 `AXI-Lite Slave`，接收 CPU 配置寄存器
- 数据面：作为 `AXI Burst Master`，执行 `mem2mem` 搬运
- 中断：任务完成后置位 `irq_dma`（电平型 pending）

## 当前实现特性

- 数据宽度固定 `32-bit`
- 仅支持 `INCR burst`
- 地址与长度要求 4 字节对齐
- 通过内部 `burst_buf` 做“先读后写”批量搬运
- 支持可配置突发长度 `REG_BURST_WORDS`

## SoC 中连接方式

- CPU 通过互连访问 DMA CSR：`0x4000_0000 ~ 0x4000_FFFF`
- DMA 数据面不走互连，直接连接 `AXI_DualPort_RAM` 的 Port-B

## CSR 寄存器（已实现）

| Offset | 名称 | 属性 | 说明 |
|---|---|---|---|
| `0x00` | `CTRL` | RW | `bit0 start(W1P)`、`bit1 soft_reset(W1P)`、`bit2 irq_en` |
| `0x04` | `STATUS` | RW1C | `bit0 busy`、`bit1 done`、`bit2 error`、`bit3 irq_pending` |
| `0x08` | `SRC_ADDR` | RW | 源地址 |
| `0x0C` | `DST_ADDR` | RW | 目的地址 |
| `0x10` | `BYTE_LEN` | RW | 传输字节数 |
| `0x14` | `ERR_CODE` | RO | 错误码 |
| `0x18` | `PERF_CYCLE` | RO | 传输总周期 |
| `0x1C` | `PERF_RDWORDS` | RO | 读 word 计数 |
| `0x20` | `PERF_WRWORDS` | RO | 写 word 计数 |
| `0x24` | `BURST_WORDS` | RW | 每次突发 word 数（受缓存深度上限约束） |

## 错误码（已实现）

- `0x0`：无错误
- `0x1`：源地址未对齐
- `0x2`：目的地址未对齐
- `0x3`：长度非法（0 或未对齐）
- `0x4`：忙状态下重复 `start`

## 内部状态机（已实现）

- `ST_IDLE`
- `ST_ISSUE_AR`
- `ST_READ_BURST`
- `ST_ISSUE_AW`
- `ST_WRITE_BURST`
- `ST_WAIT_B`
- `ST_DONE`

## 软件使用顺序（建议）

1. 写 `SRC_ADDR / DST_ADDR / BYTE_LEN`
2. 可选写 `BURST_WORDS`
3. 写 `CTRL.start = 1`
4. 轮询 `STATUS.done` 或等待 `irq_dma`
5. 读 `ERR_CODE` 与性能计数器

## 现阶段限制

- 不支持 scatter-gather
- 不支持 2D stride
- 不支持多通道并发 DMA
- 数据目标目前主要为片上 Data RAM，未接 DDR 控制器
