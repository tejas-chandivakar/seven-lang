# ============================================================
# SEVEN Language - Build Makefile
# Phase 1 Bootstrap Compiler
# ============================================================
# Requires: NASM + GNU ld (Linux or WSL)
#
# Usage:
#   make           - build the SEVEN compiler
#   make seven     - same as above
#   make test-lex  - run lexer on all test files
#   make test      - compile and run all test examples
#   make clean     - remove build artifacts
# ============================================================

NASM     := nasm
LD       := ld
NASMFLAGS := -f elf64 -w-label-redef-late
LDFLAGS  :=

SRC_DIR  := src
BUILD_DIR := build
EXAMPLES := examples
TESTS    := tests

# Source files
MAIN_SRC    := $(SRC_DIR)/main.asm
LEXER_SRC   := $(SRC_DIR)/lexer.asm
CODEGEN_SRC := $(SRC_DIR)/codegen.asm
RUNTIME_SRC := $(SRC_DIR)/runtime.asm

# Object files
MAIN_OBJ    := $(BUILD_DIR)/main.o
LEXER_OBJ   := $(BUILD_DIR)/lexer.o
CODEGEN_OBJ := $(BUILD_DIR)/codegen.o
RUNTIME_OBJ := $(BUILD_DIR)/runtime.o

# Output binary
SEVEN_BIN := $(BUILD_DIR)/seven

ALL_OBJS := $(MAIN_OBJ) $(LEXER_OBJ) $(CODEGEN_OBJ) $(RUNTIME_OBJ)

.PHONY: all seven test test-lex clean dirs

all: seven

seven: dirs $(SEVEN_BIN)

$(SEVEN_BIN): $(ALL_OBJS)
	$(LD) $(LDFLAGS) $^ -o $@

$(MAIN_OBJ): $(MAIN_SRC)
	$(NASM) $(NASMFLAGS) $< -o $@

$(LEXER_OBJ): $(LEXER_SRC)
	$(NASM) $(NASMFLAGS) $< -o $@

$(CODEGEN_OBJ): $(CODEGEN_SRC)
	$(NASM) $(NASMFLAGS) $< -o $@

$(RUNTIME_OBJ): $(RUNTIME_SRC)
	$(NASM) $(NASMFLAGS) $< -o $@

dirs:
	@mkdir -p $(BUILD_DIR)

# Debug: run lexer on all test files
test-lex: seven
	@echo "=== Lexer Tests ==="
	@for f in $(TESTS)/*.seven $(EXAMPLES)/*.seven; do \
		echo "-- $$f --"; \
		$(SEVEN_BIN) lex $$f || echo "FAILED: $$f"; \
		echo ""; \
	done

# Compile tests (codegen only)
test: seven
	@echo "=== Compile Tests ==="
	@for f in $(TESTS)/*.seven; do \
		echo "-- Compiling: $$f --"; \
		$(SEVEN_BIN) build $$f && echo "OK" || echo "FAILED: $$f"; \
	done

# Full end-to-end: compile, assemble, link, run
test-run: seven
	@echo "=== End-to-End Tests ==="
	@for f in $(TESTS)/*.seven; do \
		base=$$(basename $$f .seven); \
		echo "-- $$base --"; \
		$(SEVEN_BIN) build $$f || { echo "COMPILE FAILED"; continue; }; \
		$(NASM) $(NASMFLAGS) $$base.asm -o $(BUILD_DIR)/$$base.o || { echo "NASM FAILED"; continue; }; \
		$(LD) $(BUILD_DIR)/$$base.o $(RUNTIME_OBJ) -o $(BUILD_DIR)/$$base || { echo "LINK FAILED"; continue; }; \
		echo "Output:"; \
		$(BUILD_DIR)/$$base; \
		echo "-- exit: $$? --"; \
		echo ""; \
	done

clean:
	rm -rf $(BUILD_DIR)
