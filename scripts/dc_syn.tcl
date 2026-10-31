################################################################################
# dc_syn.tcl  -  Logic synthesis with Design Compiler
#   RTL (Verilog)  ->  gate-level netlist of SAED14 standard cells + SRAM macros
#
# run:  cd syn ; dc_shell -f ../scripts/dc_syn.tcl | tee dc.log
################################################################################
source [file dirname [info script]]/common_setup.tcl

set_host_options -max_cores 4
file mkdir reports outputs

#------------------------------------------------------------------------------
# 1. LIBRARIES
#   target_library : cells DC is ALLOWED to use when building logic.
#                    RVT only = clean baseline. (LVT/HVT swaps come later in ICC2)
#   link_library   : every library needed to RESOLVE the netlist,
#                    incl. the SRAM macro we instantiated by name.
#                    "*" = designs already in memory.
#------------------------------------------------------------------------------
set_app_var search_path    ". $PROJ/rtl"
set_app_var target_library [std_db $STD_RVT rvt $CORNER_SETUP]
set_app_var link_library   [concat "*" $DB_SETUP]

#------------------------------------------------------------------------------
# 2. READ RTL
#   analyze   : syntax check + store in WORK
#   elaborate : build the design hierarchy (parameters resolved, generic gates)
#   link      : connect instances to their library cells (SRAM must resolve!)
#------------------------------------------------------------------------------
define_design_lib WORK -path ./WORK
analyze   -format verilog [list picorv32.v rv32_soc.v]
elaborate $DESIGN
current_design $DESIGN
link

check_design > reports/check_design.rpt

#------------------------------------------------------------------------------
# 3. CONSTRAINTS
#------------------------------------------------------------------------------
source $PROJ/cons/rv32_soc.sdc

# No "assign" statements in the netlist (ICC2 dislikes them):
# insert buffers where one net drives several ports / constants
set_fix_multiple_port_nets -all -buffer_constants

# report the clock/IO setup before compiling
report_clock              > reports/clocks.rpt
check_timing              > reports/check_timing.rpt

#------------------------------------------------------------------------------
# 4. COMPILE
#   compile_ultra : timing-driven synthesis with advanced optimizations
#   -no_autoungroup keeps u_cpu as a separate block (easier to read reports)
#------------------------------------------------------------------------------
compile_ultra -no_autoungroup

#------------------------------------------------------------------------------
# 5. REPORTS  (the numbers you'll quote in your resume / interview)
#------------------------------------------------------------------------------
report_qor                                   > reports/qor.rpt
report_timing -delay_type max -max_paths 10 \
              -transition_time -nets -input_pins  > reports/timing_setup.rpt
report_timing -delay_type min -max_paths 10  > reports/timing_hold.rpt
report_constraint -all_violators             > reports/violators.rpt
report_area -hierarchy                       > reports/area.rpt
report_power                                 > reports/power.rpt
report_reference -hierarchy                  > reports/cells_used.rpt

#------------------------------------------------------------------------------
# 6. OUTPUTS for ICC2
#   netlist (.v) + constraints (.sdc) as DC sees them after synthesis
#------------------------------------------------------------------------------
change_names -rules verilog -hierarchy
write -format verilog -hierarchy -output outputs/${DESIGN}.v
write -format ddc     -hierarchy -output outputs/${DESIGN}.ddc
write_sdc                                outputs/${DESIGN}.sdc

puts "\n==== DC done. Check reports/qor.rpt and reports/violators.rpt ===="
exit
