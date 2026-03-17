# One-click Vivado simulation launcher for testbench_cpu
# argv0: firmware path (absolute or relative)
# argv1: max cycles
# argv2: flow mode: firmware | selftest
# argv3: run mode: gui | batch

set workspace [file normalize [pwd]]
set prj_file [file normalize [file join $workspace project_1.xpr]]
set rtl_file [file normalize [file join $workspace picorv32-main picorv32-main picorv32.v]]
set tb_file  [file normalize [file join $workspace picorv32-main picorv32-main testbench_cpu.v]]

set firmware_path ""
set max_cycles "200000"
set flow_mode "firmware"
set run_mode "gui"

if {[llength $argv] >= 1} { set firmware_path [lindex $argv 0] }
if {[llength $argv] >= 2} { set max_cycles [lindex $argv 1] }
if {[llength $argv] >= 3} { set flow_mode [lindex $argv 2] }
if {[llength $argv] >= 4} { set run_mode [lindex $argv 3] }

if {$firmware_path eq ""} {
    set firmware_path [file normalize [file join $workspace picorv32-main picorv32-main firmware firmware.hex]]
} else {
    set firmware_path [string map {"\\" "/"} $firmware_path]
}

puts "VIVADO project: $prj_file"
puts "VIVADO flow_mode: $flow_mode"
puts "VIVADO run_mode:  $run_mode"
puts "VIVADO firmware:  $firmware_path"
puts "VIVADO maxcycles: $max_cycles"

open_project $prj_file

set simset_name "sim_cpu"
if {[llength [get_filesets -quiet $simset_name]] == 0} {
    create_fileset -simset $simset_name
}
set simset [get_filesets $simset_name]

# Clean up stale simulation state to avoid simulate.log file-lock conflicts.
catch {close_sim}
catch {reset_simulation -simset $simset_name}

if {[llength [get_files -quiet -of_objects $simset $tb_file]] == 0} {
    add_files -fileset $simset_name $tb_file
}
if {[llength [get_files -quiet -of_objects $simset $rtl_file]] == 0} {
    add_files -fileset $simset_name $rtl_file
}

set_property top testbench_cpu $simset
set_property top_lib xil_defaultlib $simset
update_compile_order -fileset $simset_name

if {$flow_mode eq "selftest"} {
    set plusargs "-testplusarg selftest_alu -testplusarg maxcycles=$max_cycles"
} else {
    set plusargs "-testplusarg firmware=$firmware_path -testplusarg maxcycles=$max_cycles"
}

# Use -dict form to avoid interpreting value that starts with '-' as command options.
set_property -dict [list xsim.simulate.xsim.more_options $plusargs] $simset

puts "VIVADO xsim options: $plusargs"
launch_simulation -simset $simset_name -mode behavioral

# Always run simulation after launch so users don't need to click Run All manually.
run all

if {$run_mode eq "batch"} {
    close_sim
    close_project
    exit
}
