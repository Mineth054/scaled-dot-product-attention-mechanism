# ─────────────────────────────────────────────────────────────────────────
# attention_hardware -- Makefile
#
# One-shot build/run/validate flow using Icarus Verilog and Python.
#
#   make            -- alias for `test`
#   make build      -- compile RTL + top_level_tb into sim/top_sim
#   make run        -- run sim/top_sim (produces output.txt + VCD)
#   make validate   -- run validate.py against the fp32 Python reference
#   make test       -- build + run + validate (single end-to-end check)
#   make wave       -- open sim/attention.vcd in gtkwave (Linux/Mac/WSL)
#   make luts       -- regenerate data/recip_lut.txt + data/O_expected.txt
#   make <mod>_sim  -- per-module simulator (mac_sim, mul_sim, mm_sim, ...)
#   make clean      -- remove sim binaries, VCD, generated output
#
# Tested with iverilog 12.0, Python 3.12+.
# ─────────────────────────────────────────────────────────────────────────

IVERILOG ?= iverilog
VVP      ?= vvp
PYTHON   ?= python
GTKWAVE  ?= gtkwave

IVFLAGS  ?= -g2012

SRC      := $(wildcard src/*.v)
SIMDIR   := sim
DATADIR  := data

TOP_SIM   := $(SIMDIR)/top_sim
TOP_TB    := tb/top_level_tb.v
VCD       := $(SIMDIR)/attention.vcd
OUTPUT    := $(DATADIR)/output.txt
EXPECTED  := $(DATADIR)/O_expected.txt
RECIP_LUT := $(DATADIR)/recip_lut.txt

.PHONY: all test build run validate wave luts clean help \
        mac_sim mul_sim mm_sim proj_sim score_sim scale_sim softmax_sim out_sim

all: test

# ─── end-to-end ───
test: build run validate

# ─── top-level integration ───
build: $(TOP_SIM)

$(TOP_SIM): $(SRC) $(TOP_TB) | $(SIMDIR)
	$(IVERILOG) $(IVFLAGS) -o $@ $(SRC) $(TOP_TB)

run: $(TOP_SIM) $(EXPECTED) $(RECIP_LUT)
	$(VVP) $(TOP_SIM)

validate: $(OUTPUT)
	$(PYTHON) validate.py

wave: $(VCD)
	$(GTKWAVE) $(VCD) &

# ─── LUTs + golden vector ───
luts: $(RECIP_LUT) $(EXPECTED)

$(RECIP_LUT): scripts/gen_luts.py
	$(PYTHON) scripts/gen_luts.py

$(EXPECTED): scripts/gen_golden.py $(DATADIR)/X.txt $(DATADIR)/WQ.txt $(DATADIR)/WK.txt $(DATADIR)/WV.txt
	$(PYTHON) scripts/gen_golden.py

# ─── per-module sims ───
mac_sim:     ; $(IVERILOG) $(IVFLAGS) -o $(SIMDIR)/mac_sim     src/multiplier.v src/mac_unit.v tb/mac_unit_tb.v && $(VVP) $(SIMDIR)/mac_sim
mul_sim:     ; $(IVERILOG) $(IVFLAGS) -o $(SIMDIR)/mul_sim     src/multiplier.v tb/multiplier_tb.v && $(VVP) $(SIMDIR)/mul_sim
mm_sim:      ; $(IVERILOG) $(IVFLAGS) -o $(SIMDIR)/mm_sim      src/matrix_multiply.v tb/matrix_multiply_tb.v && $(VVP) $(SIMDIR)/mm_sim
proj_sim:    ; $(IVERILOG) $(IVFLAGS) -o $(SIMDIR)/proj_sim    src/matrix_multiply.v src/projection_unit.v tb/projection_unit_tb.v && $(VVP) $(SIMDIR)/proj_sim
score_sim:   ; $(IVERILOG) $(IVFLAGS) -o $(SIMDIR)/score_sim   src/score_unit.v tb/score_unit_tb.v && $(VVP) $(SIMDIR)/score_sim
scale_sim:   ; $(IVERILOG) $(IVFLAGS) -o $(SIMDIR)/scale_sim   src/scale_unit.v tb/scale_unit_tb.v && $(VVP) $(SIMDIR)/scale_sim
softmax_sim: ; $(IVERILOG) $(IVFLAGS) -o $(SIMDIR)/softmax_sim src/softmax_unit.v src/unsigned_multiplier.v tb/softmax_unit_tb.v && $(VVP) $(SIMDIR)/softmax_sim
out_sim:     ; $(IVERILOG) $(IVFLAGS) -o $(SIMDIR)/out_sim     src/multiplier.v src/output_unit.v tb/output_unit_tb.v && $(VVP) $(SIMDIR)/out_sim

# ─── housekeeping ───
$(SIMDIR):
	mkdir -p $(SIMDIR)

clean:
	rm -f $(SIMDIR)/*_sim $(SIMDIR)/top_sim $(VCD) $(OUTPUT)

help:
	@echo "Targets: test (default) | build | run | validate | wave | luts | clean"
	@echo "Per-module: mac_sim mul_sim mm_sim proj_sim score_sim scale_sim softmax_sim out_sim"
