#!/bin/bash
# run_sim.sh - compile + run RTL simulation with VCS
# usage (from project root):  bash scripts/run_sim.sh
set -e
PROJ=$(cd "$(dirname "$0")/.." && pwd)
# vendor saed14sram.v does not compile in VCS (O_ud used before declaration),
# so we simulate with our own equivalent model
SRAM_V=$PROJ/tb/sram_sim_model.v

mkdir -p $PROJ/sim && cd $PROJ/sim

vcs -full64 -sverilog -debug_access+all -kdb \
    -timescale=1ns/1ps \
    $PROJ/rtl/picorv32.v \
    $PROJ/rtl/rv32_soc.v \
    $PROJ/tb/tb_rv32_soc.v \
    $SRAM_V \
    -top tb_rv32_soc \
    -l vcs_compile.log

./simv -l sim.log

echo "----- result -----"
grep "\*\*\*" sim.log
