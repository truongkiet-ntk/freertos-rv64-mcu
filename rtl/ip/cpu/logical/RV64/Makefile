QUESTA_HOME ?= /mnt/d/ProgramFiles/questasim64_10.7c/win64
QUESTA_VLIB ?= $(QUESTA_HOME)/vlib.exe
QUESTA_VLOG ?= $(QUESTA_HOME)/vlog.exe
QUESTA_VSIM ?= $(QUESTA_HOME)/vsim.exe
WORK_LIB ?= work
sim ?= all

RTL_SOURCES := \
	modules/CSR_File.v \
	modules/Exception_Detector.v \
	modules/Trap_Controller.v

TEST_SOURCES := \
	testbenches/CSR_File_tb.v \
	testbenches/Exception_Detector_tb.v \
	testbenches/TrapController_tb.v \
	testbenches/External_Interrupt_tb.v
CORE_TEST_SOURCE := testbenches/RV32IM54F_8SP_tb.v
CORE_TEST_TOP := RV64IM72F8SP_Core_tb
CORE_RTL_SOURCE := modules/RV64IM72F_8SP.v

.DEFAULT_GOAL := dispatch
.PHONY: dispatch help compile compile-core compile-external run-sim sim sim-external sim-exception wave clean questa-version
.NOTPARALLEL:

ifneq ($(strip $(wave)),)
dispatch: wave
else
dispatch: sim
endif

help:
	@echo "Targets:"
	@echo "  make compile          Compile the CSR, exception, trap, and IRQ testbenches"
	@echo "  make sim              Run unit and full-core testbenches"
	@echo "  make sim=<testbench>  Run one testbench (e.g. make sim=CSRFile_tb)"
	@echo "                        Use $(CORE_TEST_TOP) for the full-core IRQ check"
	@echo "  make sim-external     Run focused external IRQ checks"
	@echo "  make sim-exception    Run exception-detector tests"
	@echo "  make wave=<testbench> Run a testbench and open its waveform (e.g. make wave=TrapController_tb)"
	@echo "  make clean            Remove Questa work/log/wave output"
	@echo "Override QUESTA_HOME if QuestaSim is installed elsewhere."

questa-version:
	"$(QUESTA_VSIM)" -version

compile:
	@test -f "$(QUESTA_VLIB)" || { echo "Questa vlib not found: $(QUESTA_VLIB)"; exit 1; }
	@test -f "$(QUESTA_VLOG)" || { echo "Questa vlog not found: $(QUESTA_VLOG)"; exit 1; }
	@if [ ! -d "$(WORK_LIB)" ]; then "$(QUESTA_VLIB)" "$(WORK_LIB)" || exit 1; fi
	"$(QUESTA_VLOG)" -work "$(WORK_LIB)" +incdir+modules $(RTL_SOURCES) $(TEST_SOURCES)

compile-core:
	@test -f "$(QUESTA_VLIB)" || { echo "Questa vlib not found: $(QUESTA_VLIB)"; exit 1; }
	@test -f "$(QUESTA_VLOG)" || { echo "Questa vlog not found: $(QUESTA_VLOG)"; exit 1; }
	@if [ ! -d "$(WORK_LIB)" ]; then "$(QUESTA_VLIB)" "$(WORK_LIB)" || exit 1; fi
	"$(QUESTA_VLOG)" -sv -work "$(WORK_LIB)" +incdir+modules $(CORE_RTL_SOURCE) $(CORE_TEST_SOURCE)

compile-external:
	@test -f "$(QUESTA_VLIB)" || { echo "Questa vlib not found: $(QUESTA_VLIB)"; exit 1; }
	@test -f "$(QUESTA_VLOG)" || { echo "Questa vlog not found: $(QUESTA_VLOG)"; exit 1; }
	@if [ ! -d "$(WORK_LIB)" ]; then "$(QUESTA_VLIB)" "$(WORK_LIB)" || exit 1; fi
	"$(QUESTA_VLOG)" -work "$(WORK_LIB)" +incdir+modules $(RTL_SOURCES) testbenches/External_Interrupt_tb.v

run-sim:
	@test -n "$(testbench)" || { echo "Specify testbench=<name>."; exit 2; }
	@log_file="$(WORK_LIB)/sim-$(testbench).log"; \
	"$(QUESTA_VSIM)" -c -lib "$(WORK_LIB)" "$(testbench)" -do "run -all; quit -f" > "$$log_file" 2>&1; \
	status=$$?; \
	cat "$$log_file"; \
	if [ $$status -ne 0 ]; then exit $$status; fi; \
	if grep -Eq '\*\* (Fatal|Error):|\[FAIL\]' "$$log_file"; then \
		echo "Questa reported a simulation failure in $(testbench)." >&2; exit 1; \
	fi

sim:
	@case "$(sim)" in \
		all) $(MAKE) compile && \
		     for testbench in CSRFile_tb ExceptionDetector_tb TrapController_tb External_Interrupt_tb; do \
		         $(MAKE) run-sim testbench=$$testbench || exit $$?; \
		     done && \
		     $(MAKE) compile-core && \
		     $(MAKE) run-sim testbench="$(CORE_TEST_TOP)" ;; \
		$(CORE_TEST_TOP)|RV32IM54F_8SP_tb|RV32IM54F_8SP_tb.v) \
		     $(MAKE) compile-core && \
		     $(MAKE) run-sim testbench="$(CORE_TEST_TOP)" ;; \
		CSRFile_tb|CSR_File_tb|CSR_File_tb.v|ExceptionDetector_tb|Exception_Detector_tb|Exception_Detector_tb.v|TrapController_tb|Trap_Controller_tb|TrapController_tb.v|External_Interrupt_tb|External_Interrupt_tb.v) \
		     $(MAKE) compile && \
		     case "$(sim)" in \
		         CSRFile_tb|CSR_File_tb|CSR_File_tb.v) testbench="CSRFile_tb" ;; \
		         ExceptionDetector_tb|Exception_Detector_tb|Exception_Detector_tb.v) testbench="ExceptionDetector_tb" ;; \
		         TrapController_tb|Trap_Controller_tb|TrapController_tb.v) testbench="TrapController_tb" ;; \
		         *) testbench="External_Interrupt_tb" ;; \
		     esac && \
		     $(MAKE) run-sim testbench=$$testbench ;; \
		*) echo "Unknown testbench '$(sim)'."; \
		   echo "Choose: CSRFile_tb, ExceptionDetector_tb, TrapController_tb, External_Interrupt_tb, $(CORE_TEST_TOP), or all."; \
		   exit 2 ;; \
	esac

sim-external: compile-external
	$(MAKE) run-sim testbench=External_Interrupt_tb

sim-exception: compile
	$(MAKE) run-sim testbench=ExceptionDetector_tb

wave:
	@if [ -z "$(wave)" ]; then \
		echo "Specify a testbench, e.g. make wave=TrapController_tb"; exit 2; \
	fi
	@test -f "$(QUESTA_VSIM)" || { echo "Questa vsim not found: $(QUESTA_VSIM)"; exit 1; }
	@if [ ! -d "$(WORK_LIB)" ]; then "$(QUESTA_VLIB)" "$(WORK_LIB)" || exit 1; fi
	@case "$(wave)" in \
		CSRFile_tb|CSR_File_tb|CSR_File_tb.v) testbench="CSRFile_tb"; compile_target="compile" ;; \
		ExceptionDetector_tb|Exception_Detector_tb|Exception_Detector_tb.v) testbench="ExceptionDetector_tb"; compile_target="compile" ;; \
		TrapController_tb|Trap_Controller_tb|TrapController_tb.v) testbench="TrapController_tb"; compile_target="compile" ;; \
		External_Interrupt_tb|External_Interrupt_tb.v) testbench="External_Interrupt_tb"; compile_target="compile" ;; \
		$(CORE_TEST_TOP)|RV32IM54F_8SP_tb|RV32IM54F_8SP_tb.v) testbench="$(CORE_TEST_TOP)"; compile_target="compile-core" ;; \
		*) echo "Unknown testbench '$(wave)'."; \
		   echo "Choose: CSRFile_tb, ExceptionDetector_tb, TrapController_tb, External_Interrupt_tb, or $(CORE_TEST_TOP)."; \
		   exit 2 ;; \
	esac; \
	$(MAKE) "$$compile_target" && \
	"$(QUESTA_VSIM)" -c -voptargs=+acc -lib "$(WORK_LIB)" -wlf "$(WORK_LIB)/wave_view.wlf" "$$testbench" \
		-do "log -r /*; run -all; quit -f" && \
	"$(QUESTA_VSIM)" -view "$(WORK_LIB)/wave_view.wlf"

clean:
	rm -rf "$(WORK_LIB)"
	rm -f transcript vsim.wlf
	rm -f testbenches/results/waveforms/CSR_File.vcd
	rm -f testbenches/results/waveforms/Exception_Detector_tb.vcd
	rm -f testbenches/results/waveforms/Trap_Controller_tb_pth_direct_result.vcd
	rm -f testbenches/results/waveforms/External_Interrupt_tb.vcd
	rm -f testbenches/results/waveforms/RV64IM72F8SP_Core_tb.vcd