#!/bin/bash
# run_lvs.sh - LVS (Layout Versus Schematic) with IC Validator
#
#   layout    : final GDS from ICC2 (devices extracted from the polygons)
#   schematic : our PG netlist (Verilog) + transistor netlists (CDL) of every
#               cell type used, converted to one SPICE file by icv_nettran
#   ICV checks every device and every connection match between the two.
#
#   Command style copied from the PDK demo (demo_all_in_one.RESULTS):
#     icv -i <gds> -c <top> -s <schematic> -stc <top> -sf SPICE <runset>
#
# usage (from project root):  bash scripts/run_lvs.sh
PROJ=$(cd "$(dirname "$0")/.." && pwd)
P=/data/pdk/pdk14nm/SAED14nm_EDK_03_2025
TECH=$P/SAED14nm_EDK_TECH_DATA
GDS=$PROJ/pnr/outputs/rv32_soc.gds
VLOG=$PROJ/pnr/outputs/rv32_soc_pg.v

mkdir -p $PROJ/pv/lvs && cd $PROJ/pv/lvs

#------------------------------------------------------------------------------
# 1. Verilog + cell CDLs  ->  one SPICE schematic netlist
#    (RVT + HVT std cells are used in the design, plus the SRAM)
#------------------------------------------------------------------------------
icv_nettran \
    -verilog $VLOG \
    -cdl $P/SAED14nm_EDK_STD_RVT/netlists/lvs/saed14rvt.cdl \
         $P/SAED14nm_EDK_STD_HVT/netlists/lvs/saed14hvt.cdl \
         $P/SAED14nm_EDK_SRAM/netlists/lvs/saed14sram.cdl \
    -outName rv32_soc.lvs -outType SPICE \
    > nettran.log 2>&1
echo "----- nettran -----"; tail -5 nettran.log; ls -lh rv32_soc.lvs 2>/dev/null

#------------------------------------------------------------------------------
# 2. LVS
#------------------------------------------------------------------------------
icv -i $GDS -f GDSII -c rv32_soc \
    -s rv32_soc.lvs -stc rv32_soc -sf SPICE \
    -I $TECH/icv_lvs -I $TECH/icv_lvs/Include \
    $TECH/icv_lvs/saed14nm_1p9m_lvs_runset.rs \
    > icv_lvs.log 2>&1

echo "----- LVS summary -----"
ls -1 *.LVS_ERRORS *.LAYOUT_ERRORS 2>/dev/null
grep -i -E "lvs compare results|final comparison|passed|failed|error" rv32_soc.LVS_ERRORS 2>/dev/null | head -20 \
    || tail -30 icv_lvs.log
