huff-for-humans

A minimal, hand-rolled ERC-20 token written entirely in Huff assembly.

Public goods. Open source. No Solidity compiler. Just raw EVM opcodes, a human brain, and a Huff compiler.

What is this?

SimpleHuffToken.huff is a complete ERC-20 token with:





Standard ERC-20: transfer, approve, transferFrom, balanceOf, allowance, totalSupply



Metadata: name() ("HuffToken"), symbol() ("HUFF"), decimals() (18)



Owner-gated mint(address,uint256)



Self-burn via burn(uint256)



Delegated burn via burnFrom(address,uint256)



transferOwnership(address)



Full EIP-2612 Permit (gasless approvals via off-chain signatures)



EIP-712 domain separator computed at deploy time

All in 1823 bytes of runtime bytecode. Compiled with huffc 0.3.2.

Toolchain

Quick Start

# Compile Huff to bytecode
huffc SimpleHuffToken.huff -b > bytecode_raw.txt
echo -n "0x$(cat bytecode_raw.txt)" > bytecode.txt

# Run the full test suite
forge test -vv

# Deploy to local Anvil
anvil &
forge test --fork-url http://127.0.0.1:8545 -vv

Architecture

SimpleHuffToken.huff          <- The entire contract. ~450 lines of Huff assembly.
test/SimpleHuffToken.t.sol    <- 68-test comprehensive audit suite
test/Debug.t.sol              <- Low-level debug harness (raw .call())
bytecode.txt                  <- Compiled creation bytecode (0x-prefixed)
foundry.toml                  <- Foundry config (cancun EVM, 256 fuzz runs)

Storage Layout

Key Design Decisions





HASH_PAIR macro for all mapping slot computations: keccak256(key || slot) using scratch memory at 0x00-0x3F



Infinite allowance pattern: type(uint256).max allowances are never decremented (gas optimization)



STATICCALL to precompile 0x01 for ecrecover in permit (no opcode — must use precompile)



Constructor computes domain separator at deploy time using chainid and address



Engineer's Anvil Audit

74 tests. 0 failures. Full green.

Ran 74 tests in 3 suites: 74 passed, 0 failed, 0 skipped

Smoke Tests (7/7)

Basic sanity — does the contract even exist and respond correctly?

Unit Tests — Mint (4/4)

Unit Tests — Transfer (6/6)

Unit Tests — Approve (4/4)

Unit Tests — TransferFrom (6/6)

Unit Tests — Burn (3/3)

Unit Tests — BurnFrom (3/3)

Unit Tests — Ownership (5/5)

Unit Tests — Nonces (1/1)

Event Emission Tests (3/3)

EIP-2612 Permit Tests (6/6)

Invariant / Validation Tests (3/3)

Chaos / Edge-Case Tests (10/10)

Fuzz Tests (4/4, 256 runs each)

Monkey Tests (3/3)

Multi-operation sequences simulating real usage patterns.



Bugs Found & Fixed During Audit



License

Public domain. Do whatever you want with it.

Built by @greywolf42069 — infosec researcher, Huff enthusiast, EVM geometry explorer.