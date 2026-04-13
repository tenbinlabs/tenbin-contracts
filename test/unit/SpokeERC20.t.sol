// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "../BaseTest.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {IERC20Errors} from "openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {SpokeERC20} from "../../src/external/chainlink/SpokeERC20.sol";

contract SpokeERC20Test is BaseTest {
    SpokeERC20 token;

    function setUp() public override {
        super.setUp();
        token = new SpokeERC20("SpokeToken", "STK", owner);

        vm.startPrank(owner);
        token.grantRole(token.MINTER_BURNER_ROLE(), minter);
        token.grantRole(RESTRICTER_ROLE, restricter);
        vm.stopPrank();
    }

    function test_Deployment() public view {
        assertEq(token.symbol(), "STK", "23");
        assertEq(token.name(), "SpokeToken", "wew");
        assertTrue(token.hasRole(DEFAULT_ADMIN_ROLE, owner));
        assertTrue(token.hasRole(token.MINTER_BURNER_ROLE(), minter));
        assertTrue(token.hasRole(RESTRICTER_ROLE, restricter));
    }

    function test_Revert_Mint_SpokeERC20() public {
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        token.mint(user, 1e18);
    }

    function test_Mint() public {
        vm.prank(minter);
        token.mint(user, 1e18);

        assertEq(token.balanceOf(user), 1e18);
        assertEq(token.totalSupply(), 1e18);
    }

    function test_Revert_Burn() public {
        // check access
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        token.burn(user, 1e18);

        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        token.burnFrom(user, 1e18);

        // check correct allowance
        vm.startPrank(minter);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientAllowance.selector);
        token.burn(user, 1e18);

        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientAllowance.selector);
        token.burnFrom(user, 1e18);

        vm.stopPrank();
    }

    function test_Burn() public {
        vm.prank(minter);
        token.mint(user, 3e18);

        vm.startPrank(user);
        token.approve(minter, 2e18);

        // burn with amount
        token.burn(1e18);
        vm.stopPrank();

        assertEq(token.balanceOf(user), 2e18);
        assertEq(token.totalSupply(), 2e18);

        vm.startPrank(minter);
        // burn with account
        token.burn(user, 1e18);
        assertEq(token.balanceOf(user), 1e18);
        assertEq(token.totalSupply(), 1e18);

        // burn from account
        token.burnFrom(user, 1e18);
        assertEq(token.balanceOf(user), 0);
        assertEq(token.totalSupply(), 0);
        vm.stopPrank();
    }

    function test_transfer() public {
        address user2 = vm.addr(0xC001);
        vm.prank(minter);
        token.mint(user, 1e18);

        vm.startPrank(user);
        bool result = token.transfer(user2, 1e18);

        assertTrue(result);
        assertEq(token.balanceOf(user), 0);
        assertEq(token.balanceOf(user2), 1e18);
    }

    function test_transferFrom() public {
        address user2 = vm.addr(0xC001);
        vm.prank(minter);
        token.mint(user, 1e18);

        vm.startPrank(user);
        token.approve(user, 1e18);
        bool result = token.transferFrom(user, user2, 1e18);
        assertTrue(result);

        assertEq(token.balanceOf(user), 0);
        assertEq(token.balanceOf(user2), 1e18);
    }
}
