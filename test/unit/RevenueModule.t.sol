// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {IController} from "src/interface/IController.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IRevenueModule} from "src/interface/IRevenueModule.sol";
import {RevenueModule} from "src/RevenueModule.sol";

contract RevenueModuleTest is BaseTest {
    function test_SetUp() public view {
        assertEq(address(manager), revenueModule.manager());
        assertEq(address(staking), revenueModule.staking());
        assertEq(address(asset), revenueModule.asset());
        assertEq(address(controller), revenueModule.controller());
        assertTrue(revenueModule.hasRole(revenueModule.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(revenueModule.hasRole(revenueModule.ADMIN_ROLE(), admin));
        assertTrue(revenueModule.hasRole(revenueModule.KEEPER_ROLE(), keeper));
        assertTrue(revenueModule.hasRole(revenueModule.MULTISIG_ROLE(), multisig));
    }

    function test_RevertDeploy_If_ZeroAddresses() public {
        vm.expectRevert(IRevenueModule.NonZeroAddress.selector);
        new RevenueModule(address(0), address(staking), owner, address(controller), address(asset));

        vm.expectRevert(IRevenueModule.NonZeroAddress.selector);
        new RevenueModule(address(manager), address(0), owner, address(controller), address(asset));

        vm.expectRevert(IRevenueModule.NonZeroAddress.selector);
        new RevenueModule(address(manager), address(staking), address(0), address(controller), address(asset));

        vm.expectRevert(IRevenueModule.NonZeroAddress.selector);
        new RevenueModule(address(manager), address(staking), owner, address(0), address(asset));

        vm.expectRevert(IRevenueModule.NonZeroAddress.selector);
        new RevenueModule(address(manager), address(staking), owner, address(controller), address(0));
    }

    function test_PullRevenue_Success() public {
        uint256 amount = 1e18;
        pullFunds(amount);
    }

    function test_PullRevenue_RevertsIfNoRevenue() public {
        vm.startPrank(keeper);
        vm.expectRevert(IRevenueModule.InsufficientRevenue.selector);
        revenueModule.pull(address(collateral));
        vm.stopPrank();
    }

    function test_PullRevenue_RevertsIfNotCollector() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), revenueModule.KEEPER_ROLE()
            )
        );
        revenueModule.pull(address(collateral));
    }

    function test_WithdrawToMultisig_Success() public {
        uint256 amount = 10e18;
        pullFunds(amount);
        vm.startPrank(multisig);
        vm.expectEmit(true, false, false, true);
        emit IRevenueModule.WithdrawToMultisig(address(collateral), amount);
        revenueModule.withdrawToMultisig(address(collateral), amount);
        vm.stopPrank();
        assertEq(collateral.balanceOf(multisig), amount);
    }

    function test_WithdrawToManager_Success() public {
        uint256 amount = 5e18;
        pullFunds(amount);
        vm.startPrank(keeper);
        emit IRevenueModule.WithdrawToManager(address(collateral), amount);
        revenueModule.withdrawToManager(address(collateral), amount);
        vm.stopPrank();
        assertEq(collateral.balanceOf(address(manager)), amount);
    }

    function test_Reward_Success() public {
        uint256 amount = 1e18;

        // Simulate Mint Order happened in controller
        mintAsset(address(revenueModule), amount);

        vm.startPrank(keeper);
        vm.expectEmit();
        emit IERC20.Approval(address(revenueModule), address(staking), amount);
        emit IRevenueModule.RewardSent(amount);
        revenueModule.reward(amount);
        vm.stopPrank();
        assertEq(asset.balanceOf(address(staking)), amount);
        assertEq(asset.balanceOf(address(revenueModule)), 0);
    }

    function test_RevertIf_InvalidCaller() public {
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        revenueModule.withdrawToMultisig(address(collateral), 1e18);
        vm.stopPrank();
    }

    function test_RevertIf_InsufficientBalance() public {
        vm.startPrank(multisig);
        vm.expectRevert();
        revenueModule.withdrawToMultisig(address(collateral), 1e18);
        vm.stopPrank();
    }

    function test_RevertIf_ZeroAmount() public {
        vm.startPrank(multisig);
        vm.expectRevert(IRevenueModule.InvalidAmount.selector);
        revenueModule.withdrawToMultisig(address(collateral), 0);
        vm.stopPrank();
    }

    function test_IncreaseControllerApproval() public {
        uint256 amount = 1e18;
        vm.prank(admin);
        revenueModule.increaseControllerApproval(address(collateral), amount);

        assertEq(collateral.allowance(address(revenueModule), address(controller)), amount);
    }

    function test_Revert_IncreaseControllerApproval() public {
        uint256 amount = 1e18;
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        revenueModule.increaseControllerApproval(address(collateral), amount);

        vm.prank(admin);
        vm.expectRevert(IRevenueModule.NonZeroAddress.selector);
        revenueModule.increaseControllerApproval(address(0), amount);
    }

    function test_Revert_ZeroAddress() public {
        vm.prank(keeper);
        vm.expectRevert(IRevenueModule.NonZeroAddress.selector);
        revenueModule.pull(address(0));

        vm.prank(keeper);
        vm.expectRevert(IRevenueModule.NonZeroAddress.selector);
        revenueModule.withdrawToManager(address(0), 1);
    }

    function test_DelegateSigner() public {
        allowSigner(payer);
        vm.prank(admin);
        vm.expectEmit();
        emit IController.DelegateStatusChanged(address(revenueModule), payer, true);
        revenueModule.delegateSigner(payer, true);

        assertTrue(controller.delegates(address(revenueModule), payer));
    }

    function test_Revert_DelegateSigner() public {
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        revenueModule.delegateSigner(payer, true);

        assertFalse(controller.delegates(payer, address(revenueModule)));
    }
}
