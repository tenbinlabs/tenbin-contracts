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
        assertTrue(revenueModule.hasRole(revenueModule.REVENUE_KEEPER_ROLE(), revenueKeeper));
    }

    function test_RevertDeploy_If_ZeroAddresses() public {
        vm.expectRevert(IRevenueModule.NonZeroAddress.selector);
        new RevenueModule(address(0), address(staking), owner, address(controller), address(asset), address(multisig));

        vm.expectRevert(IRevenueModule.NonZeroAddress.selector);
        new RevenueModule(address(manager), address(0), owner, address(controller), address(asset), address(multisig));

        vm.expectRevert(IRevenueModule.NonZeroAddress.selector);
        new RevenueModule(
            address(manager), address(staking), address(0), address(controller), address(asset), address(multisig)
        );

        vm.expectRevert(IRevenueModule.NonZeroAddress.selector);
        new RevenueModule(address(manager), address(staking), owner, address(0), address(asset), address(multisig));

        vm.expectRevert(IRevenueModule.NonZeroAddress.selector);
        new RevenueModule(address(manager), address(staking), owner, address(controller), address(0), address(multisig));

        vm.expectRevert(IRevenueModule.NonZeroAddress.selector);
        new RevenueModule(address(manager), address(staking), owner, address(controller), address(asset), address(0));
    }

    function test_PullRevenue_Success() public {
        uint256 amount = 1e18 - 1;
        vm.startPrank(curator);
        collateral.mint(address(manager), amount);
        manager.deposit(address(collateral), amount, 0);

        collateral.mint(address(vault), amount);
        manager.withdraw(address(collateral), amount, UINT256_MAX);
        vm.stopPrank();

        vm.startPrank(revenueKeeper);
        revenueModule.collect(address(collateral), manager.getRevenue(address(collateral)));
        vm.stopPrank();
    }

    function test_Revert_PullRevenue() public {
        vm.startPrank(revenueKeeper);
        vm.expectRevert(IRevenueModule.InsufficientRevenue.selector);
        revenueModule.collect(address(collateral), 1e18);
        vm.stopPrank();

        uint256 amount = 1e18 - 1;
        vm.startPrank(curator);
        collateral.mint(address(manager), amount);
        manager.deposit(address(collateral), amount, 0);

        collateral.mint(address(vault), amount);
        manager.withdraw(address(collateral), amount, UINT256_MAX);
        vm.stopPrank();

        vm.startPrank(revenueKeeper);
        vm.expectRevert(IRevenueModule.InsufficientRevenue.selector);
        revenueModule.collect(address(collateral), amount * 2);
        vm.stopPrank();
    }

    function test_PullRevenue_RevertsIfNotAuthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                revenueModule.REVENUE_KEEPER_ROLE()
            )
        );
        revenueModule.collect(address(collateral), 1e18);
    }

    function test_WithdrawToMultisig() public {
        collateral.mint(address(manager), 2000e18);

        // deposit, simulate earning interest, and withdraw
        vm.startPrank(curator);
        manager.deposit(address(collateral), 2000e18, 0);
        collateral.mint(address(vault), 1000e18);
        manager.withdraw(address(collateral), 1000e18, UINT256_MAX);
        vm.stopPrank();

        // collect revenue
        vm.startPrank(revenueKeeper);
        revenueModule.collect(address(collateral), manager.getRevenue(address(collateral)));
        vm.stopPrank();

        // assert revenue amount is correct
        uint256 revenue = collateral.balanceOf(address(revenueModule));
        assertApproxEqAbs(revenue, 1000e18, VAULT_TOLERANCE);

        vm.expectEmit();
        emit IRevenueModule.WithdrawToMultisig(address(collateral), revenue);

        // withdraw to multisig
        vm.prank(revenueKeeper);
        revenueModule.withdrawToMultisig(address(collateral), revenue);

        assertApproxEqAbs(collateral.balanceOf(multisig), revenue, VAULT_TOLERANCE);
    }

    function test_WithdrawToManager() public {
        collateral.mint(address(manager), 2000e18);

        // deposit, simulate earning interest, and withdraw
        vm.startPrank(curator);
        manager.deposit(address(collateral), 2000e18, 0);
        collateral.mint(address(vault), 1000e18);
        manager.withdraw(address(collateral), 1000e18, UINT256_MAX);
        vm.stopPrank();

        // collect revenue
        vm.startPrank(revenueKeeper);
        revenueModule.collect(address(collateral), manager.getRevenue(address(collateral)));
        vm.stopPrank();

        // assert revenue amount is correct
        uint256 revenue = collateral.balanceOf(address(revenueModule));
        assertApproxEqAbs(revenue, 1000e18, VAULT_TOLERANCE);

        vm.expectEmit();
        emit IRevenueModule.WithdrawToManager(address(collateral), revenue);

        // withdraw to manager
        vm.prank(revenueKeeper);
        revenueModule.withdrawToManager(address(collateral), revenue);

        assertApproxEqAbs(collateral.balanceOf(address(manager)), revenue, VAULT_TOLERANCE);
    }

    function test_Reward_Success() public {
        uint256 amount = 1e18;

        // Simulate Mint Order happened in controller
        mintAsset(address(revenueModule), amount);

        vm.startPrank(revenueKeeper);
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
        vm.startPrank(revenueKeeper);
        vm.expectRevert();
        revenueModule.withdrawToMultisig(address(collateral), 1e18);
        vm.stopPrank();
    }

    function test_RevertIf_ZeroAmount() public {
        vm.startPrank(revenueKeeper);
        vm.expectRevert(IRevenueModule.InvalidAmount.selector);
        revenueModule.withdrawToMultisig(address(collateral), 0);
        vm.stopPrank();
    }

    function test_SetControllerApproval() public {
        uint256 amount = 1e18;
        vm.prank(revenueKeeper);
        revenueModule.setControllerApproval(address(collateral), amount);

        assertEq(collateral.allowance(address(revenueModule), address(controller)), amount);

        // Allowance is always latest amount approved
        vm.prank(revenueKeeper);
        revenueModule.setControllerApproval(address(collateral), amount - 1);

        assertEq(collateral.allowance(address(revenueModule), address(controller)), amount - 1);
    }

    function test_Revert_SetControllerApproval() public {
        uint256 amount = 1e18;
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        revenueModule.setControllerApproval(address(collateral), amount);

        vm.prank(revenueKeeper);
        vm.expectRevert(IRevenueModule.NonZeroAddress.selector);
        revenueModule.setControllerApproval(address(0), amount);
    }

    function test_Revert_ZeroAddress() public {
        vm.prank(revenueKeeper);
        vm.expectRevert(IRevenueModule.NonZeroAddress.selector);
        revenueModule.collect(address(0), 1e18);

        vm.prank(revenueKeeper);
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

    function test_ClaimMorphoRewards() public {
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = keccak256("p0");
        proof[1] = keccak256("p1");

        assertGt(collateral.balanceOf(address(distributor)), 1e18);

        vm.prank(revenueKeeper);
        revenueModule.claimMorphoRewards(address(distributor), address(collateral), 1e18, proof);

        assertEq(collateral.balanceOf(address(revenueModule)), 1e18);
    }
}
