// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "../BaseTest.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {IERC20Errors} from "openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {IRestrictedRegistry} from "../../src/interface/IRestrictedRegistry.sol";
import {SpokeERC20Restricted} from "../../src/external/chainlink/SpokeERC20Restricted.sol";

contract SpokeERC20RestrictedTest is BaseTest {
    SpokeERC20Restricted token;

    function setUp() public override {
        super.setUp();
        token = new SpokeERC20Restricted("SpokeToken", "STK", owner);

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

        // check restricted accounts
        vm.prank(restricter);
        token.setIsRestricted(user, true);

        vm.prank(user);
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector);
        token.burn(1e18);

        vm.prank(minter);
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector);
        token.burn(user, 1e18);

        vm.prank(minter);
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector);
        token.burnFrom(user, 1e18);

        vm.prank(restricter);
        token.setIsRestricted(user, false);

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

    function test_Revert_SetIsRestricted() public {
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        token.setIsRestricted(user, true);
    }

    function test_SetIsRestricted() public {
        vm.prank(restricter);
        token.setIsRestricted(user, true);
        assertEq(token.isRestricted(user), true);

        vm.prank(restricter);
        token.setIsRestricted(user, false);
        assertEq(token.isRestricted(user), false);
    }

    function test_Revert_Restricted_Transfers() public {
        // forge-lint: disable-start(erc20-unchecked-transfer)
        address user2 = vm.addr(0xC001);

        vm.prank(restricter);
        token.setIsRestricted(user, true);

        // can't call transfer from a restricted account
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector);
        vm.prank(user);
        token.transfer(address(this), 1000e18);

        // can't transfer assets to a restricted account
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector);
        token.transfer(user, 1000e18);

        // can't call transferFrom assets from a restricted account
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector);
        vm.prank(user);
        token.transferFrom(user2, user2, 1000e18);

        // can't transferFrom assets from a non-restricted account
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector);
        vm.prank(user2);
        token.transferFrom(user, user2, 1000e18);

        // can't transferFrom assets to a non-restricted account
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector);
        vm.prank(user2);
        token.transferFrom(user2, user, 1000e18);
        // forge-lint: disable-end(erc20-unchecked-transfer)
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
