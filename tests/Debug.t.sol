// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

contract DebugTest is Test {
    address token;

    function setUp() public {
        string memory bytecodeHex = vm.readFile("bytecode.txt");
        bytes memory bytecode = vm.parseBytes(bytecodeHex);

        console.log("Bytecode length:", bytecode.length);

        address deployed;
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(deployed != address(0), "Deploy failed");
        token = deployed;

        // Check deployed code size
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(deployed)
        }
        console.log("Deployed code size:", codeSize);
    }

    function test_debug_rawCall_totalSupply() public {
        // totalSupply() = 0x18160ddd
        (bool ok, bytes memory ret) = token.call(
            abi.encodeWithSelector(0x18160ddd)
        );
        console.log("totalSupply ok:", ok);
        console.log("totalSupply ret length:", ret.length);
        if (ret.length >= 32) {
            uint256 val = abi.decode(ret, (uint256));
            console.log("totalSupply value:", val);
        }
    }

    function test_debug_rawCall_mint() public {
        // mint(address,uint256) = 0x40c10f19
        address to = address(0xBEEF);
        uint256 amount = 1000;
        (bool ok, bytes memory ret) = token.call(
            abi.encodeWithSelector(0x40c10f19, to, amount)
        );
        console.log("mint ok:", ok);
        console.log("mint ret length:", ret.length);
        if (!ok) {
            console.log("mint revert data length:", ret.length);
            if (ret.length > 0) {
                console.logBytes(ret);
            }
        }
    }

    function test_debug_rawCall_approve() public {
        // approve(address,uint256) = 0x095ea7b3
        address spender = address(0xBEEF);
        uint256 amount = 1000;
        (bool ok, bytes memory ret) = token.call(
            abi.encodeWithSelector(0x095ea7b3, spender, amount)
        );
        console.log("approve ok:", ok);
        if (!ok) {
            console.log("approve revert data length:", ret.length);
            if (ret.length > 0) {
                console.logBytes(ret);
            }
        }
    }

    function test_debug_rawCall_owner() public {
        // owner() = 0x8da5cb5b
        (bool ok, bytes memory ret) = token.call(
            abi.encodeWithSelector(0x8da5cb5b)
        );
        console.log("owner ok:", ok);
        if (ok && ret.length >= 32) {
            address val = abi.decode(ret, (address));
            console.log("owner:", val);
            console.log("this:", address(this));
        }
    }
}
