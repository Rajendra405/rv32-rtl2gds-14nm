#!/bin/bash
# run_drc.sh - physical verification: DRC with IC Validator on the final GDS
# usage (from project root):  bash scripts/run_drc.sh
PROJ=$(cd "$(dirname "$0")/.." && pwd)
TECH=/data/pdk/pdk14nm/SAED14nm_EDK_03_2025/SAED14nm_EDK_TECH_DATA
GDS=$PROJ/pnr/outputs/rv32_soc.gds

mkdir -p $PROJ/pv/drc && cd $PROJ/pv/drc

#   -i   layout file        -f  format          -c  top cell
#   -I   include dir for the runset's #include files
#   (no -dp: distributed processing needs a license server this site lacks)
icv -i $GDS -f GDSII -c rv32_soc \
    -I $TECH/icv_drc -I $TECH/icv_drc/Include \
    $TECH/icv_drc/saed14nm_1p9m_drc_rules.rs \
    > icv_drc.log 2>&1

echo "----- DRC summary -----"
ls -1 *.LAYOUT_ERRORS 2>/dev/null
tail -40 rv32_soc.LAYOUT_ERRORS 2>/dev/null || tail -30 icv_drc.log
