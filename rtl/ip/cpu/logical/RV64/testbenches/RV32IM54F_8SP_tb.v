`timescale 1ns/1ps

module RV64IM72F8SP_Core_tb #(
    parameter XLEN = 64
);
    reg clk;
    reg reset;
    reg external_interrupt_pending;
    reg resume_latched_after_drain;

    wire [31:0] retire_instruction;
    wire [XLEN-1:0] mmio_data_memory_address;
    wire [XLEN-1:0] mmio_data_memory_write_data;
    wire mmio_data_memory_write_enable;

    // ------------------------------------------------------------------------
    // Core-only MMIO / CLINT model
    // This model is aligned with the real clint.v behavior:
    //   - CLINT range: 0x0200_0000 ~ 0x0200_000F
    //   - mtime increments at 1 kHz from a 100 MHz CPU clock
    //   - mtime write has priority over tick increment
    //   - mtimecmp is 64-bit, split into LO/HI 32-bit registers
    // ------------------------------------------------------------------------
    reg [XLEN-1:0] mmio_read_data;

    localparam integer CLK_FREQ  = 100_000_000;
    localparam integer TICK_FREQ = 1_000;
    localparam integer DIVIDER   = CLK_FREQ / TICK_FREQ;

    localparam [31:0] MTIME_LO     = 32'h0200_0000;
    localparam [31:0] MTIME_HI     = 32'h0200_0004;
    localparam [31:0] MTIMECMP_LO  = 32'h0200_0008;
    localparam [31:0] MTIMECMP_HI  = 32'h0200_000C;

    reg [$clog2(DIVIDER)-1:0] div_cnt;
    reg                       tick;

    reg [63:0] mtime;
    reg [63:0] mtimecmp;

    wire timer_interrupt_pending;

    assign timer_interrupt_pending = (mtime >= mtimecmp) ? 1'b1 : 1'b0;

    // In this core-only TB, the CPU's MMIO address is used as both
    // the CLINT read address and write address.
    wire [31:0] clint_address;
    assign clint_address = mmio_data_memory_address[31:0];

    wire clint_selected;
    wire clint_write_enable;

    assign clint_selected =
        (clint_address == MTIME_LO)    ||
        (clint_address == MTIME_HI)    ||
        (clint_address == MTIMECMP_LO) ||
        (clint_address == MTIMECMP_HI);

    // Important:
    // Do not pass every MMIO write to CLINT.  In the real SoC, the MMIO decoder
    // selects CLINT only for CLINT addresses.  If every UART/VRAM/KB write were
    // treated as clint_write_enable, mtime's tick increment could be suppressed
    // because the real clint.v gives write_enable priority over tick.
    assign clint_write_enable =
        mmio_data_memory_write_enable && clint_selected;

    RV64IM72F8SP #(
        .XLEN(XLEN)
    ) rv64im72f8sp (
        .clk(clk),
        .clk_enable(1'b1),
        .reset(reset),
        .UART_busy(1'b0),
        .timer_interrupt_pending(timer_interrupt_pending),
        .external_interrupt_pending(external_interrupt_pending),
        .MMIO_read_data(mmio_read_data),

        .retire_instruction(retire_instruction),
        .MMIO_data_memory_address(mmio_data_memory_address),
        .MMIO_data_memory_write_data(mmio_data_memory_write_data),
        .MMIO_data_memory_write_enable(mmio_data_memory_write_enable)
    );

    // Generate clock signal: 100 MHz, period = 10 ns
    always #5 clk = ~clk;

    // ------------------------------------------------------------------------
    // 1. Clock divider: 100 MHz -> 1 kHz tick
    // Same behavior as clint.v
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            div_cnt <= 0;
            tick    <= 1'b0;
        end
        else if (div_cnt == DIVIDER - 1) begin
            div_cnt <= 0;
            tick    <= 1'b1;
        end
        else begin
            div_cnt <= div_cnt + 1;
            tick    <= 1'b0;
        end
    end

    // ------------------------------------------------------------------------
    // 2. MTIME
    // Same behavior as clint.v:
    //   reset -> 0
    //   write_enable has priority over tick increment
    //   tick -> mtime + 1
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            mtime <= 64'b0;
        end
        else if (clint_write_enable) begin
            case (clint_address)
                MTIME_LO: mtime[31:0]  <= mmio_data_memory_write_data[31:0];
                MTIME_HI: mtime[63:32] <= mmio_data_memory_write_data[31:0];
                default: ;
            endcase
        end
        else if (tick) begin
            mtime <= mtime + 64'd1;
        end
    end

    // ------------------------------------------------------------------------
    // 3. MTIMECMP
    // Same behavior as clint.v:
    //   reset -> all 1s
    //   writable split low/high
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            mtimecmp <= 64'hFFFF_FFFF_FFFF_FFFF;
        end
        else if (clint_write_enable) begin
            case (clint_address)
                MTIMECMP_LO: mtimecmp[31:0]  <= mmio_data_memory_write_data[31:0];
                MTIMECMP_HI: mtimecmp[63:32] <= mmio_data_memory_write_data[31:0];
                default: ;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // 4. MMIO read mux
    // CPU lw from CLINT address sees the corresponding split 32-bit value.
    // Other MMIO reads return zero in this core-only TB.
    // ------------------------------------------------------------------------
    always @(*) begin
        case (clint_address)
            MTIME_LO:     mmio_read_data = mtime[31:0];
            MTIME_HI:     mmio_read_data = mtime[63:32];
            MTIMECMP_LO:  mmio_read_data = mtimecmp[31:0];
            MTIMECMP_HI:  mmio_read_data = mtimecmp[63:32];
            default:      mmio_read_data = {XLEN{1'b0}};
        endcase
    end

    // ------------------------------------------------------------------------
    // Optional debug prints
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!reset && tick) begin
            $display("[%0t ns] CLINT tick: mtime=%0d mtimecmp=%0d irq=%b",
                     $time, mtime + 64'd1, mtimecmp, timer_interrupt_pending);
        end

        if (!reset && clint_write_enable) begin
            case (clint_address)
                MTIME_LO:
                    $display("[%0t ns] CLINT write MTIME_LO    <= 0x%08h",
                             $time, mmio_data_memory_write_data[31:0]);
                MTIME_HI:
                    $display("[%0t ns] CLINT write MTIME_HI    <= 0x%08h",
                             $time, mmio_data_memory_write_data[31:0]);
                MTIMECMP_LO:
                    $display("[%0t ns] CLINT write MTIMECMP_LO <= 0x%08h",
                             $time, mmio_data_memory_write_data[31:0]);
                MTIMECMP_HI:
                    $display("[%0t ns] CLINT write MTIMECMP_HI <= 0x%08h",
                             $time, mmio_data_memory_write_data[31:0]);
                default: ;
            endcase
        end
    end

    initial begin
        $dumpfile("testbenches/results/waveforms/RV64IM72F8SP_Core_tb.vcd");
        $dumpvars(0, RV64IM72F8SP_Core_tb);

        $display("==================== RV64IM72F8SP Core External IRQ Test START ====================");

        clk = 0;
        reset = 1;
        external_interrupt_pending = 0;
        resume_latched_after_drain = 0;

        // Replace the firmware with a controlled test program while reset is active.
        // It sets mtvec=0x40, enables interrupts, then jumps into a loop.
        #1;
        for (integer instruction_index = 0; instruction_index < 8192; instruction_index = instruction_index + 1)
            rv64im72f8sp.instruction_memory.data[instruction_index] = 32'h00000013;
        rv64im72f8sp.instruction_memory.data[0] = 32'h04000193; // addi x3, x0, 64
        rv64im72f8sp.instruction_memory.data[1] = 32'h30519073; // csrw mtvec, x3
        rv64im72f8sp.instruction_memory.data[2] = 32'h000010b7; // lui x1, 1
        rv64im72f8sp.instruction_memory.data[3] = 32'h0010d093; // srli x1, x1, 1 (MEIE)
        rv64im72f8sp.instruction_memory.data[4] = 32'h30409073; // csrw mie, x1
        rv64im72f8sp.instruction_memory.data[5] = 32'h00800113; // addi x2, x0, 8 (MIE)
        rv64im72f8sp.instruction_memory.data[6] = 32'h30011073; // csrw mstatus, x2
        rv64im72f8sp.instruction_memory.data[7] = 32'h0080006f; // jal x0, 8
        rv64im72f8sp.instruction_memory.data[9] = 32'h0000006f; // target: jal x0, 0
        rv64im72f8sp.instruction_memory.data[16] = 32'h00100213; // handler: addi x4, x0, 1
        rv64im72f8sp.instruction_memory.data[17] = 32'h0000006f; // handler loop

        #49;
        reset = 0;

        // Wait for the program to enable both per-source and global interrupts.
        begin : wait_for_irq_enable
            integer cycles;
            cycles = 0;
            while (!(rv64im72f8sp.csr_file.mie[11] &&
                     rv64im72f8sp.csr_file.mstatus_mie) && cycles < 300) begin
                @(posedge clk);
                #1;
                cycles = cycles + 1;
            end
            if (!(rv64im72f8sp.csr_file.mie[11] &&
                  rv64im72f8sp.csr_file.mstatus_mie))
                $fatal(1, "Timed out waiting for core to enable MEIE and MIE");
        end

        if (rv64im72f8sp.csr_file.mtvec !== 64'h40)
            $fatal(1, "Core programmed mtvec incorrectly: %h", rv64im72f8sp.csr_file.mtvec);

        $display("[PASS] Core enabled MEIE/MIE and programmed mtvec");
        external_interrupt_pending = 1'b1;

        begin : wait_for_external_trap
            integer cycles;
            cycles = 0;
            while (rv64im72f8sp.csr_file.mcause !== 64'h8000_0000_0000_000B &&
                   cycles < 300) begin
                @(posedge clk);
                #1;
                if (rv64im72f8sp.trap_controller.interrupt_resume_valid)
                    resume_latched_after_drain = 1'b1;
                cycles = cycles + 1;
            end
            if (rv64im72f8sp.csr_file.mcause !== 64'h8000_0000_0000_000B)
                $fatal(1, "Timed out waiting for external interrupt mcause; got %h",
                       rv64im72f8sp.csr_file.mcause);
        end

        if (rv64im72f8sp.csr_file.mip[11] !== 1'b1)
            $fatal(1, "External interrupt pending was not reflected in mip.MEIP");
        if (!rv64im72f8sp.trap_controller.interrupt_resume_valid)
            $fatal(1, "Interrupt resume PC was not latched after pipeline drain");
        if (!resume_latched_after_drain)
            $fatal(1, "Test did not observe resume-PC capture after drain");
        if (rv64im72f8sp.EXR_valid || rv64im72f8sp.EX_valid ||
            rv64im72f8sp.EX2_valid || rv64im72f8sp.MEM_valid ||
            rv64im72f8sp.WB_valid)
            $fatal(1, "Interrupt resume PC latched before the pipeline drained");
        if (rv64im72f8sp.csr_file.mepc[1:0] !== 2'b00)
            $fatal(1, "External interrupt saved a misaligned mepc: %h",
                   rv64im72f8sp.csr_file.mepc);
        if (rv64im72f8sp.csr_file.mepc !==
            rv64im72f8sp.trap_controller.interrupt_resume_pc)
            $fatal(1, "mepc does not match the latched resume PC");
        if (rv64im72f8sp.csr_file.mepc !== 64'h24)
            $fatal(1, "External interrupt should resume at jump target 0x24, got %h",
                   rv64im72f8sp.csr_file.mepc);
        if (rv64im72f8sp.csr_file.MIE !== 1'b0 ||
            rv64im72f8sp.csr_file.MPIE !== 1'b1)
            $fatal(1, "Trap entry did not update MIE/MPIE correctly");

        begin : wait_for_handler
            integer cycles;
            cycles = 0;
            while (rv64im72f8sp.register_file.registers[4] !== 64'd1 &&
                   cycles < 100) begin
                @(posedge clk);
                #1;
                cycles = cycles + 1;
            end
            if (rv64im72f8sp.register_file.registers[4] !== 64'd1)
                $fatal(1, "Core did not execute the external interrupt handler");
        end

        $display("[PASS] Core captured external interrupt in mip.MEIP");
        $display("[PASS] Core saved mepc=%h and mcause=%h",
                 rv64im72f8sp.csr_file.mepc, rv64im72f8sp.csr_file.mcause);
        $display("[PASS] Core entered mtvec handler and executed its first instruction");
        $display("==================== RV64IM72F8SP Core External IRQ Test PASSED ====================");
        $finish;
    end

endmodule