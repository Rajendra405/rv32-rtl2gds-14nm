//==============================================================================
// sram_sim_model.v  -  SIMULATION-ONLY model of SAED14 SRAM1RW256x8
//
// Why: the vendor file saed14sram.v uses 'O_ud' before declaring it, which
// strict Verilog compilers (VCS) reject. This model has the same ports and
// the same behaviour as the vendor non-power-aware model:
//   - write : posedge CE, CSB=1, WEB=0          -> mem[A] <= I
//   - read  : posedge CE, CSB=1, WEB=1, OEB=0   -> O <= mem[A]  (1-cycle latency)
//
// Synthesis / P&R / STA do NOT use this file - they use the .db/.ndm views
// of the real macro.
//==============================================================================
module SRAM1RW256x8 (
    input        CE,
    input        CSB,
    input        WEB,
    input        OEB,
    input  [7:0] A,
    input  [7:0] I,
    output [7:0] O
);
    reg [7:0] mem [0:255];
    reg [7:0] O_ud;

    always @(posedge CE) begin
        if (CSB & !WEB)         mem[A] <= I;
        if (CSB &  WEB & !OEB)  O_ud   <= mem[A];
    end

    assign O = O_ud;

endmodule
