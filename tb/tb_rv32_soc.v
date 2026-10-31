//==============================================================================
// tb_rv32_soc.v  -  self-checking testbench
//   Expected: CPU runs the boot-ROM program and writes 0xE2 to gpio_out.
//==============================================================================
`timescale 1ns/1ps
module tb_rv32_soc;

    reg        clk    = 1'b0;
    reg        resetn = 1'b0;
    wire [7:0] gpio_out;
    wire       trap;

    rv32_soc dut (.clk(clk), .resetn(resetn), .gpio_out(gpio_out), .trap(trap));

    always #2 clk = ~clk;                 // 4 ns period = 250 MHz

    initial begin
`ifdef FSDB
        $fsdbDumpfile("rv32_soc.fsdb");
        $fsdbDumpvars(0, tb_rv32_soc);
`else
        $dumpfile("rv32_soc.vcd");
        $dumpvars(0, tb_rv32_soc);
`endif
        repeat (5) @(posedge clk);
        resetn = 1'b1;
    end

    // print every completed bus transfer - easy to follow the program
    always @(posedge clk) begin
        if (dut.mem_valid && dut.mem_ready) begin
            if (dut.mem_wstrb != 4'b0000)
                $display("%8t  WRITE addr=%h data=%h strb=%b", $time,
                         dut.mem_addr, dut.mem_wdata, dut.mem_wstrb);
            else if (!dut.mem_instr)
                $display("%8t  READ  addr=%h data=%h", $time,
                         dut.mem_addr, dut.mem_rdata);
        end
    end

    // pass / fail checker
    integer cyc = 0;
    always @(posedge clk) begin
        cyc <= cyc + 1;
        if (trap) begin
            $display("*** FAIL: CPU trap at cycle %0d (pc fetch addr %h)", cyc, dut.mem_addr);
            $finish;
        end
        if (gpio_out != 8'h00) begin
            if (gpio_out == 8'hE2) $display("*** PASS: gpio_out = 0x%h after %0d cycles", gpio_out, cyc);
            else                   $display("*** FAIL: gpio_out = 0x%h, expected 0xE2", gpio_out);
            $finish;
        end
        if (cyc > 5000) begin
            $display("*** FAIL: timeout, gpio_out never written");
            $finish;
        end
    end

endmodule
