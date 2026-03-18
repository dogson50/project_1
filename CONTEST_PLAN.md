# Heterogeneous CPU+NPU Contest Plan

Last updated: 2026-03-18

## 1. Problem Understanding

This project targets a low-power heterogeneous processor based on 32-bit CPU + 32-bit NPU, connected by AXI interconnect.
The core requirement is to deliver:

- CPU/NPU collaborative execution.
- AXI-Lite single-beat control path + AXI burst data path.
- Zero-copy style data flow (CPU for control, NPU for compute, DMA for movement).
- Verifiable performance, bandwidth utilization, and power-saving features.

## 2. Project Goals

### 2.1 Mandatory Goals

1. Integrate a 4x4 systolic-array NPU into a designated 32-bit CPU platform.
2. Implement AXI communication between CPU and NPU:
- AXI-Lite for control/status.
- AXI burst for high-throughput data transfer.
3. Pass functional verification:
- AXI burst incrementing-address correctness.
- CPU controls logic, NPU executes matrix operations.
- RTL simulation flow with at least 95% code-path coverage target.
4. Reach baseline performance targets:
- NPU peak >= 0.5 TOPS @ INT8.
- Burst-scene bus bandwidth utilization >= 60%.
5. Implement low-power clock-gating:
- Disable systolic-array clock when NPU is idle.

### 2.2 Optimization Goals

1. NPU peak target stretch: approach/exceed 1 TOPS @ INT8.
2. Burst bandwidth utilization stretch: >= 80%.
3. Dynamic systolic-array configurability (PE connectivity reconfiguration).
4. AXI shared-bus topology with higher parallel access capability.
5. DMA integration enhancement to reduce CPU data-move overhead.
6. DFS (dynamic frequency scaling) for NPU.
7. Explore additional low-power methods:
- Power gating.
- Multi-voltage domains.
8. AXI interface standardization and reusability.

## 3. Deliverables

1. Detailed design documentation.
2. RTL code.
3. RTL simulation report and/or FPGA validation report.
4. Functional test cases, stress tests, boundary tests, and metric logs.
5. Scoring evidence package (mapping feature -> score item).

## 4. Architecture Plan

## 4.1 High-Level Partition

1. CPU subsystem:
- Task scheduling.
- CSR programming.
- Interrupt handling.
2. AXI interconnect subsystem:
- AXI-Lite control path.
- AXI burst data path.
3. DMA subsystem:
- DDR <-> NPU data movement.
- Burst transaction generation.
4. NPU subsystem:
- 4x4 systolic array.
- Matrix operation pipeline.
- Busy/done/error reporting.
5. Power-management subsystem:
- Clock gate controller.
- DFS control hooks.

### 4.2 Data and Control Planes

1. Control plane:
- CPU writes CSR (src/dst/len/mode/start).
- CPU reads status/IRQ.
2. Data plane:
- DMA and NPU use burst transfers.
- Minimize data copies via direct memory transactions.

## 5. Verification and Test Plan

## 5.1 Functional Verification

1. RTL simulation is mandatory.
2. Test categories:
- Basic function tests.
- AXI single-beat and burst protocol tests.
- CPU-NPU collaboration tests.
- Stress tests.
- Boundary-condition tests.
3. Coverage target:
- >= 95% code-path coverage in joint simulation platform.

### 5.2 Performance Verification

1. NPU throughput estimation and measurement:
- TOPS @ INT8 (peak).
2. Bus efficiency:
- Burst bandwidth utilization.
3. AI inference workload:
- MNIST and/or CIFAR-10.
- Record inference latency and accuracy.

### 5.3 Power Verification

1. Measure power under multiple workloads.
2. Compare:
- Clock-gating on/off.
- DFS modes.
3. Record power-performance trade-off curves.

### 5.4 FPGA Validation

1. Base requirement: RTL simulation completion.
2. Bonus target: FPGA validation to gain extra score.

## 6. Score-Oriented Work Breakdown

1. 4x4 systolic array implementation (20 points baseline).
2. Optional dynamic systolic array (25 points path).
3. AXI shared-bus interconnect (5 points).
4. DMA controller (5 points).
5. Low-power design: clock gating / DFS (5 points).
6. Documentation quality and modular design clarity (10 points).
7. Performance optimization score:
- Baseline metrics define zero line.
- Linear score growth toward optimization targets.
- Maximum in this section: 50 points.
8. FPGA validation bonus: +10 points.

## 7. Milestone Plan

### M0: Baseline Bring-up

1. Confirm CPU simulation baseline and firmware flow.
2. Freeze interface specs for AXI-Lite CSR + AXI burst path.
3. Define measurable KPI formulas.

### M1: Functional Integration

1. Integrate 4x4 NPU core + control/status interface.
2. Complete AXI-Lite control channel and AXI burst data channel.
3. Run CPU->NPU collaborative matrix test end-to-end.

### M2: Verification Closure

1. Add burst increment-address correctness suite.
2. Add stress and corner-case suites.
3. Reach >=95% code-path coverage goal.

### M3: Performance and Power

1. Measure TOPS and bandwidth utilization.
2. Implement and validate clock gating.
3. Implement DFS prototype and evaluate gains.

### M4: Optimization and Final Package

1. Attempt 1 TOPS and 80% bandwidth stretch targets.
2. Complete report set and score-evidence matrix.
3. Execute FPGA validation if schedule allows.

## 8. KPI Definitions

1. NPU peak TOPS @ INT8:
- Formula: ops_per_cycle * freq_hz / 1e12.
2. Bus bandwidth utilization:
- Formula: effective_payload_bandwidth / theoretical_bandwidth.
3. Coverage:
- Covered code paths / total target code paths.
4. Power-saving ratio:
- (P_baseline - P_optimized) / P_baseline.

## 9. Risks and Mitigations

1. AXI protocol corner-case bugs:
- Mitigation: protocol assertions + randomized burst tests.
2. Throughput below target:
- Mitigation: pipeline balancing, burst length tuning, DMA outstanding tuning.
3. Coverage shortfall:
- Mitigation: coverage-driven test generation and gap-focused directed tests.
4. Power optimization side effects:
- Mitigation: add wake-up latency and correctness regression tests.
5. Schedule pressure for FPGA validation:
- Mitigation: parallelize RTL closure and board bring-up preparation.

## 10. Immediate Next Actions

1. Freeze AXI register map and transaction timing assumptions.
2. Define module ownership and interface contracts.
3. Create first-pass verification matrix (feature -> testcase -> metric -> pass criteria).
4. Start M0/M1 implementation and continuous regression scripts.

