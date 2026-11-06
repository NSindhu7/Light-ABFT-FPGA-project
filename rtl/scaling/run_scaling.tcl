# ============================================================
# run_scaling.tcl - Synthesize + implement scale_top for N = 2, 4, 8
#   Run from the Vivado Tcl Console of the abft_scaling project:
#     source C:/labft_exp5/run_scaling.tcl
#   Reports are written to the project folder: util_N*.txt, timing_N*.txt
# ============================================================
set out_dir [get_property DIRECTORY [current_project]]
set_property top scale_top [current_fileset]
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value {-mode out_of_context} -objects [get_runs synth_1]

foreach n {2 4 8} {
    puts "================ N = $n ================"
    set_property generic "N=$n" [current_fileset]
    catch {reset_run impl_1}
    reset_run synth_1
    launch_runs impl_1 -jobs 4
    wait_on_run impl_1
    open_run impl_1 -name impl_N$n
    report_utilization -hierarchical -file "$out_dir/util_N$n.txt"
    report_timing_summary -file "$out_dir/timing_N$n.txt"
    report_power -file "$out_dir/power_N$n.txt"
    close_design
}
puts "Done. Reports are in $out_dir"
