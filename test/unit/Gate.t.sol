// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Gate} from "../../src/external/morpho/Gate.sol";
import {Test} from "forge-std/Test.sol";

contract GateTest is Test {
    address manager;
    address owner;

    Gate gate;

    function setUp() public {
        manager = vm.addr(0x0001);
        owner = vm.addr(0x0001);
        gate = new Gate(owner);
    }

    function test_Gate() public {
        vm.prank(owner);
        gate.setManager(manager);
        assertEq(gate.canReceiveAssets(manager), true);
        assertEq(gate.canReceiveShares(manager), true);
        assertEq(gate.canSendAssets(manager), true);
        assertEq(gate.canSendShares(manager), true);
    }

    function test_fuzz_Gate(address account) public {
        vm.assume(account != manager);
        vm.prank(owner);
        gate.setManager(manager);
        assertEq(gate.canReceiveAssets(account), false);
        assertEq(gate.canReceiveShares(account), false);
        assertEq(gate.canSendAssets(account), false);
        assertEq(gate.canSendShares(account), false);
    }
}
