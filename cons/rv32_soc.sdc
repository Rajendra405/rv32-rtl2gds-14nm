################################################################################
# rv32_soc.sdc  -  Timing constraints (Synopsys Design Constraints)
#
# SDC tells the tools WHAT timing the chip must meet. The same file is used by
# DC (synthesis), ICC2 (place & route) and PrimeTime (signoff).
#
# Units come from the .lib : time = ns, capacitance = from lib (we avoid raw
# cap numbers by using load_of a real cell pin).
################################################################################

#------------------------------------------------------------------------------
# 1. CLOCK
#    4.0 ns period = 250 MHz. Every flop-to-flop path must finish in < 4 ns.
#------------------------------------------------------------------------------
set CLK_PERIOD 4.0
create_clock -name clk -period $CLK_PERIOD [get_ports clk]

#------------------------------------------------------------------------------
# 2. CLOCK NON-IDEALITIES  (before CTS the clock is "ideal" = zero delay,
#    so we add margins that model the real clock tree that comes later)
#
#    uncertainty -setup : jitter + expected skew  -> makes setup check harder
#    uncertainty -hold  : expected skew           -> makes hold check harder
#    transition         : slew at the flop clock pins (ideal clock has 0)
#------------------------------------------------------------------------------
set_clock_uncertainty -setup 0.20 [get_clocks clk]
set_clock_uncertainty -hold  0.05 [get_clocks clk]
set_clock_transition         0.08 [get_clocks clk]

#------------------------------------------------------------------------------
# 3. INPUT / OUTPUT DELAYS
#    Our chip talks to other chips. We don't know their logic, so we budget:
#    the outside world uses 40% of the period, our logic gets the other 60%.
#
#    set_input_delay  : time AFTER the clock edge when the input arrives
#    set_output_delay : time the output must be ready BEFORE the next edge
#------------------------------------------------------------------------------
set IO_DLY [expr 0.4 * $CLK_PERIOD]
set INPUTS [remove_from_collection [all_inputs] [get_ports clk]]

set_input_delay  $IO_DLY -clock clk $INPUTS
set_output_delay $IO_DLY -clock clk [all_outputs]

#------------------------------------------------------------------------------
# 4. ENVIRONMENT
#    driving cell : inputs are driven by a medium inverter (realistic slew)
#    load         : each output drives ~4 inverter inputs
#------------------------------------------------------------------------------
set_driving_cell -lib_cell SAEDRVT14_INV_S_4 $INPUTS
set_load [expr 4 * [load_of [index_collection [get_lib_pins */SAEDRVT14_INV_S_4/A] 0]]] [all_outputs]

#------------------------------------------------------------------------------
# 5. DESIGN RULES (electrical limits)
#    max_transition : slow edges = more delay + more short-circuit power
#    max_fanout     : one gate driving too many pins
#------------------------------------------------------------------------------
set_max_transition 0.25 [current_design]
set_max_fanout     32   [current_design]
