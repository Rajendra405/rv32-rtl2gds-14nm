//==============================================================================
// rv32_soc.v  -  Top level for the RTL->GDS project
//
//   PicoRV32 (RV32I) + boot ROM (logic) + 1 KB RAM (4x SRAM1RW256x8 macros)
//   + 8-bit GPIO output register
//
// Memory map
//   0x0000_0000 - 0x0000_00FF : boot ROM  (64 words, synthesized as logic)
//   0x0000_1000 - 0x0000_13FF : RAM       (256 words x 32 bit = 4 byte lanes)
//   0x0000_2000               : GPIO_OUT  (write [7:0])
//
// Why 4 x 8-bit SRAMs instead of 1 x 32-bit?
//   RISC-V has byte/half-word stores (sb/sh). PicoRV32 tells us which bytes
//   to write with mem_wstrb[3:0]. One 8-bit SRAM per byte lane lets each lane
//   be written independently (SRAM1RW256x32 has no byte-enable).
//
// Bus timing (every access takes 2 cycles):
//   cycle 0 : mem_valid=1  -> SRAM pins driven, SRAM samples at end of cycle
//   cycle 1 : mem_ready=1  -> read data (SRAM O / ROM / GPIO) returned
//==============================================================================
module rv32_soc (
    input  wire       clk,
    input  wire       resetn,       // active-low reset
    output reg  [7:0] gpio_out,
    output wire       trap          // CPU hit an illegal instruction
);

    // SAED14 behavioral model writes when CSB=1 (despite the "B" in the name).
    // Kept as a parameter so we can flip it in ONE place if the datasheet
    // disagrees - simulation will tell us.
    localparam SRAM_CS_ACTIVE_HIGH = 1;

    //--------------------------------------------------------------------------
    // CPU
    //--------------------------------------------------------------------------
    wire        mem_valid, mem_instr;
    reg         mem_ready;
    wire [31:0] mem_addr, mem_wdata;
    wire [3:0]  mem_wstrb;          // 0000 = read, else byte-lane write enables
    reg  [31:0] mem_rdata;

    picorv32 #(
        .ENABLE_COUNTERS   (0),     // drop rdcycle/rdinstret counters (saves ~130 flops)
        .ENABLE_COUNTERS64 (0),
        .PROGADDR_RESET    (32'h0000_0000)
    ) u_cpu (
        .clk          (clk),
        .resetn       (resetn),
        .trap         (trap),
        .mem_valid    (mem_valid),
        .mem_instr    (mem_instr),
        .mem_ready    (mem_ready),
        .mem_addr     (mem_addr),
        .mem_wdata    (mem_wdata),
        .mem_wstrb    (mem_wstrb),
        .mem_rdata    (mem_rdata),
        .mem_la_read  (),
        .mem_la_write (),
        .mem_la_addr  (),
        .mem_la_wdata (),
        .mem_la_wstrb (),
        .pcpi_valid   (),
        .pcpi_insn    (),
        .pcpi_rs1     (),
        .pcpi_rs2     (),
        .pcpi_wr      (1'b0),
        .pcpi_rd      (32'b0),
        .pcpi_wait    (1'b0),
        .pcpi_ready   (1'b0),
        .irq          (32'b0),
        .eoi          (),
        .trace_valid  (),
        .trace_data   ()
    );

    //--------------------------------------------------------------------------
    // Address decode + handshake
    //--------------------------------------------------------------------------
    wire sel_rom  = (mem_addr[31:12] == 20'h00000);
    wire sel_ram  = (mem_addr[31:12] == 20'h00001);
    wire sel_gpio = (mem_addr[31:12] == 20'h00002);

    wire req = mem_valid & ~mem_ready;   // new request this cycle

    always @(posedge clk) begin
        if (!resetn) mem_ready <= 1'b0;
        else         mem_ready <= req;   // answer exactly one cycle later
    end

    // remember who must answer in the ready cycle
    localparam SRC_ROM = 2'd0, SRC_RAM = 2'd1, SRC_GPIO = 2'd2;
    reg [1:0] rsrc;
    always @(posedge clk)
        if (req) rsrc <= sel_ram ? SRC_RAM : sel_gpio ? SRC_GPIO : SRC_ROM;

    //--------------------------------------------------------------------------
    // RAM : 4 x SRAM1RW256x8 hard macros (one per byte lane)
    //   CE  : clock (rising edge)       A   : word address = mem_addr[9:2]
    //   CSB : chip select               WEB : 0 = write, 1 = read
    //   OEB : output enable (0 = on)    I/O : data in / out
    //--------------------------------------------------------------------------
    wire        ram_cs  = req & sel_ram;
    wire        ram_csb = SRAM_CS_ACTIVE_HIGH ? ram_cs : ~ram_cs;
    wire [7:0]  ram_a   = mem_addr[9:2];
    wire [31:0] ram_q;

    SRAM1RW256x8 u_sram0 (.CE(clk), .CSB(ram_csb), .WEB(~mem_wstrb[0]), .OEB(1'b0),
                          .A(ram_a), .I(mem_wdata[ 7: 0]), .O(ram_q[ 7: 0]));
    SRAM1RW256x8 u_sram1 (.CE(clk), .CSB(ram_csb), .WEB(~mem_wstrb[1]), .OEB(1'b0),
                          .A(ram_a), .I(mem_wdata[15: 8]), .O(ram_q[15: 8]));
    SRAM1RW256x8 u_sram2 (.CE(clk), .CSB(ram_csb), .WEB(~mem_wstrb[2]), .OEB(1'b0),
                          .A(ram_a), .I(mem_wdata[23:16]), .O(ram_q[23:16]));
    SRAM1RW256x8 u_sram3 (.CE(clk), .CSB(ram_csb), .WEB(~mem_wstrb[3]), .OEB(1'b0),
                          .A(ram_a), .I(mem_wdata[31:24]), .O(ram_q[31:24]));

    //--------------------------------------------------------------------------
    // GPIO output register
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!resetn)                           gpio_out <= 8'h00;
        else if (req & sel_gpio & mem_wstrb[0]) gpio_out <= mem_wdata[7:0];
    end

    //--------------------------------------------------------------------------
    // Boot ROM (hand-assembled RV32I program)
    //   sum = 1+2+...+10 = 55          (tests loop + branch)
    //   RAM[0]  = 55 (sw)              (tests word write)
    //   RAM[1]  = 0; byte1 = 0xAB (sb) (tests byte-lane write)
    //   x9 = RAM[0] + (RAM[1] >> 8) = 55 + 171 = 226 = 0xE2
    //   GPIO = 0xE2 ; then loop forever
    //--------------------------------------------------------------------------
    reg [31:0] rom_q;
    always @(posedge clk) begin
        if (req & sel_rom) begin
            case (mem_addr[7:2])
                6'd0 : rom_q <= 32'h000010B7; // 00: lui  x1, 0x1        x1 = 0x1000 (RAM)
                6'd1 : rom_q <= 32'h00002137; // 04: lui  x2, 0x2        x2 = 0x2000 (GPIO)
                6'd2 : rom_q <= 32'h00000193; // 08: addi x3, x0, 0      sum = 0
                6'd3 : rom_q <= 32'h00100213; // 0C: addi x4, x0, 1      i = 1
                6'd4 : rom_q <= 32'h00B00293; // 10: addi x5, x0, 11     limit
                6'd5 : rom_q <= 32'h004181B3; // 14: add  x3, x3, x4     loop: sum += i
                6'd6 : rom_q <= 32'h00120213; // 18: addi x4, x4, 1      i++
                6'd7 : rom_q <= 32'hFE521CE3; // 1C: bne  x4, x5, -8     -> loop
                6'd8 : rom_q <= 32'h0030A023; // 20: sw   x3, 0(x1)      RAM[0] = 55
                6'd9 : rom_q <= 32'h0000A223; // 24: sw   x0, 4(x1)      RAM[1] = 0
                6'd10: rom_q <= 32'h0AB00313; // 28: addi x6, x0, 0xAB
                6'd11: rom_q <= 32'h006082A3; // 2C: sb   x6, 5(x1)      RAM[1].byte1 = 0xAB
                6'd12: rom_q <= 32'h0000A383; // 30: lw   x7, 0(x1)      x7 = 55
                6'd13: rom_q <= 32'h0040A403; // 34: lw   x8, 4(x1)      x8 = 0x0000AB00
                6'd14: rom_q <= 32'h00845413; // 38: srli x8, x8, 8      x8 = 0xAB
                6'd15: rom_q <= 32'h008384B3; // 3C: add  x9, x7, x8     x9 = 0xE2
                6'd16: rom_q <= 32'h00912023; // 40: sw   x9, 0(x2)      GPIO = 0xE2
                6'd17: rom_q <= 32'h0000006F; // 44: jal  x0, 0          stay here
                default: rom_q <= 32'h00000013; //     nop
            endcase
        end
    end

    //--------------------------------------------------------------------------
    // Read-data mux (valid in the mem_ready cycle)
    //--------------------------------------------------------------------------
    always @(*) begin
        case (rsrc)
            SRC_RAM : mem_rdata = ram_q;
            SRC_GPIO: mem_rdata = {24'b0, gpio_out};
            default : mem_rdata = rom_q;
        endcase
    end

endmodule
