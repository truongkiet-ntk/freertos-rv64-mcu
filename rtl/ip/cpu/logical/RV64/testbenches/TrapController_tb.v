`timescale 1ns/1ps
`include "modules/headers/trap.vh"

module TrapController_tb;

  // ============================================================
  // Signal Declaration
  // ============================================================
  reg         clk;
  reg         clk_enable;
  reg         reset;

  reg         jump;
  reg         EX_jump;
  reg         jumpped_latch;
  reg         branch_taken;
  reg  [31:0] pc;
  reg  [31:0] IF_pc;
  reg  [31:0] IO_pc;
  reg  [31:0] ID_pc;
  reg  [31:0] EXR_pc;
  reg  [31:0] EX_pc;
  reg  [31:0] EX2_pc;
  reg  [31:0] MEM_pc;
  reg  [31:0] WB_pc;
  reg         interrupt_pipeline_drained;
  reg         interrupt_resume_candidate_valid;
  reg  [31:0] interrupt_resume_candidate_pc;

  reg  [3:0]  trap_status;
  reg  [31:0] csr_read_data;

  wire [31:0] trap_target;
  wire        ic_clean;
  wire        debug_mode;
  wire        trap_done;
  wire        csr_write_enable;
  wire        trap_csr_access;
  wire [11:0] csr_trap_address;
  wire [31:0] csr_trap_write_data;
  wire        misaligned_instruction_flush;
  wire        misaligned_memory_flush;
  wire        pth_done_flush;
  wire        standby_mode;
  wire        mret_executed;
  wire        pth_read;
  wire        goto_mtvec;
  wire        mret_done;

  integer errors;

  // ============================================================
  // DUT Instance
  // ============================================================
  TrapController #(
    .XLEN(32)
  ) trap_controller (
    .clk                          (clk),
    .clk_enable                   (clk_enable),
    .reset                        (reset),

    .jump                         (jump),
    .EX_jump                      (EX_jump),
    .jumpped_latch                (jumpped_latch),
    .pc                           (pc),
    .IF_pc                        (IF_pc),
    .IO_pc                        (IO_pc),
    .ID_pc                        (ID_pc),
    .EXR_pc                       (EXR_pc),
    .EX_pc                        (EX_pc),
    .EX2_pc                       (EX2_pc),
    .MEM_pc                       (MEM_pc),
    .WB_pc                        (WB_pc),
    .interrupt_pipeline_drained   (interrupt_pipeline_drained),
    .interrupt_resume_candidate_valid (interrupt_resume_candidate_valid),
    .interrupt_resume_candidate_pc (interrupt_resume_candidate_pc),

    .branch_taken                 (branch_taken),
    .trap_status                  (trap_status),
    .csr_read_data                (csr_read_data),

    .trap_target                  (trap_target),
    .ic_clean                     (ic_clean),
    .debug_mode                   (debug_mode),
    .csr_write_enable             (csr_write_enable),
    .trap_csr_access              (trap_csr_access),
    .csr_trap_address             (csr_trap_address),
    .csr_trap_write_data          (csr_trap_write_data),
    .trap_done                    (trap_done),
    .misaligned_instruction_flush (misaligned_instruction_flush),
    .misaligned_memory_flush      (misaligned_memory_flush),
    .pth_done_flush               (pth_done_flush),
    .standby_mode                 (standby_mode),
    .mret_executed                (mret_executed),
    .pth_read                     (pth_read),
    .goto_mtvec                   (goto_mtvec),
    .mret_done                    (mret_done)
  );

  // ============================================================
  // Clock (period = 10ns)
  // ============================================================
  initial clk = 0;
  always #5 clk = ~clk;

  // ============================================================
  // VCD Dump
  // ============================================================
  initial begin
    $dumpfile("./testbenches/results/waveforms/Trap_Controller_tb_pth_direct_result.vcd");
    $dumpvars(0, TrapController_tb);
  end

  // ============================================================
  // Monitor
  // ============================================================
  initial begin
    $display("time | state | trap_status | trap_target | done | standby | csr_access | csr_we | csr_addr | csr_wdata");
    $monitor("%4t |  %b  |    %h      | %h |  %b   |   %b    |     %b      |   %b    |   %h    | %h",
             $time,
             trap_controller.trap_handle_state,
             trap_status,
             trap_target,
             trap_done,
             standby_mode,
             trap_csr_access,
             csr_write_enable,
             csr_trap_address,
             csr_trap_write_data);
  end

  // ============================================================
  // Utility Tasks
  // ============================================================
  task tick;
    input integer n;
    integer i;
    begin
      for (i = 0; i < n; i = i + 1) begin
        @(posedge clk);
        #1;
      end
    end
  endtask

  task settle;
    begin
      #1;
    end
  endtask

  task set_pc;
    input [31:0] id, ex, ex2, mem, wb;
    begin
      ID_pc  = id;
      EXR_pc = ex;
      EX_pc  = ex;
      EX2_pc = ex2;
      MEM_pc = mem;
      WB_pc  = wb;
      interrupt_resume_candidate_pc = wb;
      pc = id;
      IF_pc = id;
      IO_pc = id;
    end
  endtask

  task clear_trap;
    begin
      trap_status = `TRAP_NONE;
      settle();
    end
  endtask

  task expect1;
    input [1023:0] name;
    input actual;
    input expected;
    begin
      if (actual !== expected) begin
        $display("[FAIL] %0s: expected=%b actual=%b @%0t", name, expected, actual, $time);
        errors = errors + 1;
      end else begin
        $display("[PASS] %0s = %b", name, actual);
      end
    end
  endtask

  task expect4;
    input [1023:0] name;
    input [3:0] actual;
    input [3:0] expected;
    begin
      if (actual !== expected) begin
        $display("[FAIL] %0s: expected=%h actual=%h @%0t", name, expected, actual, $time);
        errors = errors + 1;
      end else begin
        $display("[PASS] %0s = %h", name, actual);
      end
    end
  endtask

  task expect12;
    input [1023:0] name;
    input [11:0] actual;
    input [11:0] expected;
    begin
      if (actual !== expected) begin
        $display("[FAIL] %0s: expected=%h actual=%h @%0t", name, expected, actual, $time);
        errors = errors + 1;
      end else begin
        $display("[PASS] %0s = %h", name, actual);
      end
    end
  endtask

  task expect32;
    input [1023:0] name;
    input [31:0] actual;
    input [31:0] expected;
    begin
      if (actual !== expected) begin
        $display("[FAIL] %0s: expected=%h actual=%h @%0t", name, expected, actual, $time);
        errors = errors + 1;
      end else begin
        $display("[PASS] %0s = %h", name, actual);
      end
    end
  endtask

  // ============================================================
  // Testbench
  // ============================================================
  initial begin
    $display("==================== TrapController Test START ====================");
    errors = 0;

    // Initialize the controller and pipeline PC inputs.
    clk_enable    = 1'b1;
    reset         = 1'b1;
    trap_status   = `TRAP_NONE;
    csr_read_data = 32'h0000_0000;
    jump = 1'b0;
    EX_jump = 1'b0;
    jumpped_latch = 1'b0;
    branch_taken = 1'b0;
    interrupt_pipeline_drained = 1'b1;
    interrupt_resume_candidate_valid = 1'b1;
    interrupt_resume_candidate_pc = 32'b0;
    pc = 32'h0;
    IF_pc = 32'h0;
    IO_pc = 32'h0;
    set_pc(0, 0, 0, 0, 0);

    tick(2);
    reset = 1'b0;
    tick(1);

    // ============================================================
    // TEST 1: No trap remains idle.
    // ============================================================
    $display("\n--- TEST 1: TRAP_NONE IDLE ---");
    clear_trap();
    expect1 ("TRAP_NONE trap_done",        trap_done,        1'b1);
    expect32("TRAP_NONE trap_target",      trap_target,      32'h0000_0000);
    tick(3);
    expect1 ("TRAP_NONE remains complete", trap_done, 1'b1);

    // ============================================================
    // TEST 2: FENCE.I completes without entering the trap FSM.
    // ============================================================
    $display("\n--- TEST 2: FENCE.I immediate clean ---");
    trap_status = `TRAP_FENCEI;
    settle();
    expect1("FENCEI ic_clean",  ic_clean,  1'b1);
    expect1("FENCEI trap_done", trap_done, 1'b1);
    tick(1);
    clear_trap();
    tick(1);

    // ============================================================
    // TEST 3: External interrupt saves the return PC and machine cause.
    // ============================================================
    $display("\n--- TEST 3: External interrupt trap entry ---");
    set_pc(32'h0000_2030, 32'h0000_2020, 32'h0000_2010, 32'h0000_2000, 32'h0000_1FF0);
    trap_status = `EXTERNAL_INTERRUPT_IRQ;
    settle();
    expect1("External IRQ drains pipeline in standby", standby_mode, 1'b1);
    expect1("External IRQ blocks normal progress", trap_done, 1'b0);
    tick(4);
    trap_status = `TRAP_NONE;
    expect1 ("External IRQ asserts CSR write", csr_write_enable, 1'b1);
    expect12("External IRQ writes mepc", csr_trap_address, 12'h341);
    expect32("External IRQ saves latched resume PC", csr_trap_write_data, 32'h0000_1FF0);

    tick(1);
    expect1 ("External IRQ asserts mcause write", csr_write_enable, 1'b1);
    expect12("External IRQ writes mcause", csr_trap_address, 12'h342);
    expect32("External IRQ mcause is interrupt 11", csr_trap_write_data, 32'h8000_000B);

    csr_read_data = 32'h0000_7000;
    tick(1);
    expect1("External IRQ requests mtvec", trap_csr_access, 1'b1);
    expect12("External IRQ reads mtvec CSR", csr_trap_address, 12'h305);
    tick(1);
    expect1("External IRQ redirects to mtvec", goto_mtvec, 1'b1);
    expect32("External IRQ target is mtvec", trap_target, 32'h0000_7000);
    tick(2);
    expect1("External IRQ FSM returns to IDLE", trap_done, 1'b1);

    // ============================================================
    // TEST 4: Timer interrupt retains its distinct machine cause.
    // ============================================================
    $display("\n--- TEST 4: Timer interrupt trap entry ---");
    set_pc(32'h0000_5130, 32'h0000_5100, 32'h0000_50F0, 32'h0000_50E0, 32'h0000_50D0);
    trap_status = `TIMER_INTERRUPT_IRQ;
    settle();
    tick(4);
    trap_status = `TRAP_NONE;
    expect12("Timer IRQ writes mepc", csr_trap_address, 12'h341);
    tick(1);
    expect12("Timer IRQ writes mcause", csr_trap_address, 12'h342);
    expect32("Timer IRQ mcause is interrupt 7", csr_trap_write_data, 32'h8000_0007);
    tick(4);

    // ============================================================
    // TEST 5: MRET reads mepc and returns through the current FSM.
    // ============================================================
    $display("\n--- TEST 5: MRET ---");
    csr_read_data = 32'h0000_1100;
    trap_status = `TRAP_MRET;
    settle();
    expect12("MRET reads mepc", csr_trap_address, 12'h341);
    tick(1);
    trap_status = `TRAP_NONE;
    expect1("MRET requests CSR read", pth_read, 1'b1);
    expect32("MRET target is mepc", trap_target, 32'h0000_1100);
    tick(4);
    expect1("MRET signals CSR restore", mret_executed, 1'b1);
    expect1("MRET completes", mret_done, 1'b1);
    tick(1);

    // ============================================================
    // TEST 6: drain waits for valid stages and preserves a valid PC of zero.
    // ============================================================
    $display("\n--- TEST 6: clk_enable stall during external IRQ ---");
    set_pc(32'h0000_6030, 32'h0000_6020, 32'h0000_6010, 32'h0000_6000, 32'h0000_5FF0);
    interrupt_resume_candidate_pc = 32'b0;
    trap_status = `EXTERNAL_INTERRUPT_IRQ;
    settle();
    interrupt_pipeline_drained = 1'b0;
    tick(3); // IDLE -> MEM_STANDBY -> WB_STANDBY -> RTRE_STANDBY
    expect4("IRQ waits in RTRE_STANDBY for valid stages", trap_controller.trap_handle_state, 4'b1001);
    expect1("IRQ does not write mepc before drain", csr_write_enable, 1'b0);
    trap_status = `TRAP_NONE;
    clk_enable = 1'b0;
    tick(3);
    expect4("state held while clk_enable=0", trap_controller.trap_handle_state, 4'b1001);
    clk_enable = 1'b1;
    interrupt_pipeline_drained = 1'b1;
    tick(1);
    expect4("IRQ enters mepc write after drain", trap_controller.trap_handle_state, 4'b1110);
    expect12("IRQ writes mepc after drain", csr_trap_address, 12'h341);
    expect32("Valid resume PC zero is not treated as empty", csr_trap_write_data, 32'b0);
    tick(1);
    expect12("IRQ resumes and writes mcause", csr_trap_address, 12'h342);
    expect32("IRQ resumed mcause is interrupt 11", csr_trap_write_data, 32'h8000_000B);
    tick(4);

    // ============================================================
    // Summary
    // ============================================================
    if (errors == 0) begin
      $display("\n==================== ALL TESTS PASSED ====================");
    end else begin
      $display("\n==================== TESTS FAILED: %0d error(s) ====================", errors);
    end

    if (errors != 0)
      $fatal(1, "TrapController test failed");
    $finish;
  end

endmodule