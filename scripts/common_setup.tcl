################################################################################
# common_setup.tcl
# ONE place for every library / tech path. DC, ICC2 and PrimeTime all
# "source" this file, so if a path changes you fix it here only.
#
# Project : rv32_soc  (PicoRV32 + 4x SRAM1RW256x8)  RTL -> GDS
# PDK     : Synopsys SAED 14nm FinFET EDK (03_2025), 1P9M (1 poly, 9 metals)
################################################################################

#------------------------------------------------------------------------------
# 0. Project
#------------------------------------------------------------------------------
set DESIGN      rv32_soc                                  ;# top module name
set PROJ        [file normalize [file dirname [info script]]/..]

#------------------------------------------------------------------------------
# 1. PDK roots
#------------------------------------------------------------------------------
set PDK         /data/pdk/pdk14nm/SAED14nm_EDK_03_2025
set TECH        $PDK/SAED14nm_EDK_TECH_DATA
set STD_RVT     $PDK/SAED14nm_EDK_STD_RVT
set STD_LVT     $PDK/SAED14nm_EDK_STD_LVT
set STD_HVT     $PDK/SAED14nm_EDK_STD_HVT
set SRAM        $PDK/SAED14nm_EDK_SRAM

#------------------------------------------------------------------------------
# 2. PVT corners  (process / voltage / temperature)
#    name format: <proc><volt>v<temp>c   e.g. ss0p72v125c = SlowSlow, 0.72V, 125C
#    SETUP is checked at the SLOW corner  -> data arrives as late as possible
#    HOLD  is checked at the FAST corner  -> data arrives as early as possible
#------------------------------------------------------------------------------
set CORNER_SETUP  ss0p72v125c
set CORNER_HOLD   ff0p88vm40c
set CORNER_TEMPINV ss0p72vm40c   ;# FinFET temperature-inversion check (cold can be slower!)

#------------------------------------------------------------------------------
# 3. Liberty (.db) timing libraries  -> used by DC (synthesis) and PT (STA)
#    .lib = human-readable text,  .db = compiled binary that Synopsys tools read
#    "base" = normal logic cells. (cg=clock gates, iso/ulvl/dlvl/ret = low-power
#    cells for UPF designs - we don't need them)
#------------------------------------------------------------------------------
proc std_db  {dir vt corner} { return $dir/liberty/nldm/base/saed14${vt}_base_${corner}.db }
proc sram_db {corner}        { return $::SRAM/liberty/nldm/saed14sram_${corner}.db }

# Synthesis maps to RVT first; LVT (fast, leaky) and HVT (slow, low leakage)
# are added so the tools can swap Vt to fix timing / save leakage.
set DB_SETUP [list \
    [std_db $STD_RVT rvt $CORNER_SETUP] \
    [std_db $STD_LVT lvt $CORNER_SETUP] \
    [std_db $STD_HVT hvt $CORNER_SETUP] \
    [sram_db $CORNER_SETUP] ]

set DB_HOLD [list \
    [std_db $STD_RVT rvt $CORNER_HOLD] \
    [std_db $STD_LVT lvt $CORNER_HOLD] \
    [std_db $STD_HVT hvt $CORNER_HOLD] \
    [sram_db $CORNER_HOLD] ]

#------------------------------------------------------------------------------
# 4. Physical libraries for ICC2  (.ndm = "New Data Model")
#    frame  = abstract layout (cell outline, pins, blockages) for P&R
#    timing = the .db timing merged in
#------------------------------------------------------------------------------
set NDM_LIBS [list \
    $STD_RVT/ndm/saed14rvt_base_frame_timing.ndm \
    $STD_LVT/ndm/saed14lvt_base_frame_timing.ndm \
    $STD_HVT/ndm/saed14hvt_base_frame_timing.ndm \
    $SRAM/ndm/saed14sram_frame_timing.ndm ]

#------------------------------------------------------------------------------
# 5. Technology files
#    .tf      : metal/via layers, widths, spacings, pitches, routing direction
#    .tlup    : TLU+ RC tables -> wire resistance/capacitance per layer
#               Cmax = worst (most cap)  -> use with SETUP corner
#               Cmin = best  (least cap) -> use with HOLD  corner
#    map      : maps layer names in .tf to layer names in .tlup/.itf
#------------------------------------------------------------------------------
set TECH_TF       $TECH/tf/saed14nm_1p9m.tf
set TLUP_MAX      $TECH/tlup/saed14nm_1p9m_Cmax.tlup
set TLUP_MIN      $TECH/tlup/saed14nm_1p9m_Cmin.tlup
set TLUP_NOM      $TECH/tlup/saed14nm_1p9m_Cnom.tlup
set TLUP_MAP      $TECH/map/saed14nm_tf_itf_tluplus.map
set GDS_MAP       $TECH/map/saed14nm_1p9m_gdsin_gdsout.map

#------------------------------------------------------------------------------
# 6. GDS (final layout of each cell) - merged into our chip GDS at the end
#------------------------------------------------------------------------------
set GDS_STD   [glob -nocomplain $STD_RVT/gds/*.gds $STD_LVT/gds/*.gds $STD_HVT/gds/*.gds]
set GDS_SRAM  $SRAM/gds/saed14sram.gds

#------------------------------------------------------------------------------
# 7. Physical verification (IC Validator) rule decks
#------------------------------------------------------------------------------
set ICV_DRC   $TECH/icv_drc/saed14nm_1p9m_drc_rules.rs
set ICV_FILL  $TECH/icv_drc/saed14nm_1p9m_mfill_rules.rs
set ICV_LVS   $TECH/icv_lvs/saed14nm_1p9m_lvs_runset.rs

#------------------------------------------------------------------------------
# 8. Sanity check - catches a typo in a path BEFORE a 20-min run fails
#------------------------------------------------------------------------------
foreach f [concat $DB_SETUP $DB_HOLD $NDM_LIBS \
           [list $TECH_TF $TLUP_MAX $TLUP_MIN $TLUP_MAP $GDS_MAP $GDS_SRAM $ICV_DRC $ICV_LVS]] {
    if {![file exists $f]} { puts "ERROR: missing $f" }
}
puts "common_setup.tcl loaded: DESIGN=$DESIGN  setup=$CORNER_SETUP  hold=$CORNER_HOLD"
