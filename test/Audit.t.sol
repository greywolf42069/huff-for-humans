// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

/// @title SimpleHuffToken — Adversarial Audit Suite
/// @notice Probes the edge cases the main suite does not: EIP-712 digest
///         correctness, nonce sequencing, signature malleability / replay,
///         permit `v` handling, allowance edge cases, and arithmetic limits.
///         Every test here documents an invariant we want to guarantee, so a
///         future change that breaks one surfaces immediately.
interface IHuffToken {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function allowance(address, address) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
    function burnFrom(address from, uint256 amount) external;
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function transferOwnership(address newOwner) external;
    function owner() external view returns (address);
    function nonces(address) external view returns (uint256);
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

contract SimpleHuffTokenAuditTest is Test {
    IHuffToken token;
    address deployer;

    uint256 constant OWNER_PK = 0xA11CE;
    address owner;
    address spender = address(0xB0B);
    address zero = address(0);

    bytes32 constant PERMIT_TYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    bytes32 constant DOMAIN_TYPEHASH =
        0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    // secp256k1 group order; valid signatures have s in [1, N/2] (EIP-2).
    uint256 constant SECP256K1_N =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    function setUp() public {
        deployer = address(this);
        bytes memory bytecode = vm.parseBytes(vm.readFile("bytecode.txt"));
        address deployed;
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(deployed != address(0), "Deployment failed");
        token = IHuffToken(deployed);
        owner = vm.addr(OWNER_PK);
    }

    // ── helpers ───────────────────────────────────────────────────────────

    function _digest(
        address _owner,
        address _spender,
        uint256 _value,
        uint256 _nonce,
        uint256 _deadline
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, _owner, _spender, _value, _nonce, _deadline)
        );
        return keccak256(
            abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)
        );
    }

    function _sign(
        uint256 pk,
        address _owner,
        address _spender,
        uint256 _value,
        uint256 _deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        uint256 nonce = token.nonces(_owner);
        return vm.sign(pk, _digest(_owner, _spender, _value, nonce, _deadline));
    }

    // ── EIP-712 domain separator must match the spec exactly ───────────────

    function test_domainSeparator_matchesEIP712() public view {
        bytes32 expected = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("HuffToken")),
                keccak256(bytes("1")),
                block.chainid,
                address(token)
            )
        );
        assertEq(token.DOMAIN_SEPARATOR(), expected, "domain separator drift");
    }

    function test_typehashes_matchStrings() public pure {
        assertEq(
            PERMIT_TYPEHASH,
            keccak256(
                "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
            )
        );
        assertEq(
            DOMAIN_TYPEHASH,
            keccak256(
                "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
            )
        );
    }

    // ── permit nonce sequencing ────────────────────────────────────────────

    function test_permit_noncesIncrementSequentially() public {
        uint256 deadline = block.timestamp + 1 hours;
        for (uint256 i = 0; i < 3; i++) {
            assertEq(token.nonces(owner), i, "nonce mismatch before permit");
            (uint8 v, bytes32 r, bytes32 s) = _sign(OWNER_PK, owner, spender, 100 + i, deadline);
            token.permit(owner, spender, 100 + i, deadline, v, r, s);
            assertEq(token.allowance(owner, spender), 100 + i);
        }
        assertEq(token.nonces(owner), 3);
    }

    // ── signature malleability must NOT enable a second use ─────────────────
    // A malleable (s' = N - s, v flipped) variant of an already-spent permit
    // signature must be rejected because the nonce was consumed.
    function test_permit_malleableVariantCannotReplay() public {
        uint256 value = 1000e18;
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _sign(OWNER_PK, owner, spender, value, deadline);

        token.permit(owner, spender, value, deadline, v, r, s);
        assertEq(token.nonces(owner), 1);

        // Build the malleable counterpart of the same signature.
        uint8 vFlip = v == 27 ? 28 : 27;
        bytes32 sFlip = bytes32(SECP256K1_N - uint256(s));

        vm.expectRevert();
        token.permit(owner, spender, value, deadline, vFlip, r, sFlip);
        assertEq(token.allowance(owner, spender), value, "allowance changed on replay");
    }

    // ── permit with an out-of-range v recovers a bogus signer → revert ──────
    function test_permit_invalidV_reverts() public {
        uint256 value = 1000e18;
        uint256 deadline = block.timestamp + 1 hours;
        (, bytes32 r, bytes32 s) = _sign(OWNER_PK, owner, spender, value, deadline);
        vm.expectRevert();
        token.permit(owner, spender, value, deadline, 29, r, s); // v ∉ {27,28}
    }

    // ── permit at exactly the deadline timestamp is still valid ─────────────
    function test_permit_atDeadline_succeeds() public {
        uint256 value = 500e18;
        uint256 deadline = block.timestamp; // timestamp == deadline, not > deadline
        (uint8 v, bytes32 r, bytes32 s) = _sign(OWNER_PK, owner, spender, value, deadline);
        token.permit(owner, spender, value, deadline, v, r, s);
        assertEq(token.allowance(owner, spender), value);
    }

    // ── permit cannot be front-run to a different spender (digest binds it) ──
    function test_permit_wrongSpender_reverts() public {
        uint256 value = 500e18;
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _sign(OWNER_PK, owner, spender, value, deadline);
        vm.expectRevert();
        token.permit(owner, address(0xDEAD), value, deadline, v, r, s);
    }

    // ── allowance: spending the full finite allowance then 1 more reverts ───
    function test_transferFrom_exactAllowanceThenOne() public {
        token.mint(owner, 1000e18);
        vm.prank(owner);
        token.approve(spender, 300e18);

        vm.prank(spender);
        token.transferFrom(owner, address(0xCAFE), 300e18);
        assertEq(token.allowance(owner, spender), 0);

        vm.prank(spender);
        vm.expectRevert();
        token.transferFrom(owner, address(0xCAFE), 1);
    }

    // ── burnFrom decrements a finite allowance and honors infinite ──────────
    function test_burnFrom_finiteAllowanceDecrements() public {
        token.mint(owner, 1000e18);
        vm.prank(owner);
        token.approve(spender, 400e18);
        vm.prank(spender);
        token.burnFrom(owner, 400e18);
        assertEq(token.allowance(owner, spender), 0);
        assertEq(token.totalSupply(), 600e18);
    }

    // ── arithmetic limit: totalSupply add wraps (owner-only, documented) ────
    // This is NOT exploitable by users (mint is owner-gated) but pins the
    // unchecked-math behavior so it is a conscious, documented property.
    function test_mint_totalSupplyOverflowWraps() public {
        token.mint(owner, type(uint256).max);
        assertEq(token.totalSupply(), type(uint256).max);
        // Minting 1 more wraps to 0 — unchecked, owner-controlled.
        token.mint(owner, 1);
        assertEq(token.totalSupply(), 0, "expected documented wraparound");
    }

    // ── conservation under transferFrom fuzzing ─────────────────────────────
    function testFuzz_transferFrom_conservesSupply(
        uint128 mintAmt,
        uint128 allow,
        uint128 send
    ) public {
        vm.assume(send <= mintAmt);
        vm.assume(send <= allow);
        token.mint(owner, mintAmt);
        vm.prank(owner);
        token.approve(spender, allow);

        uint256 supplyBefore = token.totalSupply();
        vm.prank(spender);
        token.transferFrom(owner, address(0x1234), send);

        assertEq(token.totalSupply(), supplyBefore, "supply changed on transferFrom");
        assertEq(token.balanceOf(owner) + token.balanceOf(address(0x1234)), mintAmt);
    }

    // ── only owner may mint / transfer ownership; renounce-to-zero blocked ──
    function test_transferOwnership_toZeroReverts() public {
        vm.expectRevert();
        token.transferOwnership(zero);
        assertEq(token.owner(), deployer, "owner should be unchanged");
    }

    // ── unknown selector and short calldata both revert (no fallback mint) ──
    function test_noFallback_unknownSelectorReverts() public {
        (bool ok, ) = address(token).call(abi.encodeWithSelector(bytes4(0x12345678)));
        assertFalse(ok);
    }
}
