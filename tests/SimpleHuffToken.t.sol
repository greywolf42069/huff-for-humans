// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

/// @title SimpleHuffToken Test Suite
/// @notice Comprehensive audit/unit/validation/chaos/smoke/monkey tests
/// @dev Deploys raw bytecode from huffc compilation

interface IHuffToken {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address) external view returns (uint256);

    function allowance(address, address) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

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

contract SimpleHuffTokenTest is Test {
    IHuffToken token;
    address deployer;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address charlie = address(0xC);
    address zero = address(0);

    // Permit test key pair
    uint256 ownerPrivateKey = 0xA11CE;
    address permitOwner;

    function setUp() public {
        deployer = address(this);

        // Read bytecode from file and deploy
        string memory bytecodeHex = vm.readFile("bytecode.txt");
        bytes memory bytecode = vm.parseBytes(bytecodeHex);

        address deployed;
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(deployed != address(0), "Deployment failed");
        token = IHuffToken(deployed);

        // Derive permit owner from private key
        permitOwner = vm.addr(ownerPrivateKey);
    }

    // ════════════════════════════════════════════════════════════
    //  SMOKE TESTS — Basic sanity checks
    // ════════════════════════════════════════════════════════════

    function test_smoke_deployment() public view {
        assertTrue(address(token) != address(0), "Token deployed");
    }

    function test_smoke_name() public view {
        assertEq(token.name(), "HuffToken");
    }

    function test_smoke_symbol() public view {
        assertEq(token.symbol(), "HUFF");
    }

    function test_smoke_decimals() public view {
        assertEq(token.decimals(), 18);
    }

    function test_smoke_initialSupply() public view {
        assertEq(token.totalSupply(), 0);
    }

    function test_smoke_owner() public view {
        assertEq(token.owner(), deployer);
    }

    function test_smoke_domainSeparator() public view {
        bytes32 ds = token.DOMAIN_SEPARATOR();
        assertTrue(ds != bytes32(0), "Domain separator should be non-zero");
    }

    // ════════════════════════════════════════════════════════════
    //  UNIT TESTS — Core ERC-20 functionality
    // ════════════════════════════════════════════════════════════

    // ─── Mint ───
    function test_mint() public {
        token.mint(alice, 1000e18);
        assertEq(token.balanceOf(alice), 1000e18);
        assertEq(token.totalSupply(), 1000e18);
    }

    function test_mint_multipleAccounts() public {
        token.mint(alice, 500e18);
        token.mint(bob, 300e18);
        assertEq(token.balanceOf(alice), 500e18);
        assertEq(token.balanceOf(bob), 300e18);
        assertEq(token.totalSupply(), 800e18);
    }

    function test_mint_revert_nonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        token.mint(alice, 100e18);
    }

    function test_mint_revert_toZeroAddress() public {
        vm.expectRevert();
        token.mint(zero, 100e18);
    }

    // ─── Transfer ───
    function test_transfer() public {
        token.mint(alice, 1000e18);
        vm.prank(alice);
        bool ok = token.transfer(bob, 200e18);
        assertTrue(ok);
        assertEq(token.balanceOf(alice), 800e18);
        assertEq(token.balanceOf(bob), 200e18);
    }

    function test_transfer_entireBalance() public {
        token.mint(alice, 100e18);
        vm.prank(alice);
        token.transfer(bob, 100e18);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 100e18);
    }

    function test_transfer_revert_insufficientBalance() public {
        token.mint(alice, 100e18);
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 101e18);
    }

    function test_transfer_revert_toZeroAddress() public {
        token.mint(alice, 100e18);
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(zero, 50e18);
    }

    function test_transfer_zeroAmount() public {
        token.mint(alice, 100e18);
        vm.prank(alice);
        token.transfer(bob, 0);
        assertEq(token.balanceOf(alice), 100e18);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transfer_preservesTotalSupply() public {
        token.mint(alice, 1000e18);
        vm.prank(alice);
        token.transfer(bob, 400e18);
        assertEq(token.totalSupply(), 1000e18);
    }

    // ─── Approve ───
    function test_approve() public {
        vm.prank(alice);
        bool ok = token.approve(bob, 500e18);
        assertTrue(ok);
        assertEq(token.allowance(alice, bob), 500e18);
    }

    function test_approve_overwrite() public {
        vm.prank(alice);
        token.approve(bob, 500e18);
        vm.prank(alice);
        token.approve(bob, 200e18);
        assertEq(token.allowance(alice, bob), 200e18);
    }

    function test_approve_revert_toZeroAddress() public {
        vm.prank(alice);
        vm.expectRevert();
        token.approve(zero, 100e18);
    }

    function test_approve_maxUint() public {
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        assertEq(token.allowance(alice, bob), type(uint256).max);
    }

    // ─── TransferFrom ───
    function test_transferFrom() public {
        token.mint(alice, 1000e18);
        vm.prank(alice);
        token.approve(bob, 500e18);

        vm.prank(bob);
        bool ok = token.transferFrom(alice, charlie, 200e18);
        assertTrue(ok);
        assertEq(token.balanceOf(alice), 800e18);
        assertEq(token.balanceOf(charlie), 200e18);
        assertEq(token.allowance(alice, bob), 300e18); // 500 - 200
    }

    function test_transferFrom_revert_exceedsAllowance() public {
        token.mint(alice, 1000e18);
        vm.prank(alice);
        token.approve(bob, 100e18);

        vm.prank(bob);
        vm.expectRevert();
        token.transferFrom(alice, charlie, 200e18);
    }

    function test_transferFrom_revert_exceedsBalance() public {
        token.mint(alice, 50e18);
        vm.prank(alice);
        token.approve(bob, 100e18);

        vm.prank(bob);
        vm.expectRevert();
        token.transferFrom(alice, charlie, 51e18);
    }

    function test_transferFrom_infiniteAllowance() public {
        token.mint(alice, 1000e18);
        vm.prank(alice);
        token.approve(bob, type(uint256).max);

        vm.prank(bob);
        token.transferFrom(alice, charlie, 500e18);

        // infinite allowance should not decrease
        assertEq(token.allowance(alice, bob), type(uint256).max);
        assertEq(token.balanceOf(charlie), 500e18);
    }

    function test_transferFrom_revert_fromZero() public {
        vm.prank(bob);
        vm.expectRevert();
        token.transferFrom(zero, charlie, 1);
    }

    function test_transferFrom_revert_toZero() public {
        token.mint(alice, 100e18);
        vm.prank(alice);
        token.approve(bob, 100e18);
        vm.prank(bob);
        vm.expectRevert();
        token.transferFrom(alice, zero, 50e18);
    }

    // ─── Burn ───
    function test_burn() public {
        token.mint(alice, 1000e18);
        vm.prank(alice);
        token.burn(300e18);
        assertEq(token.balanceOf(alice), 700e18);
        assertEq(token.totalSupply(), 700e18);
    }

    function test_burn_entireBalance() public {
        token.mint(alice, 100e18);
        vm.prank(alice);
        token.burn(100e18);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), 0);
    }

    function test_burn_revert_exceedsBalance() public {
        token.mint(alice, 100e18);
        vm.prank(alice);
        vm.expectRevert();
        token.burn(101e18);
    }

    // ─── BurnFrom ───
    function test_burnFrom() public {
        token.mint(alice, 1000e18);
        vm.prank(alice);
        token.approve(bob, 500e18);

        vm.prank(bob);
        token.burnFrom(alice, 200e18);
        assertEq(token.balanceOf(alice), 800e18);
        assertEq(token.totalSupply(), 800e18);
        assertEq(token.allowance(alice, bob), 300e18);
    }

    function test_burnFrom_revert_exceedsAllowance() public {
        token.mint(alice, 1000e18);
        vm.prank(alice);
        token.approve(bob, 100e18);

        vm.prank(bob);
        vm.expectRevert();
        token.burnFrom(alice, 200e18);
    }

    function test_burnFrom_infiniteAllowance() public {
        token.mint(alice, 1000e18);
        vm.prank(alice);
        token.approve(bob, type(uint256).max);

        vm.prank(bob);
        token.burnFrom(alice, 500e18);
        assertEq(token.allowance(alice, bob), type(uint256).max);
        assertEq(token.balanceOf(alice), 500e18);
        assertEq(token.totalSupply(), 500e18);
    }

    // ─── Transfer Ownership ───
    function test_transferOwnership() public {
        token.transferOwnership(alice);
        assertEq(token.owner(), alice);
    }

    function test_transferOwnership_revert_nonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        token.transferOwnership(alice);
    }

    function test_transferOwnership_revert_toZero() public {
        vm.expectRevert();
        token.transferOwnership(zero);
    }

    function test_transferOwnership_newOwnerCanMint() public {
        token.transferOwnership(alice);
        vm.prank(alice);
        token.mint(bob, 100e18);
        assertEq(token.balanceOf(bob), 100e18);
    }

    function test_transferOwnership_oldOwnerCannotMint() public {
        token.transferOwnership(alice);
        vm.expectRevert();
        token.mint(bob, 100e18);
    }

    // ─── Nonces ───
    function test_nonces_initialZero() public view {
        assertEq(token.nonces(alice), 0);
    }

    // ════════════════════════════════════════════════════════════
    //  EVENT TESTS
    // ════════════════════════════════════════════════════════════

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    function test_event_transfer() public {
        token.mint(alice, 1000e18);
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Transfer(alice, bob, 200e18);
        token.transfer(bob, 200e18);
    }

    function test_event_mint() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(zero, alice, 1000e18);
        token.mint(alice, 1000e18);
    }

    function test_event_approve() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Approval(alice, bob, 500e18);
        token.approve(bob, 500e18);
    }

    // ════════════════════════════════════════════════════════════
    //  PERMIT (EIP-2612) TESTS
    // ════════════════════════════════════════════════════════════

    function _getPermitDigest(
        address _owner,
        address _spender,
        uint256 _value,
        uint256 _nonce,
        uint256 _deadline
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                0x6e71edae12b1b97f4d1f60370fea2543b90042d7b3d644eae9740da8db28d22a,
                _owner,
                _spender,
                _value,
                _nonce,
                _deadline
            )
        );
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    token.DOMAIN_SEPARATOR(),
                    structHash
                )
            );
    }

    function test_permit() public {
        uint256 value = 1000e18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(permitOwner);

        bytes32 digest = _getPermitDigest(
            permitOwner,
            bob,
            value,
            nonce,
            deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        token.permit(permitOwner, bob, value, deadline, v, r, s);
        assertEq(token.allowance(permitOwner, bob), value);
        assertEq(token.nonces(permitOwner), 1);
    }

    function test_permit_revert_expiredDeadline() public {
        uint256 value = 1000e18;
        uint256 deadline = block.timestamp - 1; // expired
        uint256 nonce = token.nonces(permitOwner);

        bytes32 digest = _getPermitDigest(
            permitOwner,
            bob,
            value,
            nonce,
            deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        vm.expectRevert();
        token.permit(permitOwner, bob, value, deadline, v, r, s);
    }

    function test_permit_revert_wrongSigner() public {
        uint256 value = 1000e18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(permitOwner);

        bytes32 digest = _getPermitDigest(
            permitOwner,
            bob,
            value,
            nonce,
            deadline
        );
        // Sign with wrong key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBEEF, digest);

        vm.expectRevert();
        token.permit(permitOwner, bob, value, deadline, v, r, s);
    }

    function test_permit_revert_replayAttack() public {
        uint256 value = 1000e18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(permitOwner);

        bytes32 digest = _getPermitDigest(
            permitOwner,
            bob,
            value,
            nonce,
            deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        token.permit(permitOwner, bob, value, deadline, v, r, s);

        // Replay should fail (nonce incremented)
        vm.expectRevert();
        token.permit(permitOwner, bob, value, deadline, v, r, s);
    }

    function test_permit_revert_zeroOwner() public {
        vm.expectRevert();
        token.permit(
            zero,
            bob,
            100,
            block.timestamp + 1,
            27,
            bytes32(0),
            bytes32(0)
        );
    }

    function test_permit_revert_zeroSpender() public {
        vm.expectRevert();
        token.permit(
            alice,
            zero,
            100,
            block.timestamp + 1,
            27,
            bytes32(0),
            bytes32(0)
        );
    }

    // ════════════════════════════════════════════════════════════
    //  VALIDATION / INVARIANT TESTS
    // ════════════════════════════════════════════════════════════

    function test_invariant_supplyEqualsSumOfBalances() public {
        token.mint(alice, 500e18);
        token.mint(bob, 300e18);
        token.mint(charlie, 200e18);

        vm.prank(alice);
        token.transfer(bob, 100e18);

        vm.prank(bob);
        token.burn(50e18);

        uint256 sum = token.balanceOf(alice) +
            token.balanceOf(bob) +
            token.balanceOf(charlie);
        assertEq(token.totalSupply(), sum);
    }

    function test_invariant_transferDoesNotCreateTokens() public {
        token.mint(alice, 1000e18);
        uint256 supplyBefore = token.totalSupply();

        vm.prank(alice);
        token.transfer(bob, 500e18);

        assertEq(token.totalSupply(), supplyBefore);
    }

    function test_invariant_burnReducesSupply() public {
        token.mint(alice, 1000e18);
        uint256 supplyBefore = token.totalSupply();

        vm.prank(alice);
        token.burn(300e18);

        assertEq(token.totalSupply(), supplyBefore - 300e18);
    }

    // ════════════════════════════════════════════════════════════
    //  CHAOS / EDGE CASE TESTS
    // ════════════════════════════════════════════════════════════

    function test_chaos_transferToSelf() public {
        token.mint(alice, 1000e18);
        vm.prank(alice);
        token.transfer(alice, 500e18);
        assertEq(token.balanceOf(alice), 1000e18);
        assertEq(token.totalSupply(), 1000e18);
    }

    function test_chaos_approveToSelf() public {
        vm.prank(alice);
        token.approve(alice, 100e18);
        assertEq(token.allowance(alice, alice), 100e18);
    }

    function test_chaos_transferFromSelf() public {
        token.mint(alice, 1000e18);
        vm.prank(alice);
        token.approve(alice, 500e18);
        vm.prank(alice);
        token.transferFrom(alice, bob, 200e18);
        assertEq(token.balanceOf(alice), 800e18);
        assertEq(token.balanceOf(bob), 200e18);
    }

    function test_chaos_mintMaxUint() public {
        // Mint a large amount (not max to avoid overflow in later ops)
        uint256 large = type(uint128).max;
        token.mint(alice, large);
        assertEq(token.balanceOf(alice), large);
        assertEq(token.totalSupply(), large);
    }

    function test_chaos_multipleApprovals() public {
        vm.startPrank(alice);
        token.approve(bob, 100e18);
        token.approve(charlie, 200e18);
        token.approve(bob, 50e18);
        vm.stopPrank();

        assertEq(token.allowance(alice, bob), 50e18);
        assertEq(token.allowance(alice, charlie), 200e18);
    }

    function test_chaos_burnZero() public {
        token.mint(alice, 100e18);
        vm.prank(alice);
        token.burn(0);
        assertEq(token.balanceOf(alice), 100e18);
    }

    function test_chaos_transferZero() public {
        vm.prank(alice);
        token.transfer(bob, 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_chaos_shortCalldata() public {
        // Call with < 4 bytes of calldata — should revert
        (bool ok, ) = address(token).call(hex"aabb");
        assertFalse(ok);
    }

    function test_chaos_unknownSelector() public {
        (bool ok, ) = address(token).call(
            abi.encodeWithSelector(bytes4(0xdeadbeef))
        );
        assertFalse(ok);
    }

    function test_chaos_emptyCalldata() public {
        (bool ok, ) = address(token).call("");
        assertFalse(ok);
    }

    // ════════════════════════════════════════════════════════════
    //  FUZZ TESTS
    // ════════════════════════════════════════════════════════════

    function testFuzz_mint(address to, uint256 amount) public {
        vm.assume(to != zero);
        vm.assume(amount < type(uint128).max);
        token.mint(to, amount);
        assertEq(token.balanceOf(to), amount);
        assertEq(token.totalSupply(), amount);
    }

    function testFuzz_transfer(uint256 mintAmt, uint256 sendAmt) public {
        vm.assume(mintAmt < type(uint128).max);
        vm.assume(sendAmt <= mintAmt);
        token.mint(alice, mintAmt);
        vm.prank(alice);
        token.transfer(bob, sendAmt);
        assertEq(token.balanceOf(alice), mintAmt - sendAmt);
        assertEq(token.balanceOf(bob), sendAmt);
    }

    function testFuzz_approve(address spender, uint256 amount) public {
        vm.assume(spender != zero);
        vm.prank(alice);
        token.approve(spender, amount);
        assertEq(token.allowance(alice, spender), amount);
    }

    function testFuzz_burn(uint256 mintAmt, uint256 burnAmt) public {
        vm.assume(mintAmt < type(uint128).max);
        vm.assume(burnAmt <= mintAmt);
        token.mint(alice, mintAmt);
        vm.prank(alice);
        token.burn(burnAmt);
        assertEq(token.balanceOf(alice), mintAmt - burnAmt);
        assertEq(token.totalSupply(), mintAmt - burnAmt);
    }

    // ════════════════════════════════════════════════════════════
    //  MONKEY TESTS — Random sequences of operations
    // ════════════════════════════════════════════════════════════

    function test_monkey_mintTransferBurnCycle() public {
        // Mint → Transfer → Burn → Check invariants
        token.mint(alice, 1000e18);
        token.mint(bob, 500e18);

        vm.prank(alice);
        token.transfer(bob, 200e18);

        vm.prank(bob);
        token.transfer(charlie, 100e18);

        vm.prank(charlie);
        token.burn(50e18);

        vm.prank(alice);
        token.burn(100e18);

        uint256 totalBal = token.balanceOf(alice) +
            token.balanceOf(bob) +
            token.balanceOf(charlie);
        assertEq(token.totalSupply(), totalBal);
        assertEq(token.totalSupply(), 1350e18); // 1500 - 50 - 100
    }

    function test_monkey_approveTransferFromBurnFrom() public {
        token.mint(alice, 1000e18);

        vm.prank(alice);
        token.approve(bob, 600e18);

        vm.prank(bob);
        token.transferFrom(alice, charlie, 200e18);

        vm.prank(alice);
        token.approve(charlie, 300e18);

        vm.prank(charlie);
        token.burnFrom(alice, 100e18);

        assertEq(token.balanceOf(alice), 700e18);
        assertEq(token.balanceOf(charlie), 200e18);
        assertEq(token.totalSupply(), 900e18);
        assertEq(token.allowance(alice, bob), 400e18);
        assertEq(token.allowance(alice, charlie), 200e18);
    }

    function test_monkey_ownershipTransferAndMint() public {
        token.transferOwnership(alice);

        // Old owner can't mint
        vm.expectRevert();
        token.mint(bob, 100e18);

        // New owner can
        vm.prank(alice);
        token.mint(bob, 100e18);
        assertEq(token.balanceOf(bob), 100e18);

        // Transfer again
        vm.prank(alice);
        token.transferOwnership(bob);

        vm.prank(bob);
        token.mint(charlie, 50e18);
        assertEq(token.balanceOf(charlie), 50e18);
    }
}
