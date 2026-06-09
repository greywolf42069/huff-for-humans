# SimpleHuffToken — Audit Notes

Scope: [`SimpleHuffToken.huff`](./SimpleHuffToken.huff) (v3.0), the compiled
`bytecode.txt`, and the Foundry test suites under `test/`.

Method: manual review of the Huff/EVM logic (stack-effect tracing of every macro and
branch), reconstruction of the EIP-712/EIP-2612 constants from their canonical strings,
and an adversarial Foundry suite (`test/Audit.t.sol`) that checks the contract against
the **standard** rather than against its own constants. All 93 tests pass after the
fixes below.

---

## Findings

### H-1 — `PERMIT_TYPEHASH` did not match the EIP-2612 string (Fixed)

**Severity:** High (standards interoperability)

The contract hard-coded:

```
PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fea2543b90042d7b3d644eae9740da8db28d22a
```

but the canonical value is:

```
keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
        = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9
```

Any wallet or library (ethers, viem, MetaMask, OpenZeppelin) signing an EIP-2612 permit
uses the canonical typehash, so the contract would recover a different signer and reject
every standards-compliant signature. The "gasless approvals / full EIP-2612" feature was
non-functional with real tooling.

The original 68-test suite missed this because it computed the permit digest with the
**same** wrong constant, making the test internally consistent with the bug.

**Fix:** replaced the constant with the canonical typehash.

### H-2 — Domain separator hashed padded 32-byte words instead of the name/version strings (Fixed)

**Severity:** High (standards interoperability)

EIP-712 requires `nameHash = keccak256(bytes("HuffToken"))` and
`versionHash = keccak256(bytes("1"))` — i.e. the hash of the *raw UTF-8 bytes* (9 bytes
and 1 byte respectively). The constructor instead hashed a full 32-byte word:

```huff
0x48756666546f6b656e0000…0000 0x80 mstore
0x20 0x80 sha3      // ← hashes 32 bytes, not the 9 bytes of "HuffToken"
```

So the cached `DOMAIN_SEPARATOR` did not match the value any EIP-712 client computes:

| | Contract (before) | EIP-712 standard |
|---|---|---|
| name hash | `keccak256(0x4875…0000)` = `0x4fbcc5…` | `keccak256("HuffToken")` = `0xda171a…` |
| version hash | `keccak256(0x3100…0000)` = `0x20463d…` | `keccak256("1")` = `0xc89efd…` |

Combined with H-1, the entire permit digest was non-standard.

**Fix:** hash the correct lengths — `0x09 0x80 sha3` for the name and `0x01 0x80 sha3`
for the version.

> `DOMAIN_TYPEHASH` (`0x8b73c3c6…b39400f`) was verified correct and left unchanged.

**Regression guard:** `test/Audit.t.sol::test_domainSeparator_matchesEIP712` and
`test_typehashes_matchStrings` reconstruct the domain separator and both typehashes from
their canonical strings and assert equality, so any future drift fails CI.
`test_permit_standardWalletFlow_endToEnd` goes further: it builds the entire permit
digest the way an off-chain wallet does — from the published EIP-712 strings, the chain
id and the contract address, never reading the on-chain `DOMAIN_SEPARATOR` — then submits
the signature and asserts the allowance, nonce and `Approval` event. This is the
end-to-end proof of the "interoperable with standard wallets" claim.

### M-1 — `permit` emitted `Approval` with `owner`/`spender` swapped (Fixed)

**Severity:** Medium (event correctness / off-chain accounting)

The `permit` path emitted `Approval(spender, owner, value)` instead of
`Approval(owner, spender, value)` — the two indexed topics were pushed in the wrong order:

```huff
0x04 calldataload 0x24 calldataload   // owner, then spender → topic1=spender, topic2=owner
```

The state change (the allowance) was correct, but the emitted event was backwards. Any
indexer, subgraph or dApp reconstructing allowances from `Approval` logs would attribute
the approval to the wrong pair. The regular `approve` path was correct; only `permit` was
affected, and no prior test asserted the permit event.

**Fix:** push `spender` before `owner` so `log3` records `topic1=owner, topic2=spender`.

**Regression guard:** the end-to-end permit test now uses `vm.expectEmit`, and
`test_event_transferFrom` / `test_event_burn` / `test_event_burnFrom` were added so every
event path's indexed ordering is checked (the original suite only checked
transfer/mint/approve).

### L-1 — Functions accepted ETH despite the `nonpayable` ABI (Fixed)

**Severity:** Low (fund safety / ABI conformance)

The dispatcher never checked `callvalue`, so any call carrying ETH — e.g.
`transfer{value: 1 ether}(...)` — was silently accepted. The contract has no `withdraw`
path, so that ETH would be **locked forever**. Solidity emits this guard automatically for
`nonpayable` functions; the hand-written Huff omitted it, contradicting the `nonpayable`
declarations in the ABI.

**Fix:** a single `callvalue notPayable jumpi` at the top of `MAIN` — no function is
payable, so any non-zero value reverts before dispatch (~6 bytes; runtime grew
1823 → 1829).

**Regression guard:** `test_nonpayable_rejectsEtherOnCall`,
`test_nonpayable_rejectsEtherOnView`, and `test_nonpayable_zeroValueStillWorks`.

> Note: `SELFDESTRUCT` and block-reward payments can still force ETH into *any* contract
> address — that is unpreventable at the EVM level and not specific to this token.

---

## Verified correct (no change required)

- **`transfer` / `transferFrom` / `burn` / `burnFrom`** — stack effects, balance/allowance
  checks (`bal < amount` → revert), and self-transfer net-zero behavior traced and tested.
- **Infinite allowance** — `type(uint256).max` allowances are not decremented in
  `transferFrom`/`burnFrom`; matches standard behavior.
- **`permit`** — nonce is incremented before signature checks (replay-safe); expired
  `deadline` reverts (`timestamp > deadline`); recovered signer compared against `owner`.
  Signature malleability cannot enable replay because the nonce is consumed
  (`test_permit_malleableVariantCannotReplay`).
- **Access control** — `mint` and `transferOwnership` are owner-gated; `transferOwnership`
  rejects the zero address.
- **Dispatcher** — calldata `< 4` bytes and unknown selectors revert (no unintended
  fallback).
- **`ecrecover`** — invalid signatures (empty precompile output / out-of-range `v`) leave
  the digest in the output buffer, which never equals the non-zero `owner`, so the permit
  reverts (`test_permit_invalidV_reverts`).

---

## Known limitations (by design — documented, not bugs)

1. **Unchecked arithmetic.** Balances and `totalSupply` use raw `add`/`sub`. The `sub`
   paths are guarded by explicit `bal < amount` checks. The `add` paths
   (`mint`, transfer credit) are unguarded; `mint` is owner-only, and transfer credits
   are bounded by conservation, so realistic flows cannot overflow. A malicious owner can
   overflow `totalSupply` via `mint` — see `test_mint_totalSupplyOverflowWraps`, which
   pins this as a conscious, documented property.
2. **Cached domain separator.** Computed once at deploy. If the chain undergoes a
   chain-id change (replay-protection fork), the cached separator becomes stale. Standard
   for most cached EIP-712 implementations; acceptable for this token's scope.
3. **`approve`/`transfer` to the zero address revert.** Intentional (OpenZeppelin-style
   guard), slightly stricter than the bare ERC-20 spec.
4. **No `permit` zero-value short-circuit / no EIP-1271 support.** EOA signatures only.

---

## Reproducing

```bash
git submodule update --init --recursive
make verify-bytecode   # asserts bytecode.txt matches the Huff source
make test              # 93 tests, 0 failures
```
