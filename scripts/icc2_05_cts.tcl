################################################################################
# icc2_05_cts.tcl  -  ICC2 step 5: Clock Tree Synthesis + post-CTS optimization
#
#   Before CTS the clock is "ideal": it reaches all 1454 flops + 4 SRAMs at the
#   same instant. CTS builds a real buffer tree from the clk port to every
#   sink, balancing the arrival times (skew) and keeping slew sharp.
#   After CTS clocks are "propagated" -> real latency/skew in every timing path
#   -> hold violations can now be fixed for real.
#
# run:  cd pnr ; icc2_shell -f ../scripts/icc2_05_cts.tcl > icc2_05.log 2>&1 < /dev/null
################################################################################
source [file dirname [info script]]/common_setup.tcl
set_host_options -max_cores 4

open_lib ${DESIGN}.nlib
copy_block -from ${DESIGN}/place -to ${DESIGN}/cts -force
current_block ${DESIGN}/cts
link_block

# what are the "Nets with DRC Violations" left after place_opt?
# (catch: a report must never stop the flow)
catch {redirect -file reports/05_drv_pre_cts.rpt {report_constraints -all_violators}}

#------------------------------------------------------------------------------
# 1. CLOCK CELLS - use only dedicated clock buffers/inverters if the lib has them
#    (balanced rise/fall, better for duty cycle and skew)
#------------------------------------------------------------------------------
set CTS_CELLS [get_lib_cells -quiet {*/SAEDRVT14_*CK*BUF* */SAEDRVT14_*CK*INV* */SAEDRVT14_*BUF*CK* */SAEDRVT14_*INV*CK*}]
if {[sizeof_collection $CTS_CELLS] > 0} {
    puts "INFO: CTS cells: [get_object_name $CTS_CELLS]"
    set_lib_cell_purpose -exclude cts [get_lib_cells */*]
    set_lib_cell_purpose -include cts $CTS_CELLS
} else {
    puts "INFO: no dedicated clock cells found - CTS uses regular buffers/inverters"
}

#------------------------------------------------------------------------------
# 2. CLOCK ROUTING RULE (NDR = non-default rule)
#    double width  -> lower resistance -> less delay variation
#    double spacing-> less coupling    -> less crosstalk noise on the clock
#    clock routed on M3..M6 (middle layers: good RC, away from the M7/M8 mesh)
#------------------------------------------------------------------------------
create_routing_rule CLK_NDR \
    -widths   {M3 0.068 M4 0.12 M5 0.12 M6 0.12} \
    -spacings {M3 0.1   M4 0.2  M5 0.2  M6 0.2}
set_clock_routing_rules -rules CLK_NDR -min_routing_layer M3 -max_routing_layer M6

#------------------------------------------------------------------------------
# 3. CTS TARGETS
#------------------------------------------------------------------------------
set_clock_tree_options -target_skew 0.05 -clocks [get_clocks clk]
foreach scn {func@ss func@ff} {
    current_scenario $scn
    set_max_transition 0.10 -clock_path [get_clocks clk]
    # pre-CTS uncertainty (0.20) included an estimate of skew; the real skew
    # is now measured, so keep only jitter + margin
    set_clock_uncertainty -setup 0.05 [get_clocks clk]
    set_clock_uncertainty -hold  0.02 [get_clocks clk]
}
current_scenario func@ss

#------------------------------------------------------------------------------
# 4. BUILD + ROUTE CLOCK TREE, THEN OPTIMIZE (incl. HOLD FIXING)
#    clock_opt = build_clock -> route_clock -> final_opto
#------------------------------------------------------------------------------
clock_opt
connect_pg_net -automatic

#------------------------------------------------------------------------------
# 5. REPORTS
#------------------------------------------------------------------------------
report_clock_qor -type summary                   > reports/05_clock_qor.rpt
report_qor -summary                              > reports/05_qor.rpt
report_timing -scenarios func@ss -delay_type max -max_paths 5 > reports/05_timing_setup.rpt
report_timing -scenarios func@ff -delay_type min -max_paths 5 > reports/05_timing_hold.rpt
catch {redirect -file reports/05_drv_post_cts.rpt {report_constraints -all_violators}}
check_legality                                   > reports/05_legality.rpt
check_pg_connectivity                            > reports/05_pg_connectivity.rpt

save_block
save_lib
puts "\n==== CTS done: block ${DESIGN}/cts saved ===="
exit
