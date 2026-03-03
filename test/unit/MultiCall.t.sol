// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MultiCall} from "../../src/MultiCall.sol";
import {Test} from "forge-std/Test.sol";

contract MultiCallTest is Test {
    address caller;

    MockERC20 internal token;
    MultiCall internal multicall;

    function setUp() public {
        caller = vm.addr(0x0001);
        multicall = new MultiCall(address(this));
        token = new MockERC20("Mock ERC20", "MERC20", 18);
    }

    function test_MultiCall() public {
        multicall.grantRole(keccak256("MULTICALLER_ROLE"), caller);
        address[] memory targets = new address[](8);
        bytes[] memory data = new bytes[](8);

        vm.prank(caller);
        multicall.multicall(targets, data);
    }

    function test_Revert_MultiCall() public {
        // ensure multicall reverts if any delegate call reverts
        token.mint(address(multicall), 1e18);
        multicall.grantRole(keccak256("MULTICALLER_ROLE"), caller);

        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);
        targets[0] = address(token);
        targets[1] = address(token);

        data[0] = abi.encodeWithSelector(IERC20.transfer.selector, caller, 1e18);
        data[1] = abi.encodeWithSelector(IERC20.transfer.selector, caller, 1e18);

        vm.prank(caller);
        vm.expectRevert();
        multicall.multicall(targets, data);

        vm.prank(caller);
        vm.expectRevert(MultiCall.ArrayLengthMismatch.selector);
        multicall.multicall(new address[](1), data);
    }

    function test_Revert_MultiCall_Unauthorized(address account) public {
        vm.assume(account != caller);
        address[] memory targets = new address[](8);
        bytes[] memory data = new bytes[](8);

        vm.prank(account);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        multicall.multicall(targets, data);
    }
}
