`timescale 1ns/1ps
`include "modules/headers/trap.vh"

module External_Interrupt_tb;
    reg clk;
    reg reset;

    reg external_interrupt_pending;
    reg timer_interrupt_pending;
    reg trapped;
    reg trapped_latch;
    reg mret_executed;
    reg csr_write_enable;
    reg [11:0] csr_read_address;
    reg [11:0] csr_write_address;
    reg [63:0] csr_write_data;
    reg instruction_retired;
    reg [3:0] csr_trap_status;
    reg pth_read;
    wire [63:0] csr_read_out;
    wire csr_ready;
    wire mstatus_mie;
    wire mie_mtie;
    wire mie_meie;

    reg [3:0] trap_status;
    reg [63:0] csr_read_data;
    reg jump;
    reg ex_jump;
    reg jumpped_latch;
    reg branch_taken;
    reg [63:0] pc;
    reg [63:0] if_pc;
    reg [63:0] io_pc;
    reg [63:0] id_pc;
    reg [63:0] exr_pc;
    reg [63:0] ex_pc;
    reg [63:0] ex2_pc;
    reg [63:0] mem_pc;
    reg [63:0] wb_pc;
    reg interrupt_pipeline_drained;
    reg interrupt_resume_candidate_valid;
    reg [63:0] interrupt_resume_candidate_pc;
    wire [63:0] trap_target;
    wire trap_csr_write_enable;
    wire [11:0] trap_csr_address;
    wire [63:0] trap_csr_write_data;
    wire trap_done;
    wire standby_mode;
    wire goto_mtvec;
    wire pth_read_out;
    wire mret_done;
    wire mret_executed_out;
    wire ic_clean;
    wire debug_mode;
    wire trap_csr_access;
    wire misaligned_instruction_flush;
    wire misaligned_memory_flush;
    wire pth_done_flush;

    integer errors;

    CSRFile #(.XLEN(64)) csr_file (
        .clk(clk),
        .clk_enable(1'b1),
        .reset(reset),
        .trapped(trapped),
        .trapped_latch(trapped_latch),
        .mret_executed(mret_executed),
        .csr_write_enable(csr_write_enable),
        .csr_read_address(csr_read_address),
        .csr_write_address(csr_write_address),
        .csr_write_data(csr_write_data),
        .instruction_retired(instruction_retired),
        .valid_csr_address(1'b1),
        .timer_interrupt_pending(timer_interrupt_pending),
        .external_interrupt_pending(external_interrupt_pending),
        .pth_read(pth_read),
        .trap_status(csr_trap_status),
        .csr_read_out(csr_read_out),
        .csr_ready(csr_ready),
        .mstatus_mie(mstatus_mie),
        .mie_mtie(mie_mtie),
        .mie_meie(mie_meie)
    );

    TrapController #(.XLEN(64)) trap_controller (
        .clk(clk),
        .clk_enable(1'b1),
        .reset(reset),
        .jump(jump),
        .EX_jump(ex_jump),
        .jumpped_latch(jumpped_latch),
        .pc(pc),
        .IF_pc(if_pc),
        .IO_pc(io_pc),
        .ID_pc(id_pc),
        .EXR_pc(exr_pc),
        .EX_pc(ex_pc),
        .EX2_pc(ex2_pc),
        .MEM_pc(mem_pc),
        .WB_pc(wb_pc),
        .interrupt_pipeline_drained(interrupt_pipeline_drained),
        .interrupt_resume_candidate_valid(interrupt_resume_candidate_valid),
        .interrupt_resume_candidate_pc(interrupt_resume_candidate_pc),
        .branch_taken(branch_taken),
        .trap_status(trap_status),
        .csr_read_data(csr_read_data),
        .trap_target(trap_target),
        .ic_clean(ic_clean),
        .debug_mode(debug_mode),
        .csr_write_enable(trap_csr_write_enable),
        .trap_csr_access(trap_csr_access),
        .csr_trap_address(trap_csr_address),
        .csr_trap_write_data(trap_csr_write_data),
        .trap_done(trap_done),
        .misaligned_instruction_flush(misaligned_instruction_flush),
        .misaligned_memory_flush(misaligned_memory_flush),
        .pth_done_flush(pth_done_flush),
        .standby_mode(standby_mode),
        .mret_executed(mret_executed_out),
        .pth_read(pth_read_out),
        .goto_mtvec(goto_mtvec),
        .mret_done(mret_done)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("./testbenches/results/waveforms/External_Interrupt_tb.vcd");
        $dumpvars(0, External_Interrupt_tb);
    end

    task check64;
        input [255:0] name;
        input [63:0] actual;
        input [63:0] expected;
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0s expected=%h actual=%h", name, expected, actual);
                errors = errors + 1;
            end else begin
                $display("[PASS] %0s = %h", name, actual);
            end
        end
    endtask

    task write_csr;
        input [11:0] address;
        input [63:0] value;
        begin
            @(negedge clk);
            csr_write_address = address;
            csr_write_data = value;
            csr_write_enable = 1'b1;
            @(posedge clk); #1;
            csr_write_enable = 1'b0;
            @(posedge clk); #1;
        end
    endtask

    task read_csr;
        input [11:0] address;
        begin
            @(negedge clk);
            csr_read_address = address;
            @(posedge clk); #1;
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        errors = 0;
        external_interrupt_pending = 1'b0;
        timer_interrupt_pending = 1'b0;
        trapped = 1'b0;
        trapped_latch = 1'b0;
        mret_executed = 1'b0;
        csr_write_enable = 1'b0;
        csr_read_address = 12'h000;
        csr_write_address = 12'h000;
        csr_write_data = 64'b0;
        instruction_retired = 1'b0;
        csr_trap_status = `TRAP_NONE;
        pth_read = 1'b0;
        trap_status = `TRAP_NONE;
        csr_read_data = 64'h0000_0000_0000_7000;
        jump = 1'b0;
        ex_jump = 1'b0;
        jumpped_latch = 1'b0;
        branch_taken = 1'b0;
        pc = 64'h0000_0000_0000_1000;
        if_pc = 64'h0000_0000_0000_1004;
        io_pc = 64'h0000_0000_0000_1008;
        id_pc = 64'h0000_0000_0000_100C;
        exr_pc = 64'h0000_0000_0000_1010;
        ex_pc = 64'h0000_0000_0000_1014;
        ex2_pc = 64'h0000_0000_0000_1018;
        mem_pc = 64'h0000_0000_0000_101C;
        wb_pc = 64'h0000_0000_0000_1020;
        interrupt_pipeline_drained = 1'b1;
        interrupt_resume_candidate_valid = 1'b1;
        interrupt_resume_candidate_pc = 64'h0000_0000_0000_1020;

        repeat (2) @(posedge clk);
        #1 reset = 1'b0;

        $display("\n=== External interrupt CSR pending test ===");
        external_interrupt_pending = 1'b1;
        read_csr(12'h344);
        check64("mip.MEIP", csr_read_out, 64'h0000_0000_0000_0800);

        write_csr(12'h304, 64'h0000_0000_0000_0880);
        check64("mie.MEIE enable", {63'b0, mie_meie}, 64'd1);
        check64("mie.MTIE remains enabled", {63'b0, mie_mtie}, 64'd1);
        write_csr(12'h300, 64'h0000_0000_0000_0008);
        check64("mstatus.MIE enable", {63'b0, mstatus_mie}, 64'd1);

        $display("\n=== External interrupt trap-controller test ===");
        trap_status = `EXTERNAL_INTERRUPT_IRQ;
        #1;
        if (standby_mode !== 1'b1 || trap_done !== 1'b0) begin
            $display("[FAIL] External interrupt must start IRQ handling");
            errors = errors + 1;
        end else begin
            $display("[PASS] External interrupt accepted by trap controller");
        end

        repeat (4) @(posedge clk);
        #1;
        trap_status = `TRAP_NONE;
        check64("mepc write address", {52'b0, trap_csr_address}, 64'h341);
        check64("mepc saved drained resume PC", trap_csr_write_data,
                interrupt_resume_candidate_pc);
        if (trap_csr_write_enable !== 1'b1) begin
            $display("[FAIL] mepc write enable not asserted");
            errors = errors + 1;
        end

        @(posedge clk); #1;
        check64("mcause write address", {52'b0, trap_csr_address}, 64'h342);
        check64("mcause external interrupt code", trap_csr_write_data,
                64'h8000_0000_0000_000B);

        if (errors == 0)
            $display("\nALL EXTERNAL INTERRUPT CHECKS PASSED");
        else
            $display("\nEXTERNAL INTERRUPT CHECKS FAILED: %0d", errors);

        if (errors != 0)
            $fatal(1, "External interrupt regression failed");
        $finish;
    end
endmodule
