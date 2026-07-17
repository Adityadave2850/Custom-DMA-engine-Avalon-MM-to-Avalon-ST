#!/bin/bash
# =============================================================================
# run_sims.sh — build & run both testbenches with Icarus Verilog, producing
# VCD files viewable in GTKWave.
#
# Usage:
#   ./run_sims.sh
#
# Requires: iverilog, vvp (Icarus Verilog), gtkwave (for viewing results)
#   Ubuntu/Debian: sudo apt-get install iverilog gtkwave
# =============================================================================
set -e
cd "$(dirname "$0")"

echo "=== Building + running: full streaming_dma_ip testbench ==="
iverilog -g2005 -o sim_dma.out \
    ../rtl/dma_engine.v \
    ../rtl/avalon_onchip_mem.v \
    ../rtl/avalon_consumer.v \
    ../rtl/streaming_dma_ip.v \
    ../tb/tb_streaming_dma_ip.v
vvp sim_dma.out

echo
echo "=== Building + running: standalone producer/consumer testbench ==="
iverilog -g2005 -o sim_pc.out \
    ../rtl/avalon_producer.v \
    ../rtl/avalon_consumer.v \
    ../tb/tb_producer_consumer.v
vvp sim_pc.out

echo
echo "Done. Open waveforms with:"
echo "  gtkwave streaming_dma_ip.vcd streaming_dma_ip.gtkw"
echo "  gtkwave producer_consumer.vcd"
