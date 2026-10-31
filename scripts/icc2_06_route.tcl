################################################################################
# icc2_06_route.tcl  -  ICC2 step 6: routing, post-route opt, fillers, outputs
#
#   route_auto : global route -> track assignment -> detail route (+ DRC fix)
#   route_opt  : post-route timing/DRV/hold optimization with real RC
#   fillers    : close the gaps in every row (continuous wells/implants)
#   outputs    : netlist, SPEF, SDC for PrimeTime ; GDS for IC Validator
#
# run:  cd pnr ; icc2_shell -f ../scripts/icc2_06_route.tcl > icc2_06.log 2>&1 < /dev/null
################################################################################
source [file dirname [info script]]/common_setup.tcl
set_host_options -max_cores 4
file mkdir outputs

open_lib ${DESIGN}.nlib
copy_block -from ${DESIGN}/cts -to ${DESIGN}/route -force
current_block ${DESIGN}/route
link_block

#------------------------------------------------------------------------------
# 1. SETTINGS
#   DRV (max transition/cap) fixing at BOTH corners from now on
#   timing-driven routing + antenna fixing (uses the tech file antenna rules)
#------------------------------------------------------------------------------
set_scenario_status func@ff -max_transition true -max_capacitance true

set_app_options -name route.global.timing_driven -value true
set_app_options -name route.track.timing_driven  -value true
set_app_options -name route.detail.timing_driven -value true
set_app_options -name route.detail.antenna       -value true

#------------------------------------------------------------------------------
# 2. ROUTE + POST-ROUTE OPTIMIZATION
#------------------------------------------------------------------------------
route_auto -max_detail_route_iterations 30
route_opt
connect_pg_net -automatic

#------------------------------------------------------------------------------
# 3. FILLER CELLS (largest first; skip ECO / special N-well-break fillers)
#------------------------------------------------------------------------------
set FILLERS [sort_collection -descending \
    [get_lib_cells -filter "name=~SAEDRVT14_FILL* && name!~*ECO* && name!~*NNW*" */*] width]
puts "INFO: fillers = [get_object_name $FILLERS]"
create_stdcell_fillers -lib_cells $FILLERS
connect_pg_net -automatic
catch {remove_stdcell_fillers_with_violation}

#------------------------------------------------------------------------------
# 4. CHECKS + REPORTS
#------------------------------------------------------------------------------
check_routes                                     > reports/06_check_routes.rpt
catch {redirect -file reports/06_check_lvs.rpt {check_lvs -max_errors 200}}
check_legality                                   > reports/06_legality.rpt
check_pg_connectivity                            > reports/06_pg_connectivity.rpt
report_qor -summary                              > reports/06_qor.rpt
report_timing -scenarios func@ss -delay_type max -max_paths 5 > reports/06_timing_setup.rpt
report_timing -scenarios func@ff -delay_type min -max_paths 5 > reports/06_timing_hold.rpt
catch {redirect -file reports/06_drv.rpt {report_constraints -all_violators}}
report_clock_qor -type summary                   > reports/06_clock_qor.rpt
report_power                                     > reports/06_power.rpt
report_utilization                               > reports/06_utilization.rpt

save_block
save_lib

#------------------------------------------------------------------------------
# 5. OUTPUTS
#   rv32_soc.v      : logical netlist          -> PrimeTime
#   rv32_soc_pg.v   : netlist with VDD/VSS + physical cells -> LVS
#   *.spef          : extracted parasitics per corner -> PrimeTime
#   rv32_soc.gds    : final layout, std-cell + SRAM GDS merged in -> DRC/LVS
#------------------------------------------------------------------------------
catch {write_verilog outputs/${DESIGN}.v}
catch {write_verilog -include {pg_netlist all_physical_cells} outputs/${DESIGN}_pg.v}
catch {write_parasitics -output outputs/${DESIGN}}
catch {write_sdc -output outputs/${DESIGN}.sdc}
if {[catch {write_gds -design ${DESIGN}/route -layer_map $GDS_MAP \
            -merge_files [concat $GDS_STD $GDS_SRAM] -long_names \
            outputs/${DESIGN}.gds} msg]} { puts "INFO: write_gds: $msg" }

puts "\n==== Routing done: block ${DESIGN}/route saved, outputs/ written ===="
exit
