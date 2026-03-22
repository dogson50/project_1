# AXI Interconnect（当前版本）

对应文件：`picorv32-main/picorv32-main/HDL_src/AXI_Interconnect_2M3S.v`

## 模块定位

`AXI_Interconnect_2M3S` 负责把主设备请求按地址路由到 3 个从设备窗口：

- `s0` -> Program RAM
- `s1` -> Data RAM（CPU Port-A）
- `s2` -> DMA CSR

## 当前 SoC 实际使用方式

- 互连支持 `2 Master`（`m0/m1`），但在当前顶层中只启用 `m0=CPU`
- `m1` 预留，后续可用于新增主设备
- DMA 的 Burst 数据通路当前是旁路互连直连 Data RAM Port-B

## 地址译码规则

采用 `BASE/MASK` 命中：

`(addr & MASK) == BASE`

默认参数对应：

- `0x0000_xxxx` -> Program RAM
- `0x2000_xxxx` -> Data RAM
- `0x4000_xxxx` -> DMA CSR

## 仲裁和事务模型

- 写通路和读通路各有一个“活跃事务”槽位
- 支持 `m0/m1` 轮询仲裁（round-robin）
- 未命中地址走默认响应路径，避免主机死锁

## 验证关注点

- 同时请求时仲裁是否公平
- 地址命中与端口选通信号是否一致
- 非法地址访问是否可正常返回
- 连续读写场景下是否存在握手停滞
