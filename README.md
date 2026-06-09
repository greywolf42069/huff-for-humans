# huff-for-humans

A minimal, hand-rolled ERC-20 token written entirely in [Huff](https://docs.huff.sh) assembly.

Public goods. Open source. No Solidity compiler for the token itself — just raw EVM
opcodes, a human brain, and the Huff compiler.

## What is this?

[`SimpleHuffToken.huff`](./SimpleHuffToken.huff) is a complete ERC-20 token:

- **Standard ERC-20** — `transfer`, `approve`, `transferFrom`, `balanceOf`,
  `allowance`, `totalSupply`
- **Metadata** — `name()` (`"HuffToken"`), `symbol()` (`"HUFF"`), `decimals()` (`18`)
- **Owner-gated** `mint(address,uint256)`
- **Self-burn** via `burn(uint256)` and **delegated burn** via `burnFrom(address,uint256)`
- **Ownership** — `transferOwnership(address)`, `owner()`
- **Full EIP-2612 Permit** — gasless approvals via off-chain EIP-712 signatures,
  interoperable with standard wallets/libraries (ethers, viem, MetaMask, OpenZeppelin)
- **EIP-712 domain separator** computed at deploy time from `chainid` and `address`

Runtime bytecode: **1823 bytes** (creation: 1975 bytes). Compiled with `huffc 0.3.2`.

## Toolchain

| Tool | Version | Install |
|------|---------|---------|
| Huff | 0.3.2 | `curl -L get.huff.sh \| bash && huffup` |
| Foundry | latest | `curl -L https://foundry.paradigm.xyz \| bash && foundryup` |

```bash
# One-time: pull the test dependency (forge-std)
git submodule update --init --recursive
```

## Quick Start

```bash
# Compile Huff to creation bytecode (0x-prefixed, no trailing newline)
make build           # == huffc SimpleHuffToken.huff -b  →  bytecode.txt

# Run the full test suite (deploys the compiled bytecode and exercises it)
make test            # == forge test -vv

# Fail loudly if bytecode.txt has drifted from the Huff source
make verify-bytecode
```

CI ([`.github/workflows/ci.yml`](./.github/workflows/ci.yml)) recompiles the Huff
on every push, asserts the committed `bytecode.txt` matches, and runs the suite.

## Architecture

```
SimpleHuffToken.huff          <- The entire contract (~450 lines of Huff)
bytecode.txt                  <- Compiled creation bytecode (0x-prefixed)
foundry.toml                  <- Foundry config (cancun EVM, 256 fuzz runs)
Makefile                      <- build / test / verify-bytecode targets
test/SimpleHuffToken.t.sol    <- Functional ERC-20 audit suite
test/Audit.t.sol              <- EIP-712/2612 standards-compliance + adversarial suite
test/Debug.t.sol              <- Low-level debug harness (raw .call())
docs-old/                     <- Original "Huff for Humans" PWA tutorial
```

## Storage Layout

| Slot | Contents |
|------|----------|
| `0x00` | `totalSupply` |
| `0x01` | `balanceOf` mapping base (`keccak256(addr ‖ 0x01)`) |
| `0x02` | `allowance` mapping base (nested hash) |
| `0x03` | `owner` |
| `0x04` | `nonces` mapping base |
| `0x05` | cached `DOMAIN_SEPARATOR` |

## Key Design Decisions

- **`HASH_PAIR` macro** for every mapping slot: `keccak256(key ‖ slot)` using scratch
  memory at `0x00–0x3F`.
- **Infinite allowance pattern**: `type(uint256).max` allowances are never decremented
  (gas optimization, matches OpenZeppelin/standard behavior).
- **`STATICCALL` to precompile `0x01`** for `ecrecover` in `permit` (there is no opcode).
- **Cached domain separator** computed once in the constructor from `chainid` + `address`.

## Test Suite

**90 tests across 3 suites. 0 failures.**

```
test/SimpleHuffToken.t.sol  — 68 tests  (smoke, ERC-20 units, events, permit, fuzz, monkey)
test/Audit.t.sol            — 18 tests  (EIP-712/2612 standards compliance, malleability,
                                          nonce sequencing, arithmetic limits, conservation)
test/Debug.t.sol            —  4 tests  (raw low-level call harness)
```

`test/Audit.t.sol` checks the contract against the **published EIP-712/EIP-2612 strings**
(not against the contract's own constants), so a regression in the domain separator or
typehash fails CI immediately.

## Audit

See [`AUDIT.md`](./AUDIT.md) for the full findings. Three bugs were found and fixed:
two **High-severity** EIP-2612 interoperability bugs (incorrect `PERMIT_TYPEHASH` and an
incorrectly-padded name/version hash in the domain separator) and one **Medium** event
bug (`permit` emitted `Approval` with `owner`/`spender` swapped), plus documented known
limitations.

## License

Public domain. Do whatever you want with it.

Built by [@greywolf42069](https://github.com/greywolf42069) — infosec researcher,
Huff enthusiast, EVM geometry explorer.
