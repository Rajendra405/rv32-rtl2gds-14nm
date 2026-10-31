################################################################################
# pt_sta.tcl  -  Signoff STA in PrimeTime with post-route parasitics (SPEF)
#
#   Same netlist + SDC as ICC2, but PrimeTime is the "golden" timer: this is
#   the number you quote as final timing.
#
#   One run per corner (CORNER env variable):
#     ss     : ss0p72v125c + Cmax SPEF  -> setup  (classic worst case)
#     ssm40  : ss0p72vm40c + Cmax SPEF  -> setup  (FinFET temperature inversion;
#              SPEF is the 125C extraction -> approximation, noted in reports)
#     ff     : ff0p88vm40c + Cmin SPEF  -> hold
#
# run:  cd sta ; CORNER=ss pt_shell -f ../scripts/pt_sta.tcl | tee pt_ss.log
################################################################################
source [file dirname [info script]]/common_setup.tcl
set PNR_OUT $PROJ/pnr/outputs

if {[info exists ::env(CORNER)]} { set CORNER $::env(CORNER) } else { set CORNER ss }
switch $CORNER {
    ss    { set PVT $CORNER_SETUP   ; set SPEF $PNR_OUT/${DESIGN}.Cmax_125.spef }
    ssm40 { set PVT $CORNER_TEMPINV ; set SPEF $PNR_OUT/${DESIGN}.Cmax_125.spef }
    ff    { set PVT $CORNER_HOLD    ; set SPEF $PNR_OUT/${DESIGN}.Cmin_-40.spef }
    default { puts "ERROR: CORNER must be ss, ssm40 or ff" ; exit }
}
set RPT reports_${CORNER}
file mkdir $RPT
puts "INFO: corner=$CORNER  pvt=$PVT  spef=[file tail $SPEF]"

#------------------------------------------------------------------------------
# 1. LIBRARIES for this corner (std cells RVT/LVT/HVT + SRAM)
#------------------------------------------------------------------------------
set LIBS [list [std_db $STD_RVT rvt $PVT] [std_db $STD_LVT lvt $PVT] \
               [std_db $STD_HVT hvt $PVT] [sram_db $PVT]]
set_app_var search_path ". $PNR_OUT"
set_app_var link_path   [concat "*" $LIBS]

#------------------------------------------------------------------------------
# 2. DESIGN + CONSTRAINTS
#   post-CTS: clocks are propagated (real tree delays from SPEF), so the
#   uncertainty only covers jitter + margin, same as in ICC2 after CTS
#------------------------------------------------------------------------------
read_verilog $PNR_OUT/${DESIGN}.v
current_design $DESIGN
link_design

source $PROJ/cons/rv32_soc.sdc
set_propagated_clock [all_clocks]
set_clock_uncertainty -setup 0.05 [all_clocks]
set_clock_uncertainty -hold  0.02 [all_clocks]

#------------------------------------------------------------------------------
# 3. PARASITICS - real R and C of every routed wire
#------------------------------------------------------------------------------
read_parasitics -format SPEF $SPEF
report_annotated_parasitics -check > $RPT/annotated_parasitics.rpt

update_timing -full

#------------------------------------------------------------------------------
# 4. REPORTS
#------------------------------------------------------------------------------
check_timing -verbose                          > $RPT/check_timing.rpt
report_global_timing                           > $RPT/global_timing.rpt
report_qor                                     > $RPT/qor.rpt
# -slack_lesser_than 999: with -max_paths > 1 PT otherwise shows only
# violating paths (slack < 0) - and we have none
report_timing -delay_type max -max_paths 10 -slack_lesser_than 999 -nosplit \
    -transition_time -capacitance -nets -input_pins -significant_digits 3 \
                                               > $RPT/timing_setup.rpt
report_timing -delay_type min -max_paths 10 -slack_lesser_than 999 -nosplit \
    -transition_time -capacitance -nets -input_pins -significant_digits 3 \
                                               > $RPT/timing_hold.rpt
report_constraint -all_violators -nosplit      > $RPT/all_violators.rpt
report_clock_timing -type skew -significant_digits 3 > $RPT/clock_skew.rpt
report_clock_timing -type latency -significant_digits 3 > $RPT/clock_latency.rpt
report_analysis_coverage                       > $RPT/coverage.rpt

puts "\n==== PT done for corner $CORNER - see $RPT/ ===="
exit
