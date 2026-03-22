# 用法:
# 1) Batch:
#    vivado -mode batch -source picorv32-main/picorv32-main/sim/NPU/run_vivado_npu_cluster.tcl
# 2) GUI:
#    vivado -source picorv32-main/picorv32-main/sim/NPU/run_vivado_npu_cluster.tcl -tclargs gui

set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file normalize [file join $script_dir ".." ".."]]
cd $proj_root

set rtl_list [list \
    "HDL_src/NPU_design/npu_mac_lane.v" \
    "HDL_src/NPU_design/npu_pe.v" \
    "HDL_src/NPU_design/npu_core_tile_4x4.v" \
    "HDL_src/NPU_design/npu_core_cluster.v" \
    "sim/NPU/tb_npu_core_cluster.v" \
]

foreach f $rtl_list {
    if {![file exists $f]} {
        puts "ERROR: missing file -> $f"
        exit 1
    }
}

set run_gui 0
if {[llength $argv] > 0} {
    if {[string equal -nocase [lindex $argv 0] "gui"]} {
        set run_gui 1
    }
}

if {[file exists ".sim/xsim_npu_cluster"]} {
    file delete -force ".sim/xsim_npu_cluster"
}
file mkdir ".sim/xsim_npu_cluster"

puts "INFO: xvlog compile..."
eval xvlog -sv $rtl_list

puts "INFO: xelab..."
xelab -debug typical -s tb_npu_core_cluster_sim tb_npu_core_cluster

puts "INFO: xsim run..."
if {$run_gui} {
    xsim tb_npu_core_cluster_sim -gui
} else {
    xsim tb_npu_core_cluster_sim -runall
}

puts "INFO: done."

