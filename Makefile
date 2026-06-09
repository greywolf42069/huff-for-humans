.PHONY: all build test fmt clean install verify-bytecode

HUFF_SRC := SimpleHuffToken.huff
BYTECODE := bytecode.txt

all: build test

## Compile the Huff source to creation bytecode (0x-prefixed, no trailing newline).
build:
	@huffc $(HUFF_SRC) -b > bytecode_raw.txt
	@printf '0x%s' "$$(cat bytecode_raw.txt)" > $(BYTECODE)
	@rm -f bytecode_raw.txt
	@echo "Wrote $(BYTECODE) ($$(( ($$(wc -c < $(BYTECODE)) - 2) / 2 )) bytes)"

## Run the full Foundry test suite against the committed bytecode.
test:
	@forge test -vv

## Fail if the committed bytecode is stale relative to the Huff source.
verify-bytecode:
	@huffc $(HUFF_SRC) -b > bytecode_raw.txt
	@printf '0x%s' "$$(cat bytecode_raw.txt)" > bytecode_check.txt
	@rm -f bytecode_raw.txt
	@if diff -q $(BYTECODE) bytecode_check.txt >/dev/null; then \
		echo "bytecode.txt is up to date"; rm -f bytecode_check.txt; \
	else \
		echo "ERROR: bytecode.txt is stale. Run 'make build' and commit."; \
		rm -f bytecode_check.txt; exit 1; \
	fi

fmt:
	@forge fmt

clean:
	@forge clean

## Install toolchains: forge-std submodule, Foundry, and the Huff compiler.
install:
	@git submodule update --init --recursive
	@echo "Now install Foundry (https://getfoundry.sh) and Huff (https://docs.huff.sh)."
