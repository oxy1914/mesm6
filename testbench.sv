//
// Run the processor with memory attached.
//
// Copyright (c) 2019 Serge Vakulenko
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
`default_nettype none
`include "mesm6_defines.sv"

module testbench();

// Global time parameters.
timeunit 1ns / 1ps;

// Inputs.
// Clock, reset, interrupt rquest
logic        clk, reset, irq;

// Instruction memory signals.
logic        ibus_rd;       // fetch request
logic [14:0] ibus_addr;     // address
logic [47:0] ibus_input;    // instruction word from memory
logic        ibus_done;     // operation completed

// Data memory signals.
logic        dbus_rd;       // read request
logic        dbus_wr;       // write request
logic [14:0] dbus_addr;     // address
logic [47:0] dbus_output;   // data to memory
logic [47:0] dbus_input;    // data from memory
logic        dbus_done;     // operation completed

// Instantiate CPU.
mesm6_core cpu(
    clk,                    // clock on rising edge
    reset,                  // reset on rising edge
    irq,                    // interrupt request

    // Instruction memory bus.
    ibus_rd,                // request instruction fetch
    ibus_addr,              // memory address
    ibus_input,             // instruction word read
    ibus_done,              // memory operation completed

    // Data memory bus.
    dbus_rd,                // request data read
    dbus_wr,                // request data write
    dbus_addr,              // memory address
    dbus_output,            // data written
    dbus_input,             // data read
    dbus_done               // memory operation completed
);

// Instruction memory.
imemory prom(
    clk,                    // clock on rising edge
    ibus_addr,              // memory address
    ibus_rd,                // read request
    ibus_input,             // data from memory
    ibus_done               // operation completed
);

// Data memory.
dmemory ram(
    clk,                    // clock on rising edge
    dbus_addr,              // memory address
    dbus_rd,                // read request
    dbus_wr,                // write request
    dbus_output,            // data to memory
    dbus_input,             // data from memory
    dbus_done               // operation completed
);

string tracefile = "output.trace";
int limit;
int tracelevel;             // Trace level
int tracefd;                // Trace file descriptor
time ctime;                 // Current time

//
// Last fetch address
//
logic [`UPC_BITS-1:0] upc_f;    // PC at fetch stage

// Time routines imported from C library.
`ifdef XILINX_SIMULATOR
typedef struct { longint sec, usec; } timeval_t;
`else
typedef struct { int sec, usec; } timeval_t;
`endif

import "DPI-C" function void gettimeofday(inout timeval_t tv, input chandle tz);

timeval_t t0;               // Start time of simulation

//
// Generate clock 500MHz.
//
always #1 clk = ~clk;

//
// Main loop.
//
initial begin
    $display("");
    $display("--------------------------------");

    // Dump waveforms.
    if ($test$plusargs("dump")) begin
        $dumpfile("output.vcd");
        $dumpvars();
    end

    // Enable detailed instruction trace to file.
    tracelevel = 2;
    $display("Generate trace file %0S", tracefile);
    tracefd = $fopen(tracefile, "w");

    // Limit the simulation by specified number of cycles.
    if (! $value$plusargs("limit=%d", limit)) begin
        // Default limit value.
        limit = 100000;
        $display("Limit: %0d", limit);
        $fdisplay(tracefd, "Limit: %0d", limit);
    end

    // Start with reset active
    clk = 1;
    reset = 1;
    irq = 0;

    // Hold reset for a while.
    #2 reset = 0;

    // Run until limit.
    gettimeofday(t0, null);
    #limit begin
        message("Time Limit Exceeded");
        $finish;
    end
end

//
// Print a message to stdout and trace file
//
task message(input string msg);
    $display("*** %s", msg);
    $fdisplay(tracefd, "(%0d) *** %s", ctime, msg);
endtask

// Get time at the rising edge of the clock.
always @(posedge clk) begin
    ctime = $time;
    upc_f = cpu.upc;
end

//
// Tracer
//
//
// Import standard C function gettimeofday().
//
longint instr_count;                    // Instruction and micro-instruction counters
longint uinstr_count;
bit old_reset = 0;                      // Previous state of reset

// At negative clock edge, when all the signals are quiet,
// print the state of the processor.
always @(negedge clk) begin
    if (tracefd) begin
        if (reset) begin
            if (!old_reset) begin               // Reset
                $fdisplay(tracefd, "(%0d) *** Reset", ctime);
                old_reset = 1;
            end
        end else begin
            if (old_reset) begin                // Clear reset
                $fdisplay(tracefd, "(%0d) *** Clear reset", ctime);
                old_reset = 0;
            end
        end

        if (tracelevel > 1) begin
            // Print last executed micro-instruction
            if (!reset)
                print_uop(upc_f, cpu.uop);

            // Print changed micro state
            //print_changed_cpu(opcode_x);
        end else begin
            // Print changed architectural state
            //print_changed_regs(opcode_x);
        end

`ifdef notdef
        // Print transactions on external bus
        print_ext_bus();

        // Print BESM instruction
        if (!reset)
            print_insn();

        if (int_flag_x)
            $fdisplay(tracefd, "(%0d) *** Interrupt #%0d", ctime, cpu.int_vect);
`endif

        // Get data from fetch stage
        //int_flag_x = cpu.int_flag;
        //tkk_x = cpu.tkk;
        //cb_x = cpu.cb;

        //->instruction_retired;
    end

`ifdef notdef
    if (!reset && $isunknown(cpu.opcode)) begin
        $display("(%0d) Unknown instruction: cpu.opcode=%h", ctime, cpu.opcode);
        if (tracefd)
            $fdisplay(tracefd, "(%0d) *** Unknown instruction: cpu.opcode=%h", ctime, cpu.opcode);
        terminate("Fatal Error!");
    end
`endif

    if ((cpu.dbus_read | cpu.dbus_write) && $isunknown(cpu.dbus_addr)) begin
        $display("(%0d) Unknown address: dbus_addr=%h", ctime, cpu.dbus_addr);
        if (tracefd)
            $fdisplay(tracefd, "(%0d) *** Unknown address: dbus_addr=%h", ctime, cpu.dbus_addr);
        terminate("Fatal Error!");
    end

    if (cpu.ibus_fetch && $isunknown(cpu.ibus_addr)) begin
        $display("(%0d) Unknown address: ibus_addr=%h", ctime, cpu.ibus_addr);
        if (tracefd)
            $fdisplay(tracefd, "(%0d) *** Unknown address: ibus_addr=%h", ctime, cpu.ibus_addr);
        terminate("Fatal Error!");
    end

    //TODO
    //if (!cpu.run) begin
    //    cpu_halted();
    //end
end

// ---- register operation dump ----
always @(negedge clk) begin
    if (~reset) begin
        uinstr_count++;

        if (cpu.w_rm) $fdisplay(tracefd, "--- set M[%0d]=0x%h", cpu.op_ir, cpu.alu.alu_r);
        if (cpu.w_acc) $fdisplay(tracefd, "--- set A=0x%h", cpu.alu.alu_r);
        if (cpu.w_acc_mem) $fdisplay(tracefd, "--- set A=0x%h (from MEM)", cpu.dbus_input);
        if (cpu.w_lsb) $fdisplay(tracefd, "--- set B=0x%h", cpu.alu.alu_r);
        if (cpu.w_opcode & ~cpu.is_op_cached) $fdisplay(tracefd, "--- set opcode_cache=0x%h, pc_cached=0x%h", cpu.alu.alu_r, {cpu.pc[31:2], 2'b0});

        if (~cpu.busy & cpu.upc == `UADDR_INTERRUPT) $fdisplay(tracefd, "--- ***** ENTERING INTERRUPT MICROCODE ******");
        if (~cpu.busy & cpu.exit_interrupt) $fdisplay(tracefd, "--- ***** INTERRUPT FLAG CLEARED *****");
        if (~cpu.busy & cpu.enter_interrupt) $fdisplay(tracefd, "--- ***** INTERRUPT FLAG SET *****");

// ---- microcode trace ----
        if (~cpu.busy) begin
            $fdisplay(tracefd, "--- uop[%d]=%o", cpu.upc, cpu.uop);
            if (cpu.branch)      $fdisplay(tracefd, "--- microcode: branch=%d", cpu.uop_addr);
            if (cpu.cond_branch) $fdisplay(tracefd, "--- microcode: CONDITION branch=%d", cpu.uop_addr);
            if (cpu.decode)      $fdisplay(tracefd, "--- decoding opcode=%o : branch to=%d ", cpu.opcode, cpu.opcode, cpu.op_entry);
        end else
            $fdisplay(tracefd, "--- busy");
    end
end

// ----- opcode dissasembler ------
always @(negedge clk) begin
    if (~cpu.busy)
        case (cpu.upc)
        0 : $fdisplay(tracefd, "--- ------  reset ------");
        4 : $fdisplay(tracefd, "--- ------  shiftleft ------");
        8 : $fdisplay(tracefd, "--- ------  pushsp ------");
        12 : $fdisplay(tracefd, "--- ------  popint ------");
        16 : $fdisplay(tracefd, "--- ------  poppc ------");
        20 : $fdisplay(tracefd, "--- ------  add ------");
        24 : $fdisplay(tracefd, "--- ------  and ------");
        28 : $fdisplay(tracefd, "--- ------  or ------");
        32 : $fdisplay(tracefd, "--- ------  load ------");
        36 : $fdisplay(tracefd, "--- ------  not ------");
        40 : $fdisplay(tracefd, "--- ------  flip ------");
        44 : $fdisplay(tracefd, "--- ------  nop ------");
        48 : $fdisplay(tracefd, "--- ------  store ------");
        52 : $fdisplay(tracefd, "--- ------  popsp ------");
        56 : $fdisplay(tracefd, "--- ------  ipsum ------");
        60 : $fdisplay(tracefd, "--- ------  sncpy ------");

        `UADDR_EMULATE   : $fdisplay(tracefd, "--- ------  emulate 0x%h ------", cpu.lsb[2:0]); // opcode[5:0] );

        128 : $fdisplay(tracefd, "--- ------  mcpy ------");
        132 : $fdisplay(tracefd, "--- ------  mset ------");
        136 : $fdisplay(tracefd, "--- ------  loadh ------");
        140 : $fdisplay(tracefd, "--- ------  storeh ------");
        144 : $fdisplay(tracefd, "--- ------  lessthan ------");
        148 : $fdisplay(tracefd, "--- ------  lessthanorequal ------");
        152 : $fdisplay(tracefd, "--- ------  ulessthan ------");
        156 : $fdisplay(tracefd, "--- ------  ulessthanorequal ------");
        160 : $fdisplay(tracefd, "--- ------  swap ------");
        164 : $fdisplay(tracefd, "--- ------  mult ------");
        168 : $fdisplay(tracefd, "--- ------  lshiftright ------");
        172 : $fdisplay(tracefd, "--- ------  ashiftleft ------");
        176 : $fdisplay(tracefd, "--- ------  ashiftright ------");
        180 : $fdisplay(tracefd, "--- ------  call ------");
        184 : $fdisplay(tracefd, "--- ------  eq ------");
        188 : $fdisplay(tracefd, "--- ------  neq ------");
        192 : $fdisplay(tracefd, "--- ------  neg ------");
        196 : $fdisplay(tracefd, "--- ------  sub ------");
        200 : $fdisplay(tracefd, "--- ------  xor ------");
        204 : $fdisplay(tracefd, "--- ------  loadb ------");
        208 : $fdisplay(tracefd, "--- ------  storeb ------");
        212 : $fdisplay(tracefd, "--- ------  div ------");
        216 : $fdisplay(tracefd, "--- ------  mod ------");
        220 : $fdisplay(tracefd, "--- ------  eqbranch ------");
        224 : $fdisplay(tracefd, "--- ------  neqbranch ------");
        228 : $fdisplay(tracefd, "--- ------  poppcrel ------");
        232 : $fdisplay(tracefd, "--- ------  config ------");
        236 : $fdisplay(tracefd, "--- ------  pushpc ------");
        240 : $fdisplay(tracefd, "--- ------  syscall_emulate ------");
        244 : $fdisplay(tracefd, "--- ------  pushspadd ------");
        248 : $fdisplay(tracefd, "--- ------  halfmult ------");
        252 : $fdisplay(tracefd, "--- ------  callpcrel ------");
        default : $fdisplay(tracefd, "--- upc=%0d", cpu.upc);
        endcase
end

//
// Print statistics and finish the simulation.
//
task terminate(input string message);
    timeval_t t1;
    longint usec;

    gettimeofday(t1, null);

    if (message != "")
        $display("\n----- %s -----", message);
    if (tracefd)
        $fdisplay(tracefd, "\n----- %s -----", message);

    usec = (t1.usec - t0.usec) + (t1.sec - t0.sec) * 1000000;
    $display("   Elapsed time: %0d seconds", usec / 1000000);
    $display("      Simulated: %0d instructions, %0d micro-instructions",
        instr_count, uinstr_count);
    if (usec > 0)
        $display("Simulation rate: %.1f instructions/sec, %.0f micro-instructions/sec",
            1000000.0 * instr_count / usec,
            1000000.0 * uinstr_count / usec);

    if (tracefd) begin
        $fdisplay(tracefd, "   Elapsed time: %0d seconds", usec / 1000000);
        $fdisplay(tracefd, "      Simulated: %0d instructions, %0d micro-instructions",
            instr_count, uinstr_count);
        if (usec > 0)
            $fdisplay(tracefd, "Simulation rate: %.1f instructions/sec, %.0f micro-instructions/sec",
                1000000.0 * instr_count / usec,
                1000000.0 * uinstr_count / usec);
    end

    $finish;
endtask

//
// Print micro-instruction.
//
task print_uop(
    input logic [`UPC_BITS-1:0] upc,    // microcode PC
    input logic [`UOP_BITS-1:0] uop     // microcode operation
);
    static string alu_name[4] = '{
        0: "A",    1: "OPCODE",    2: "CONST",   3: "B"
    };
    static string addr_name[4] = '{
        0: "PC",    1: "SP",    2: "A",   3: "B"
    };
    static string op_name[16] = '{
        0: "A",    1: "B",     2: "A+B",  3: "A+Boff",
        4: "A&B",  5: "A|B",   6: "~A",   7: "?7",
        8: "?8",   9: "?9",    10:"?10",  11:"?11",
        12:"?12",  13:"?13",   14:"?14",  15:"?15"
    };

    logic       sel_read;
    logic [1:0] sel_alu;
    logic [1:0] sel_addr;
    logic [3:0] alu_op;
    logic       w_sp;
    logic       w_rm;
    logic       w_acc;
    logic       w_acc_mem;
    logic       w_lsb;
    logic       w_opcode;
    logic       mem_read;
    logic       mem_write;
    logic       mem_fetch;
    logic       w_pc_increment;
    logic       exit_interrupt;
    logic       enter_interrupt;
    logic       cond_op_not_cached;
    logic       cond_a_zero;
    logic       cond_a_neg;
    logic       decode;
    logic       branch;
    logic [`UPC_BITS-1:0] goto;

    assign sel_read           = uop[`P_SEL_READ];
    assign sel_alu            = uop[`P_SEL_ALU+1:`P_SEL_ALU];
    assign sel_addr           = uop[`P_SEL_ADDR+1:`P_SEL_ADDR];
    assign alu_op             = uop[`P_ALU+3:`P_ALU];
    assign w_rm               = uop[`P_W_RM];
    assign w_acc              = uop[`P_W_A];
    assign w_acc_mem          = uop[`P_W_A_MEM];
    //assign w_lsb              = uop[`P_W_B];
    assign w_opcode           = uop[`P_W_OPCODE];
    assign mem_read           = uop[`P_MEM_R];
    assign mem_write          = uop[`P_MEM_W];
    assign mem_fetch          = uop[`P_FETCH];
    assign exit_interrupt     = uop[`P_EXIT_INT];
    assign enter_interrupt    = uop[`P_ENTER_INT];
    assign cond_op_not_cached = uop[`P_OP_NOT_CACHED];
    assign cond_a_zero        = uop[`P_A_ZERO];
    assign cond_a_neg         = uop[`P_A_NEG];
    assign decode             = uop[`P_DECODE];
    assign branch             = uop[`P_BRANCH];
    assign goto               = uop[`P_ADDR+`UPC_BITS-1:`P_ADDR];

    $fwrite(tracefd, "(%0d) %0d:", ctime, upc);

    if (sel_read != 0) $fwrite(tracefd, " sel_read");
    if (sel_alu  != 0) $fwrite(tracefd, " sel_alu=%0s", alu_name[sel_alu]);
    if (sel_addr != 0) $fwrite(tracefd, " sel_addr=%0s", addr_name[sel_addr]);
    if (alu_op   != 0) $fwrite(tracefd, " alu_op=%0s", op_name[alu_op]);

    if (w_rm               != 0) $fwrite(tracefd, " w_rm");
    if (w_acc              != 0) $fwrite(tracefd, " w_acc");
    if (w_acc_mem          != 0) $fwrite(tracefd, " w_acc_mem");
    //if (w_lsb              != 0) $fwrite(tracefd, " w_lsb");
    if (w_opcode           != 0) $fwrite(tracefd, " w_opcode");
    if (mem_read           != 0) $fwrite(tracefd, " mem_r");
    if (mem_write          != 0) $fwrite(tracefd, " mem_w");
    if (mem_fetch          != 0) $fwrite(tracefd, " mem_fetch");
    if (w_pc_increment     != 0) $fwrite(tracefd, " w_pc_increment");
    if (exit_interrupt     != 0) $fwrite(tracefd, " exit_interrupt");
    if (enter_interrupt    != 0) $fwrite(tracefd, " enter_interrupt");
    if (cond_op_not_cached != 0) $fwrite(tracefd, " cond_op_not_cached");
    if (cond_a_zero        != 0) $fwrite(tracefd, " cond_a_zero");
    if (cond_a_neg         != 0) $fwrite(tracefd, " cond_a_neg");
    if (decode             != 0) $fwrite(tracefd, " decode");
    if (branch             != 0) $fwrite(tracefd, " branch");

    if (goto  != 0)    $fwrite(tracefd, " goto=%0d", goto);
    $fdisplay(tracefd, "");
endtask

endmodule
