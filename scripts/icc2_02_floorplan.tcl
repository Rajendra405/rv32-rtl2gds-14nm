################################################################################
# icc2_02_floorplan.tcl  -  ICC2 step 2: die/core, macro placement, pins, taps
#
# run:  cd pnr ; icc2_shell -f ../scripts/icc2_02_floorplan.tcl | tee icc2_02.log
################################################################################
source [file dirname [info script]]/common_setup.tcl
set_host_options -max_cores 4

open_lib ${DESIGN}.nlib
copy_block -from ${DESIGN}/init -to ${DESIGN}/floorplan
current_block ${DESIGN}/floorplan
link_block

#------------------------------------------------------------------------------
# 1. CORE / DIE
#   core = area where cells go (rows are created here)
#   core_offset = gap core->die edge, used later for the power ring
#   Size: 4 macros (72.52 x 139.8 each = 40.5k um2) + ~3k um2 std cells
#         -> core 210 x 340 = 71.4k um2  (~61% filled incl. std cells)
#------------------------------------------------------------------------------
set CORE_W 210.0
set CORE_H 340.0
initialize_floorplan -control_type core -shape R \
    -side_length [list $CORE_W $CORE_H] -core_offset {6}

#------------------------------------------------------------------------------
# 2. MACRO PLACEMENT (manual, fixed)
#   SRAM pins (from LEF): 20 inputs on LEFT edge, 8 outputs on RIGHT edge, M6
#   Left column  : MY (mirror) -> inputs turn to face the centre channel
#   Right column : R0          -> inputs already face the centre channel
#   y values are multiples of the 0.6 um row height
#------------------------------------------------------------------------------
set MW 72.52 ; set MH 139.8
set XL 15.0
set XR [expr {$CORE_W - 15.0 - $MW}]     ;# 122.48
set YB 10.2
set YT [expr {$CORE_H - 10.2 - $MH}]     ;# 190.0 -> keep on row grid below
set YT 190.2

foreach {inst x y orient} [list \
        u_sram0 $XL $YB MY \
        u_sram1 $XR $YB R0 \
        u_sram2 $XL $YT MY \
        u_sram3 $XR $YT R0 ] {
    set_cell_location -coordinates [list $x $y] -orientation $orient [get_cells $inst]
}
set_attribute [get_cells u_sram*] physical_status fixed

# halo: no std cell within 2 um of a macro (pin access + routing room)
create_keepout_margin -type hard -outer {2 2 2 2} [get_cells u_sram*]

#------------------------------------------------------------------------------
# 3. I/O PINS  (11 ports: clk, resetn, gpio_out[7:0], trap)
#   sides: 1=left 2=top 3=right 4=bottom
#------------------------------------------------------------------------------
set_block_pin_constraints -self -allowed_layers {M5 M6} -sides {1 3}
place_pins -self

#------------------------------------------------------------------------------
# 4. TAP CELLS (FinFET: connect wells to VDD/VSS -> prevent latch-up)
#   distance = max spacing between taps in a row (check databook rule)
#------------------------------------------------------------------------------
create_tap_cells -lib_cell [get_lib_cells */SAEDRVT14_TAPDS] \
    -distance 25 -pattern stagger -skip_fixed_cells

#------------------------------------------------------------------------------
# 5. REPORTS
#------------------------------------------------------------------------------
redirect reports/02_layers.rpt {
    foreach_in_collection l [get_layers -filter "layer_type==interconnect"] {
        puts [format "%-5s dir=%-10s pitch=%s  min_width=%s" \
            [get_object_name $l] \
            [get_attribute $l routing_direction] \
            [get_attribute $l pitch] \
            [get_attribute $l min_width]]
    }
}
redirect reports/02_macros.rpt {
    foreach_in_collection c [get_cells u_sram*] {
        puts "[get_object_name $c]  orient=[get_attribute $c orientation]  bbox=[get_attribute $c boundary_bbox]"
    }
}
report_utilization > reports/02_utilization.rpt
check_pin_placement -self > reports/02_pins.rpt

save_block
save_lib
puts "\n==== Floorplan done: block ${DESIGN}/floorplan saved ===="
exit
