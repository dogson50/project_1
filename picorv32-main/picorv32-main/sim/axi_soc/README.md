# AXI Demo SoC Simulation

## Files

1. `tb_picorv32_AXI_SOC.v`  
   AXI Demo SoC testbench.
2. `sw/`  
   Demo software and build scripts (`demo.hex` output).

## Quick Run (Icarus)

From `picorv32-main/picorv32-main`:

1. Build testbench:
   `iverilog -g2012 -o .sim/tb_picorv32_AXI_SOC.vvp sim/axi_soc/tb_picorv32_AXI_SOC.v HDL_src/picorv32_AXI_SOC.v HDL_src/AXI_Interconnect_2M3S.v HDL_src/AXI_DMA.v HDL_src/AXI_Block_RAM.v HDL_src/AXI_DualPort_RAM.v picorv32.v`
2. Run simulation (program is loaded by testbench parameter `PROG_MEM_INIT_FILE`):
   `vvp -N .sim/tb_picorv32_AXI_SOC.vvp +maxcycles=50000`
3. Override program hex at compile time (optional):
   `iverilog -g2012 -P tb_picorv32_AXI_SOC.PROG_MEM_INIT_FILE=\"sim/axi_soc/sw/demo.hex\" -o .sim/tb_picorv32_AXI_SOC.vvp sim/axi_soc/tb_picorv32_AXI_SOC.v HDL_src/picorv32_AXI_SOC.v HDL_src/AXI_Interconnect_2M3S.v HDL_src/AXI_DMA.v HDL_src/AXI_Block_RAM.v HDL_src/AXI_DualPort_RAM.v picorv32.v`

## Vivado One-Click Wave Preset

When launching AXI SoC simulation via `.vscode/vivado_one_click_axi_soc.tcl`,
the GUI flow auto-loads a default waveform preset from:
`.vscode/xsim_axi_soc_waves.tcl`

This preset includes:
1. Testbench control/status (`clk/resetn/trap/trace/cycle_counter`)
2. CPU internal state/decode (`cpu_state/decoder_trigger/mem_do_*`)
3. AXI master handshake (`cpu_axi_*`)
4. Program/Data RAM ports (`p0_axi_*`, `p1_axi_*`)

For a focused "Fetch-Decode-Execute" view, use VS Code task:
`run:vivado:axi-soc:one-click:fde:gui`

This uses preset:
`.vscode/xsim_axi_soc_waves_fde.tcl`

The preset watches TB-level debug aliases (`dbg_*`) defined in:
`sim/axi_soc/tb_picorv32_AXI_SOC.v`
so decode/execute signals are easier to find than deep hierarchy paths.

## Memory Map

1. Program RAM: `0x0000_0000 ~ 0x0000_FFFF`
2. Data RAM: `0x2000_0000 ~ 0x2000_FFFF`
3. DMA CSR: `0x4000_0000 ~ 0x4000_FFFF`
