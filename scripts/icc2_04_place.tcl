################################################################################
# icc2_04_place.tcl  -  ICC2 step 4: placement + pre-CTS optimization
#
#   place_opt = coarse placement -> timing/DRV optimization (sizing, buffering,
#               Vt swap) -> legalization (cells snapped onto rows/sites)
#   Clocks are still IDEAL here (no clock tree yet).
#
# run:  cd pnr ; icc2_shell -f ../scripts/icc2_04_place.tcl > icc2_04.log 2>&1 < /dev/null
################################################################################
source [file dirname [info script]]/common_setup.tcl
set_host_options -max_cores 4

open_lib ${DESIGN}.nlib
copy_block -from ${DESIGN}/powerplan -to ${DESIGN}/place -force
current_block ${DESIGN}/place
link_block

#------------------------------------------------------------------------------
# 1. SETTINGS
#   routing layers : M2..M7 for signals (M1 = pin access inside cells,
#                    M8 = power mesh; M9/MRDL unused)
#   no scan chains in this design -> don't stop on missing SCANDEF
#------------------------------------------------------------------------------
set_ignored_layers -min_routing_layer M2 -max_routing_layer M7
set_app_options -name place.coarse.continue_on_missing_scandef -value true

# pre-placement sanity check (floorplan, libs, constraints)
check_design -checks pre_placement_stage > reports/04_check_pre_place.rpt

#------------------------------------------------------------------------------
# 2. PLACE + OPTIMIZE
#------------------------------------------------------------------------------
place_opt

# cells added by optimization (buffers, tie cells) need their PG pins tied
connect_pg_net -automatic

#------------------------------------------------------------------------------
# 3. REPORTS
#------------------------------------------------------------------------------
check_legality                                   > reports/04_legality.rpt
report_utilization                               > reports/04_utilization.rpt
report_qor -summary                              > reports/04_qor.rpt
report_timing -scenarios func@ss -max_paths 5    > reports/04_timing_setup.rpt
report_threshold_voltage_group                   > reports/04_vt_usage.rpt

# congestion: quick global route just to build the congestion map
route_global -congestion_map_only true
report_congestion                                > reports/04_congestion.rpt

# every placed std cell now sits on a rail -> floating std cells must be 0
check_pg_connectivity                            > reports/04_pg_connectivity.rpt

save_block
save_lib
puts "\n==== Placement done: block ${DESIGN}/place saved ===="
exit
