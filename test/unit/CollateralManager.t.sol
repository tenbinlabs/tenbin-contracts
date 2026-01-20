// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {CollateralManager} from "src/CollateralManager.sol";
import {CollateralManagerPause} from "test/mocks/CollateralManagerPause.sol";
import {Controller} from "src/Controller.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {ERC4626} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {IAggregationRouterV6} from "src/external/1inch/IAggregationRouterV6.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {ICollateralManager} from "src/interface/ICollateralManager.sol";
import {IERC20Errors} from "lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {Initializable} from "lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {ISwapModule} from "src/interface/ISwapModule.sol";
import {
    Mock1InchRouterWithInsufficientAmountSent,
    Mock1InchRouterWithExtraAmountSent
} from "test/mocks/Mock1InchRouter.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockERC4626} from "test/mocks/MockERC4626.sol";
import {MockReentrantERC20} from "test/mocks/MockReentrantERC20.sol";
import {MockReentrantERC4626} from "test/mocks/MockReentrantERC4626.sol";
import {ReentrancyGuardTransient} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol";

contract CollateralManagerTest is BaseTest {
    function test_CollateralManager_Initialize() public view {
        assertEq(manager.controller(), address(controller));
        assertEq(manager.hasRole(DEFAULT_ADMIN_ROLE, owner), true);
    }

    function test_Revert_CollateralManager_Initialize() public {
        CollateralManager managerImplementation = new CollateralManager();
        // cannot initialize again
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        manager.initialize(address(controller), address(this));

        // cannot initialize implementation
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        managerImplementation.initialize(address(controller), address(this));

        // test failed initialization cases
        bytes memory data = abi.encodeWithSelector(CollateralManager.initialize.selector, address(0), address(this));
        vm.expectRevert(ICollateralManager.NonZeroAddress.selector);
        CollateralManager(address(new ERC1967Proxy(address(managerImplementation), data)));
    }

    function test_Revert_CollateralManager_UpgradeToAndCall() public {
        address newImplementation = address(new CollateralManagerPause());
        address badImplementation = address(new MockERC20("mock", "mock", 18));

        // revert if not default admin role
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        manager.upgradeToAndCall(newImplementation, new bytes(0));

        // revert if implementation is not UUPS
        vm.expectPartialRevert(ERC1967Utils.ERC1967InvalidImplementation.selector);
        vm.prank(owner);
        manager.upgradeToAndCall(badImplementation, new bytes(0));
    }

    function test_CollateralManager_UpgradeToAndCall() public {
        address newImplementation = address(new CollateralManagerPause());
        vm.prank(owner);
        manager.upgradeToAndCall(newImplementation, new bytes(0));

        // check implementation slot to ensure new implementation is correct
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        assertEq(abi.encode(vm.load(address(manager), slot)), abi.encode(newImplementation));

        // ensure roles are still valid after upgrade
        assertEq(manager.hasRole(DEFAULT_ADMIN_ROLE, owner), true);
        assertEq(manager.hasRole(ADMIN_ROLE, admin), true);
        assertEq(manager.hasRole(CURATOR_ROLE, curator), true);
        assertEq(manager.hasRole(REBALANCER_ROLE, rebalancer), true);
        assertEq(manager.hasRole(GATEKEEPER_ROLE, gatekeeper), true);
        assertEq(manager.hasRole(CAP_ADJUSTER_ROLE, capAdjuster), true);

        // expect all functions to revert based on the new implementation
        vm.expectRevert(CollateralManagerPause.ContractPaused.selector);
        manager.getRevenue(address(0));
        vm.expectRevert(CollateralManagerPause.ContractPaused.selector);
        manager.deposit(address(0), uint256(0), 0);
        vm.expectRevert(CollateralManagerPause.ContractPaused.selector);
        manager.withdraw(address(0), uint256(0), UINT256_MAX);
        vm.expectRevert(CollateralManagerPause.ContractPaused.selector);
        manager.withdrawRevenue(address(0), uint256(0));
        vm.expectRevert(CollateralManagerPause.ContractPaused.selector);
        manager.rebalance(address(0), uint256(0));
        vm.expectRevert(CollateralManagerPause.ContractPaused.selector);
        manager.swap(new bytes(0), new bytes(0));
        vm.expectRevert(CollateralManagerPause.ContractPaused.selector);
        manager.convertRevenue(address(0), uint256(0));

        // upgrade back to original implementation
        newImplementation = address(new CollateralManager());
        vm.prank(owner);
        manager.upgradeToAndCall(newImplementation, new bytes(0));

        // check implementation slot to ensure new implementation is correct
        slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        assertEq(abi.encode(vm.load(address(manager), slot)), abi.encode(newImplementation));

        // check some functions return correct values
        assertEq(manager.getRevenue(address(collateral)), 0);
    }

    function test_Deposit_Withdraw_Revenue() public {
        // send tokens to collateral manager
        collateral.mint(address(manager), 10000e6);
        // deposit into underlying
        vm.prank(curator);
        manager.deposit(address(collateral), 10000e6, 0);
        assertEq(manager.vaults(address(collateral)).totalAssets(), 10000e6);
        // simulate earning interest
        collateral.mint(address(vault), 1000e6);
        // withdraw from underlying
        vm.prank(curator);
        manager.withdraw(address(collateral), 10000e6, UINT256_MAX);
        assertEq(manager.vaults(address(collateral)).totalAssets(), 1000e6);
        // get revenue
        assertApproxEqAbs(manager.getRevenue(address(collateral)), 1000e6, VAULT_TOLERANCE);
    }

    function test_Revert_AccessControl() public {
        address user = vm.addr(0xFFFF);
        vm.startPrank(user);

        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        manager.addCollateral(address(0), address(0));

        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        manager.removeCollateral(address(0));

        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        manager.redeemLegacyShares(ERC4626(address(0)), 0);

        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        manager.deposit(address(0), 0, 0);

        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        manager.withdraw(address(0), 0, UINT256_MAX);

        vm.expectPartialRevert(ICollateralManager.OnlyRevenueModule.selector);
        manager.withdrawRevenue(address(0), 0);

        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        manager.rebalance(address(0), 0);

        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        manager.swap(new bytes(0), new bytes(0));

        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        manager.setPauseStatus(ICollateralManager.ManagerPauseStatus.FMLPause);

        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        manager.setMinSwapPrice(address(0), address(0), 0);

        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        manager.setSwapCap(address(0), 0);
    }

    function test_Revert_FMLPause() public {
        vm.prank(gatekeeper);
        manager.setPauseStatus(ICollateralManager.ManagerPauseStatus.FMLPause);

        vm.expectRevert(ICollateralManager.FMLPause.selector);
        manager.deposit(address(0), 0, 0);

        vm.expectRevert(ICollateralManager.FMLPause.selector);
        manager.withdraw(address(0), 0, UINT256_MAX);

        vm.expectRevert(ICollateralManager.FMLPause.selector);
        manager.withdrawRevenue(address(0), 0);

        vm.expectRevert(ICollateralManager.FMLPause.selector);
        manager.rebalance(address(0), 0);

        vm.expectRevert(ICollateralManager.FMLPause.selector);
        manager.swap(new bytes(0), new bytes(0));
    }

    function test_Revert_GetRevenue() public {
        vm.expectRevert();
        manager.getRevenue(address(0));
    }

    function test_GetRevenue() public {
        assertEq(manager.getRevenue(address(collateral)), 0);

        // deposit
        collateral.mint(address(manager), 10000e18 * 2);
        vm.prank(curator);
        manager.deposit(address(collateral), 10000e18, 0);

        // assert no revenue because lastTotalAssets == vault total assets
        assertEq(manager.lastTotalAssets(address(collateral)), vault.totalAssets());
        assertApproxEqAbs(manager.getRevenue(address(collateral)), 0, VAULT_TOLERANCE);

        // mock increased asset amount
        collateral.mint(address(vault), 10000e6);

        // ensure revenue calculated correctly
        assertApproxEqAbs(manager.getRevenue(address(collateral)), 10000e6, VAULT_TOLERANCE);

        // make new deposit so pending Revenue its updated
        vm.prank(curator);
        manager.deposit(address(collateral), 10000e18, 0);

        // mock decreased assets inside the vault
        collateral.burn(address(vault), 10000e6);

        // assert no revenue
        assertGt(manager.lastTotalAssets(address(collateral)), vault.totalAssets());
        assertApproxEqAbs(manager.getRevenue(address(collateral)), 0, VAULT_TOLERANCE);
    }

    function test_GetRevenue_NegativeTotalValue() public {
        vm.startPrank(curator);
        collateral.mint(address(manager), 10000e6);
        manager.deposit(address(collateral), 10000e6, 0);
        assertEq(manager.getRevenue(address(collateral)), 0);

        collateral.mint(address(vault), 10000e6);
        assertApproxEqAbs(manager.getRevenue(address(collateral)), 10000e6, VAULT_TOLERANCE);

        collateral.mint(address(manager), 10000e6);
        manager.deposit(address(collateral), 10000e6, 0);
        assertApproxEqAbs(manager.getRevenue(address(collateral)), 10000e6, VAULT_TOLERANCE);

        // simulate a loss in the vault by burning some tokens
        collateral.burn(address(vault), 5000e6);
        manager.withdraw(address(collateral), 5000e6, UINT256_MAX);

        // revenue decreases when a loss is incurred
        assertApproxEqAbs(manager.getRevenue(address(collateral)), 5000e6, VAULT_TOLERANCE);
    }

    function test_GetVaultAssets() public {
        // assets in collateral manager are NOT included in vault assets
        collateral.mint(address(manager), 1000e18);
        assertEq(manager.getVaultAssets(address(collateral)), 0);

        // assets in vault are included in assets
        vm.prank(curator);
        manager.deposit(address(collateral), 1000e18, 0);
        assertApproxEqAbs(manager.getVaultAssets(address(collateral)), 1000e18, VAULT_TOLERANCE);

        // assets in collateral manager are NOT included in vault assets
        collateral.mint(address(manager), 1000e18);
        assertApproxEqAbs(manager.getVaultAssets(address(collateral)), 1000e18, VAULT_TOLERANCE);

        // interest is included in calculation
        collateral.mint(address(vault), 1000e18);
        assertApproxEqAbs(manager.getVaultAssets(address(collateral)), 2000e18, VAULT_TOLERANCE);

        // deposited amount results in correct calculation
        vm.prank(curator);
        manager.deposit(address(collateral), 1000e18, 0);
        assertApproxEqAbs(manager.getVaultAssets(address(collateral)), 3000e18, VAULT_TOLERANCE);

        // simulate earning more interest
        collateral.mint(address(vault), 1000e18);
        assertApproxEqAbs(manager.getVaultAssets(address(collateral)), 4000e18, VAULT_TOLERANCE);

        // additional assets in collateral manager are not included in vault assets
        collateral.mint(address(manager), 1000e18);
        assertApproxEqAbs(manager.getVaultAssets(address(collateral)), 4000e18, VAULT_TOLERANCE);
    }

    function test_Revert_GetAssets() public {
        vm.expectRevert(ICollateralManager.CollateralNotSupported.selector);
        manager.getVaultAssets(address(this));
    }

    function test_Revert_SetPauseStatus() public {
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        manager.setPauseStatus(ICollateralManager.ManagerPauseStatus.FMLPause);
    }

    function test_SetPauseStatus() public {
        vm.startPrank(gatekeeper);
        vm.expectEmit();
        emit ICollateralManager.PauseStatusChanged(ICollateralManager.ManagerPauseStatus.FMLPause);
        manager.setPauseStatus(ICollateralManager.ManagerPauseStatus.FMLPause);
        assertTrue(manager.pauseStatus() == ICollateralManager.ManagerPauseStatus.FMLPause);

        vm.expectEmit();
        emit ICollateralManager.PauseStatusChanged(ICollateralManager.ManagerPauseStatus.None);
        manager.setPauseStatus(ICollateralManager.ManagerPauseStatus.None);
        assertTrue(manager.pauseStatus() == ICollateralManager.ManagerPauseStatus.None);
    }

    function test_Revert_AddCollateral() public {
        vm.startPrank(owner);
        vm.expectRevert(ICollateralManager.NonZeroAddress.selector);
        manager.addCollateral(address(0), address(vault));

        vm.expectRevert(ICollateralManager.NonZeroAddress.selector);
        manager.addCollateral(address(collateral), address(0));

        vm.expectRevert(ICollateralManager.CollateralAlreadySupported.selector);
        manager.addCollateral(address(collateral), address(vault));

        vm.expectRevert(ICollateralManager.IncompatibleCollateralVault.selector);
        manager.addCollateral(address(collateral2), address(vault));
    }

    function test_AddCollateral() public {
        // create new vault with existing value
        MockERC20 newCollateral = new MockERC20("Mock Collateral", "MCLT", 18);
        MockERC4626 newVault = new MockERC4626("Mock Vault", "MVLT", newCollateral);
        newCollateral.mint(address(newVault), 1000e18);

        vm.startPrank(owner);
        vm.expectEmit();
        emit ICollateralManager.CollateralAdded(address(newCollateral), address(newVault));
        manager.addCollateral(address(newCollateral), address(newVault));
        assertEq(address(manager.vaults(address(newCollateral))), address(newVault));
        assertEq(manager.pendingRevenue(address(newCollateral)), 0);
    }

    function test_Revert_RemoveCollateral() public {
        // only owner can call this function
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        manager.removeCollateral(address(collateral));

        /// cannot remove a collateral if there is no collateral set
        vm.prank(owner);
        vm.expectRevert(ICollateralManager.CollateralNotSupported.selector);
        manager.removeCollateral(address(0));
    }

    function test_RemoveCollateral() public {
        vm.prank(owner);
        vm.expectEmit();
        emit ICollateralManager.CollateralRemoved(address(collateral), address(vault));
        manager.removeCollateral(address(collateral));
        assertEq(manager.lastTotalAssets(address(collateral)), 0);
        assertEq(address(manager.vaults(address(collateral))), address(0));
    }

    function test_Revert_RedeemLegacyShares() public {
        // only owner can call this function
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        manager.redeemLegacyShares(vault, 0);

        // can't redeem shares for a vault that is currently being used
        vm.prank(owner);
        vm.expectRevert(ICollateralManager.CollateralAlreadySupported.selector);
        manager.redeemLegacyShares(vault, 0);
    }

    function test_RedeemLegacyShares() public {
        // deposit collateral into vault
        collateral.mint(address(manager), 1000e6);
        vm.prank(curator);
        manager.deposit(address(collateral), 1000e6, 0);

        // simulate earning interest
        collateral.mint(address(vault), 1000e6);
        assertApproxEqAbs(manager.getRevenue(address(collateral)), 1000e6, VAULT_TOLERANCE);

        // remove collateral vault
        vm.prank(owner);
        manager.removeCollateral(address(collateral));
        assertEq(manager.lastTotalAssets(address(collateral)), 0);

        // redeem legacy shares
        vm.expectEmit();
        emit ICollateralManager.LegacySharesRedeemed(address(vault), 500e6);
        vm.prank(owner);
        manager.redeemLegacyShares(vault, 500e6);
        assertEq(vault.balanceOf(address(manager)), 500e6);
        assertApproxEqAbs(collateral.balanceOf(address(manager)), 1000e6, VAULT_TOLERANCE);

        // redeem legacy shares again
        vm.expectEmit();
        emit ICollateralManager.LegacySharesRedeemed(address(vault), 500e6);
        vm.prank(owner);
        manager.redeemLegacyShares(vault, 500e6);
        assertEq(vault.balanceOf(address(manager)), 0);
        assertApproxEqAbs(collateral.balanceOf(address(manager)), 2000e6, VAULT_TOLERANCE);
    }

    function test_Revert_Deposit() public {
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        manager.deposit(address(collateral), 1000e6, 0);

        vm.startPrank(curator);
        vm.expectRevert(ICollateralManager.CollateralNotSupported.selector);
        manager.deposit(address(0), 1000e6, 0);

        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        manager.deposit(address(collateral), 1000e6, 0);

        // revert if min shares too high
        collateral.mint(address(manager), 2000e6);
        manager.deposit(address(collateral), 1000e6, 0);
        vm.expectRevert(ICollateralManager.InsufficientSharesReceived.selector);
        manager.deposit(address(collateral), 1000e6, 1000e6 + 1);
    }

    function test_Deposit(uint256 amount, uint8 decimals) public {
        amount = bound(amount, 0, 1e40);

        // create a new token and add it as collateral
        MockERC20 token = new MockERC20("Token", "TKN", decimals);
        MockERC4626 tokenVault = new MockERC4626("Token Vault", "vTKN", token);
        vm.prank(owner);
        manager.addCollateral(address(token), address(tokenVault));
        token.mint(address(manager), amount);

        // perform deposit
        vm.startPrank(curator);
        vm.expectEmit();
        emit ICollateralManager.Deposit(address(token), amount);
        manager.deposit(address(token), amount, 0);

        assertEq(token.balanceOf(address(manager)), 0);
        assertEq(token.balanceOf(address(tokenVault)), amount);
        assertEq(tokenVault.totalAssets(), amount);
        assertEq(manager.pendingRevenue(address(token)), 0);
        assertEq(tokenVault.balanceOf(address(manager)), amount);
    }

    function test_Revert_Withdraw() public {
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        manager.withdraw(address(collateral), 1000e6, UINT256_MAX);

        vm.startPrank(curator);
        vm.expectRevert(ICollateralManager.CollateralNotSupported.selector);
        manager.withdraw(address(0), 1000e6, UINT256_MAX);

        vm.expectPartialRevert(ERC4626.ERC4626ExceededMaxWithdraw.selector);
        manager.withdraw(address(collateral), 1000e6, UINT256_MAX);

        // revert if redeeming too many shares during withdraw
        collateral.mint(address(manager), 1000e6);
        manager.deposit(address(collateral), 1000e6, 0);
        collateral.burn(address(vault), 500e6);
        vm.expectRevert(ICollateralManager.ExcessiveSharesRedeemed.selector);
        manager.withdraw(address(collateral), 500e6, 1000e6 - 1);
    }

    function test_Withdraw(uint256 amount, uint8 decimals) public {
        amount = bound(amount, 0, 1e40);
        // create a new token and add it as collateral
        MockERC20 token = new MockERC20("Token", "TKN", decimals);
        MockERC4626 tokenVault = new MockERC4626("Token Vault", "vTKN", token);
        vm.prank(owner);
        manager.addCollateral(address(token), address(tokenVault));
        token.mint(address(manager), amount);

        // deposit some tokens
        vm.startPrank(curator);
        manager.deposit(address(token), amount, 0);

        // withdraw tokens
        vm.expectEmit();
        emit ICollateralManager.Withdraw(address(token), amount);
        manager.withdraw(address(token), amount, UINT256_MAX);

        assertEq(tokenVault.balanceOf(address(manager)), 0);
        assertEq(token.balanceOf(address(manager)), amount);
        assertEq(manager.pendingRevenue(address(token)), 0);
    }

    function test_Revert_WithdrawRevenue() public {
        // only revenue module can withdraw revenue
        vm.expectPartialRevert(ICollateralManager.OnlyRevenueModule.selector);
        manager.withdrawRevenue(address(collateral), 1000e6);

        // revert if unsupported collateral
        vm.startPrank(address(revenueModule));
        vm.expectRevert(ICollateralManager.CollateralNotSupported.selector);
        manager.withdrawRevenue(address(collateral2), 1000e6);

        // revert when trying to withdraw more revenue than has accrued
        vm.startPrank(address(revenueModule));
        vm.expectPartialRevert(ICollateralManager.ExceedsPendingRevenue.selector);
        manager.withdrawRevenue(address(collateral), 1000e6);

        // test withdrawal when manager has insufficient funds
        collateral.mint(address(manager), 1000e6);
        resetPrank(curator);
        manager.deposit(address(collateral), 1000e6, 0);

        // can't withdraw revenue unless curator withdraws from vault
        collateral.mint(address(vault), 100e6 + VAULT_TOLERANCE); // account for vault rounding
        resetPrank(address(revenueModule));
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        manager.withdrawRevenue(address(collateral), 100e6);
    }

    function test_WithdrawRevenue() public {
        // deposit 200
        vm.startPrank(curator);
        collateral.mint(address(manager), 2000e6);
        manager.deposit(address(collateral), 2000e6, 0);

        // simulate earning 2000 interest and withdraw 500
        collateral.mint(address(vault), 2000e6);
        manager.withdraw(address(collateral), 500e6, UINT256_MAX);

        // withdraw 500 as revenue
        resetPrank(address(revenueModule));
        vm.expectEmit();
        emit ICollateralManager.RevenueWithdraw(address(collateral), 500e6);
        manager.withdrawRevenue(address(collateral), 500e6);

        // ensure correct values
        assertApproxEqAbs(manager.pendingRevenue(address(collateral)), 1500e6, VAULT_TOLERANCE);
        assertEq(collateral.balanceOf(address(revenueModule)), 500e6);
        assertEq(vault.totalAssets(), 3500e6);

        // withdraw 500 from vault and withdraw 500 revenue
        resetPrank(curator);
        manager.withdraw(address(collateral), 500e6, UINT256_MAX);
        resetPrank(address(revenueModule));
        manager.withdrawRevenue(address(collateral), 500e6);

        // ensure correct values
        assertApproxEqAbs(manager.pendingRevenue(address(collateral)), 1000e6, VAULT_TOLERANCE);
        assertEq(collateral.balanceOf(address(revenueModule)), 1000e6);
        assertEq(vault.totalAssets(), 3000e6);
    }

    function test_Revert_SetRebalanceCap() public {
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        manager.setRebalanceCap(address(collateral), 10000e6);
    }

    function test_SetRebalanceCap() public {
        vm.startPrank(capAdjuster);
        vm.expectEmit();
        emit ICollateralManager.RebalanceCapChanged(address(collateral), 10000e6);
        manager.setRebalanceCap(address(collateral), 10000e6);
        assertEq(manager.rebalanceCap(address(collateral)), 10000e6);
    }

    function test_Revert_Rebalance() public {
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        manager.rebalance(address(collateral), 10000e6);

        vm.startPrank(rebalancer);
        vm.expectRevert(ICollateralManager.ExceedsRebalanceCap.selector);
        manager.rebalance(address(collateral), 10000e6);
    }

    function test_Rebalance() public {
        collateral.mint(address(manager), 100000e6);
        vm.prank(capAdjuster);
        manager.setRebalanceCap(address(collateral), 10000e6);

        vm.startPrank(rebalancer);
        vm.expectEmit();
        emit ICollateralManager.Rebalance(address(collateral), 5000e6);
        manager.rebalance(address(collateral), 5000e6);
        assertEq(manager.rebalanceCap(address(collateral)), 5000e6);
        assertEq(collateral.balanceOf(custodian), 5000e6);
        assertEq(collateral.balanceOf(address(manager)), 95000e6);

        manager.rebalance(address(collateral), 5000e6);
        assertEq(manager.rebalanceCap(address(collateral)), 0);
        assertEq(collateral.balanceOf(custodian), 10000e6);
        assertEq(collateral.balanceOf(address(manager)), 90000e6);
    }

    function test_Revert_SetSwapModule() public {
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        manager.setSwapModule(address(0));

        vm.startPrank(owner);
        vm.expectRevert(ICollateralManager.NonZeroAddress.selector);
        manager.setSwapModule(address(0));

        vm.expectRevert(ICollateralManager.NonZeroAddress.selector);
        manager.setSwapModule(address(0));
    }

    function test_SetSwapModule() public {
        vm.prank(owner);
        vm.expectEmit();
        emit ICollateralManager.SwapModuleUpdated(address(swapModule));
        manager.setSwapModule(address(swapModule));
        assertEq(manager.swapModule(), address(swapModule));
    }

    function test_Revert_SwapCollateral() public {
        // setup
        SwapContext memory ctx;
        ctx.executor = vm.addr(0x1111);
        ctx.minPrice = 0.99e18; // 1%
        ctx.token1 = collateral;
        ctx.token2 = collateral2;
        ctx.srcToken = address(0);
        ctx.dstToken = address(0);
        ctx.amount = 1000e6;
        ctx.minReturnAmount = 1000e18;

        // create input data
        (
            bytes memory parameters,
            bytes memory swapData,
            /* IAggregationRouterV6.SwapDescription memory  desc*/,
            ISwapModule.SwapParameters memory params
        ) = makeSwapData(ctx);

        vm.prank(capAdjuster);
        manager.setMinSwapPrice(address(collateral), address(collateral2), ctx.minPrice);

        // caller is not curator
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        manager.swap(parameters, swapData);

        vm.startPrank(curator);

        // bad swap parameters & swap data
        vm.expectRevert();
        manager.swap(new bytes(0), swapData);
        vm.expectRevert();
        manager.swap(parameters, new bytes(0));

        vm.startPrank(curator);
        // src token mismatch with collateral types
        vm.expectRevert(ICollateralManager.CollateralNotSupported.selector);
        manager.swap(parameters, swapData);
        params.srcToken = address(collateral);

        // dst token not collateral
        vm.expectRevert(ICollateralManager.CollateralNotSupported.selector);
        manager.swap(abi.encode(params), swapData);

        resetPrank(owner);
        manager.addCollateral(address(collateral2), address(vault2));

        resetPrank(curator);

        // dst token mismatch with collateral types
        vm.expectRevert(ICollateralManager.CollateralNotSupported.selector);
        manager.swap(parameters, swapData);
        params.dstToken = address(collateral2);

        // insufficient srcToken balance
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        manager.swap(abi.encode(params), swapData);

        collateral.mint(address(manager), 1000e6);
        collateral2.mint(address(router), 1000e18);

        // insufficient amount received
        vm.etch(address(router), address(new Mock1InchRouterWithInsufficientAmountSent()).code);
        vm.expectRevert(ICollateralManager.InsufficientAmountReceived.selector);
        manager.swap(abi.encode(params), swapData);
        params.minReturnAmount = 1;

        // Allowed slippage is too high
        vm.expectRevert(ICollateralManager.InsufficientSwapPrice.selector);
        manager.swap(abi.encode(params), swapData);

        // Real slippage is only 1 bps lower than allowed
        params.minReturnAmount = 989.9e18; // 989.9 * 1e6 for slippage ~1%
        vm.expectRevert(ICollateralManager.InsufficientSwapPrice.selector);
        manager.swap(abi.encode(params), swapData);
        vm.stopPrank();

        // invalid source token swap cap
        vm.startPrank(capAdjuster);
        manager.setSwapCap(address(collateral), 0);
        manager.setSwapCap(address(collateral2), 0);
        vm.stopPrank();

        vm.startPrank(curator);
        vm.expectRevert(ICollateralManager.SwapCapExceededSrc.selector);
        manager.swap(abi.encode(params), swapData);
        vm.stopPrank();

        // invalid destination token cap
        params.minReturnAmount = 1000e18;
        vm.startPrank(capAdjuster);
        manager.setSwapCap(address(collateral), type(uint256).max);
        manager.setSwapCap(address(collateral2), params.minReturnAmount - 1);
        vm.stopPrank();

        vm.prank(curator);
        vm.expectRevert(ICollateralManager.SwapCapExceededDst.selector);
        manager.swap(abi.encode(params), swapData);
        vm.stopPrank();

        // received destination token surpasses cap
        vm.etch(address(router), address(new Mock1InchRouterWithExtraAmountSent()).code);
        collateral2.mint(address(router), 1000e18);
        vm.prank(capAdjuster);
        manager.setSwapCap(address(collateral2), params.minReturnAmount);

        vm.prank(curator);
        vm.expectRevert(ICollateralManager.SwapCapExceededDst.selector);
        manager.swap(abi.encode(params), swapData);
        vm.stopPrank();
    }

    function test_SwapCollateral() public {
        // setup
        SwapContext memory ctx;
        ctx.executor = vm.addr(0x1111);
        ctx.token1 = collateral;
        ctx.token2 = collateral2;
        ctx.srcToken = address(collateral);
        ctx.dstToken = address(collateral2);
        ctx.amount = 1000e6;
        ctx.minReturnAmount = 1000e18;

        vm.prank(owner);
        manager.addCollateral(address(collateral2), address(vault2));
        vm.prank(capAdjuster);
        manager.setMinSwapPrice(address(collateral), address(collateral2), 0.99e18); // 1%
        (
            bytes memory parameters,
            bytes memory swapData,
            IAggregationRouterV6.SwapDescription memory desc,
            ISwapModule.SwapParameters memory params
        ) = makeSwapData(ctx);

        // mint tokens
        collateral.mint(address(manager), 1000e6);
        collateral2.mint(address(router), 1000e18);

        // save current caps
        uint256 collateralCap = manager.swapCap(address(collateral));
        uint256 collateral2Cap = manager.swapCap(address(collateral2));

        // perform swap where decimals < 18
        vm.prank(curator);
        vm.expectEmit();
        emit ICollateralManager.Swap(address(collateral), address(collateral2), 1000e6, 1000e18);
        manager.swap(parameters, swapData);

        // check balances
        assertEq(collateral.balanceOf(address(manager)), 0);
        assertEq(collateral2.balanceOf(address(manager)), 1000e18);
        assertEq(manager.swapCap(address(collateral)), collateralCap - ctx.amount);
        assertEq(manager.swapCap(address(collateral2)), collateral2Cap - ctx.minReturnAmount);

        // perform swap where both tokens have equal decimals
        MockERC20 token1 = new MockERC20("mock1", "mock1", 6);
        MockERC20 token2 = new MockERC20("mock2", "mock2", 6);
        MockERC4626 newVault1 = new MockERC4626("Collateral Vault 2", "vCLT2", token1);
        MockERC4626 newVault2 = new MockERC4626("Collateral Vault 2", "vCLT2", token2);

        vm.startPrank(owner);
        manager.addCollateral(address(token2), address(newVault2));
        manager.addCollateral(address(token1), address(newVault1));
        controller.setIsCollateral(address(token1), true);
        controller.setIsCollateral(address(token2), true);
        vm.stopPrank();
        vm.prank(capAdjuster);
        manager.setMinSwapPrice(address(token1), address(token2), 0.99e6); // 1%

        // create new input data
        ctx.token1 = token1;
        ctx.token2 = token2;
        ctx.srcToken = address(token1);
        ctx.dstToken = address(token2);
        ctx.amount = 1000e18;
        ctx.minReturnAmount = 1000e18;
        (parameters, swapData, desc, params) = makeSwapData(ctx);

        // mint tokens
        token1.mint(address(manager), 1000e18);
        token2.mint(address(router), 1000e18);

        // set caps
        vm.startPrank(capAdjuster);
        manager.setSwapCap(address(token1), type(uint256).max);
        manager.setSwapCap(address(token2), type(uint256).max);
        vm.stopPrank();

        // perform swap where decimals < 18
        vm.prank(curator);
        vm.expectEmit();
        emit ICollateralManager.Swap(address(token1), address(token2), 1000e18, 1000e18);
        manager.swap(parameters, swapData);

        // check balances
        assertEq(token1.balanceOf(address(manager)), 0);
        assertEq(token2.balanceOf(address(manager)), 1000e18);
    }

    function test_SwapCollateralSlippage() public {
        SwapContext memory ctx;
        ctx.executor = vm.addr(0x1111);
        ctx.token1 = new MockERC20("mock1", "mock1", 6);
        ctx.srcToken = address(ctx.token1);
        MockERC4626 newVault1 = new MockERC4626("Collateral Vault 1", "vCLT1", ctx.token1);

        // Perform swap where one token decimals > 18
        ctx.token2 = new MockERC20("mock2", "mock2", 20);
        ctx.dstToken = address(ctx.token2);
        MockERC4626 newVault2 = new MockERC4626("Collateral Vault 2", "vCLT2", ctx.token2);
        vm.startPrank(capAdjuster);
        manager.setSwapCap(ctx.srcToken, type(uint256).max);
        manager.setSwapCap(ctx.dstToken, type(uint256).max);
        vm.stopPrank();

        ctx.amount = 1000e6;
        ctx.minReturnAmount = 1000e20;

        vm.startPrank(owner);
        manager.addCollateral(address(ctx.token1), address(newVault1));
        manager.addCollateral(address(ctx.token2), address(newVault2));
        vm.stopPrank();
        vm.prank(capAdjuster);
        manager.setMinSwapPrice(address(ctx.token1), address(ctx.token2), 0.99e20); // 1%

        // mint tokens
        ctx.token1.mint(address(manager), 1000e6);
        ctx.token2.mint(address(router), 1000e20);

        // create input data
        (bytes memory parameters, bytes memory swapData,,) = makeSwapData(ctx);

        // mint tokens
        ctx.token1.mint(address(manager), 1000e6);
        ctx.token2.mint(address(router), 1000e20);

        // perform swap where decimals < 18
        vm.prank(curator);
        vm.expectEmit();
        emit ICollateralManager.Swap(address(ctx.token1), address(ctx.token2), 1000e6, 1000e20);
        manager.swap(parameters, swapData);

        // check balances
        assertEq(ctx.token1.balanceOf(address(router)), 1000e6);
        assertEq(ctx.token2.balanceOf(address(manager)), 1000e20);
    }

    function test_Revert_UpdateController() public {
        // set up
        Controller newController = new Controller(address(asset), 1e17, custodian, address(this));
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(0);

        // revert if not called by admin
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        manager.updateController(address(newController));

        // revert if new controller is zero address
        vm.prank(owner);
        vm.expectRevert(ICollateralManager.NonZeroAddress.selector);
        manager.updateController(address(0));
    }

    function test_UpdateController() public {
        // set up and add second collateral
        vm.prank(owner);
        manager.addCollateral(address(collateral2), address(vault2));
        Controller newController = new Controller(address(asset), 1e17, custodian, address(this));
        address[] memory collaterals = new address[](2);
        collaterals[0] = address(collateral);
        collaterals[1] = address(collateral2);

        vm.prank(owner);
        vm.expectEmit();
        emit ICollateralManager.ControllerUpdated(address(newController));
        manager.updateController(address(newController));
        assertEq(manager.controller(), address(newController));
        assertEq(collateral.allowance(address(manager), address(controller)), 0);
        assertEq(collateral2.allowance(address(manager), address(controller)), 0);
        assertEq(collateral.allowance(address(manager), address(newController)), type(uint256).max);
        assertEq(collateral2.allowance(address(manager), address(newController)), type(uint256).max);
    }

    function test_Revert_RescueEther() public {
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        manager.rescueEther();
        vm.prank(owner);
        manager.grantRole(ADMIN_ROLE, address(etherReceiver));

        // revert when receiving ether
        vm.prank(address(etherReceiver));
        vm.expectPartialRevert(ICollateralManager.RescueEtherFailed.selector);
        manager.rescueEther();
    }

    function test_RescueEther() public {
        deal(address(manager), 1e18);
        vm.prank(admin);
        manager.rescueEther();
        assertEq(address(manager).balance, 0);
        assertEq(admin.balance, 1e18);
    }

    function test_setMinSwapPrice() public {
        vm.prank(capAdjuster);
        vm.expectEmit();
        emit ICollateralManager.MinSwapPriceUpdated(address(collateral), address(collateral2), 1e18);
        manager.setMinSwapPrice(address(collateral), address(collateral2), 1e18);

        assertEq(manager.minSwapPrice(address(collateral), address(collateral2)), 1e18);
    }

    function test_setSwapCap() public {
        vm.prank(capAdjuster);
        vm.expectEmit();
        emit ICollateralManager.SwapCapUpdated(address(collateral), 1e18);
        manager.setSwapCap(address(collateral), 1e18);

        assertEq(manager.swapCap(address(collateral)), 1e18);
    }

    function test_fuzz_Slippage(uint16 bps, uint8 dec1, uint8 dec2, uint256 amount) public {
        SwapContext memory ctx;
        // Avoid small values that will affect divisions and also big values to not affect multiplication
        amount = bound(amount, 1, 1_000_000);
        ctx.dec1 = uint8(bound(dec1, 6, 20));
        ctx.dec2 = uint8(bound(dec2, 6, 20));

        // Need to adjust min amount per decimal amount
        bps = uint16(bound(bps, 50, 5_000)); // max 50% slippage

        // set min price based on slippage in bps
        ctx.minPrice = 10 ** ctx.dec2 - 10 ** ctx.dec2 * bps / BASIS_PRECISION;
        ctx.token1 = new MockERC20("Mock Collateral", "MCLT", ctx.dec1);
        ctx.token2 = new MockERC20("Mock Collateral", "MCLT", ctx.dec2);
        ctx.srcToken = address(ctx.token1);
        ctx.dstToken = address(ctx.token2);
        MockERC4626 vault1 = new MockERC4626("Mock Vault", "MVLT", ctx.token1);
        MockERC4626 vault2 = new MockERC4626("Mock Vault", "MVLT", ctx.token2);
        vm.startPrank(capAdjuster);
        manager.setSwapCap(ctx.srcToken, type(uint256).max);
        manager.setSwapCap(ctx.dstToken, type(uint256).max);
        vm.stopPrank();

        // 0 Slippage
        ctx.amount = amount * (10 ** ctx.dec1);
        ctx.minReturnAmount = amount * (10 ** ctx.dec2);

        vm.startPrank(owner);
        manager.addCollateral(address(ctx.token1), address(vault1));
        manager.addCollateral(address(ctx.token2), address(vault2));
        vm.stopPrank();
        vm.prank(capAdjuster);
        manager.setMinSwapPrice(address(ctx.token1), address(ctx.token2), ctx.minPrice);

        (bytes memory parameters, bytes memory swapData,, ISwapModule.SwapParameters memory params) = makeSwapData(ctx);

        // mint tokens
        ctx.token1.mint(address(manager), ctx.amount);
        ctx.token2.mint(address(router), ctx.minReturnAmount);

        // perform swap
        vm.prank(curator);
        manager.swap(parameters, swapData);

        // check balances
        assertEq(ctx.token1.balanceOf(address(manager)), 0);
        assertEq(ctx.token2.balanceOf(address(manager)), ctx.minReturnAmount);

        // Trigger Slippage error

        // Create an amount under slippage threshold
        uint256 limitDiff = (params.minReturnAmount * bps / BASIS_PRECISION);
        uint256 threshold = params.minReturnAmount - limitDiff;

        params.minReturnAmount = threshold / 2;

        vm.prank(curator);
        vm.expectRevert(ICollateralManager.InsufficientSwapPrice.selector);
        manager.swap(abi.encode(params), swapData);
    }

    function test_fuzz_Rebalance(uint256 amount) public {
        amount = bound(amount, 100, 1e40);
        collateral.mint(address(manager), amount);
        vm.prank(capAdjuster);
        manager.setRebalanceCap(address(collateral), amount);

        vm.startPrank(rebalancer);
        vm.expectEmit();
        emit ICollateralManager.Rebalance(address(collateral), amount);
        manager.rebalance(address(collateral), amount);
        assertEq(manager.rebalanceCap(address(collateral)), 0);
        assertEq(collateral.balanceOf(custodian), amount);
        assertEq(collateral.balanceOf(address(manager)), 0);
    }

    function test_DepositReentrancy() public {
        // Add corrupted vault
        MockReentrantERC20 badCollateral = new MockReentrantERC20("Mock Collateral", "MCLT", 18);
        MockReentrantERC4626 badVault = new MockReentrantERC4626("BadVault", "BV", badCollateral);
        vm.prank(owner);
        manager.addCollateral(address(badCollateral), address(badVault));

        // deposit
        badVault.setTriggerReentrancy(true);
        badCollateral.mint(address(manager), 10000e6);
        vm.startPrank(curator);
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        manager.deposit(address(badCollateral), 10000e6, 0);
        vm.stopPrank();
    }

    function test_WithdrawReentrancy() public {
        // Add corrupted vault
        MockReentrantERC20 badCollateral = new MockReentrantERC20("Mock Collateral", "MCLT", 18);
        MockReentrantERC4626 badVault = new MockReentrantERC4626("BadVault", "BV", badCollateral);
        vm.prank(owner);
        manager.addCollateral(address(badCollateral), address(badVault));

        // withdraw
        badCollateral.mint(address(manager), 10000e6);
        badVault.setTriggerReentrancy(false);
        vm.prank(curator);
        manager.deposit(address(badCollateral), 10000e6, 0);
        badVault.setTriggerReentrancy(true);
        vm.prank(curator);
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        manager.withdraw(address(badCollateral), 10000e6, UINT256_MAX);
    }

    function test_WithdrawRevenueReentrancy() public {
        // Add corrupted vault
        MockReentrantERC20 badCollateral = new MockReentrantERC20("Mock Collateral", "MCLT", 18);
        MockReentrantERC4626 badVault = new MockReentrantERC4626("BadVault", "BV", badCollateral);
        vm.prank(owner);
        manager.addCollateral(address(badCollateral), address(badVault));

        // withdrawRevenue
        badVault.setTriggerReentrancy(false);
        vm.startPrank(curator);
        badCollateral.mint(address(manager), 1000e6);
        manager.deposit(address(badCollateral), 1000e6, 0);

        resetPrank(curator);
        badCollateral.mint(address(badVault), 1000e6);
        manager.withdraw(address(badCollateral), 500e6, UINT256_MAX);

        badCollateral.setTriggerReentrancy(true);
        resetPrank(address(revenueModule));
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        manager.withdrawRevenue(address(badCollateral), 500e6);
        badCollateral.setTriggerReentrancy(false);
        vm.stopPrank();
    }

    function test_SwapReentrancy() public {
        // Add corrupted vault
        MockReentrantERC20 badCollateral = new MockReentrantERC20("Mock Collateral", "MCLT", 18);
        MockReentrantERC4626 badVault = new MockReentrantERC4626("BadVault", "BV", badCollateral);
        vm.prank(owner);
        manager.addCollateral(address(badCollateral), address(badVault));

        // swap
        SwapContext memory ctx;
        ctx.executor = vm.addr(0x1111);
        ctx.token1 = MockERC20(address(badCollateral));
        ctx.token2 = collateral2;
        ctx.srcToken = address(badCollateral);
        ctx.dstToken = address(collateral2);
        ctx.amount = 1000e18;
        ctx.minReturnAmount = 1000e18;

        vm.prank(owner);
        manager.addCollateral(address(collateral2), address(vault2));
        vm.prank(capAdjuster);
        manager.setMinSwapPrice(address(badCollateral), address(collateral2), 0.99e18); // 1%
        (
            bytes memory parameters,
            bytes memory swapData,
            /* IAggregationRouterV6.SwapDescription memory  desc*/,
            ISwapModule.SwapParameters memory params
        ) = makeSwapData(ctx);

        badCollateral.mint(address(manager), 1000e18);
        collateral2.mint(address(router), 1000e18);
        vm.prank(capAdjuster);
        manager.setSwapCap(address(badCollateral), params.amount);

        badCollateral.setTriggerReentrancy(true);
        vm.prank(curator);
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        manager.swap(parameters, swapData);
    }

    function test_ExposedGetRevenue() public {
        // deposit some collateral into vault
        collateral.mint(address(manager), 1000e6);
        vm.prank(curator);
        manager.deposit(address(collateral), 1000e6, 0);

        // check internal function
        assertEq(manager.exposedGetRevenue(address(collateral), vault), 0);

        // simulate earning interest
        collateral.mint(address(vault), 1000e6);
        assertApproxEqAbs(manager.exposedGetRevenue(address(collateral), vault), 1000e6, VAULT_TOLERANCE);

        // simulate a loss
        collateral.burn(address(vault), 500e6);
        assertApproxEqAbs(manager.exposedGetRevenue(address(collateral), vault), 500e6, VAULT_TOLERANCE);
    }

    function test_ExposedTotalAssets() public {
        // assets in collateral manager are included in assets
        collateral.mint(address(manager), 1000e18);
        vm.prank(curator);
        manager.deposit(address(collateral), 1000e18, 0);
        assertApproxEqAbs(manager.exposedTotalAssets(vault), 1000e18, VAULT_TOLERANCE);
    }

    function test_Revert_ClaimRewards() public {
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = keccak256("p0");
        proof[1] = keccak256("p1");

        vm.expectPartialRevert(ICollateralManager.OnlyRevenueModule.selector);
        manager.claimMorphoRewards(address(distributor), address(collateral), 1e18, proof);
    }

    function test_ClaimRewards() public {
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = keccak256("p0");
        proof[1] = keccak256("p1");

        assertGt(collateral.balanceOf(address(distributor)), 1e18);

        vm.prank(address(revenueModule));
        manager.claimMorphoRewards(address(distributor), address(collateral), 1e18, proof);

        assertEq(collateral.balanceOf(address(revenueModule)), 1e18);
    }

    function test_Revert_SetRevenueModule() public {
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        manager.setRevenueModule(address(revenueModule));
    }

    function test_SetRevenueModule() public {
        vm.prank(owner);
        vm.expectEmit();
        emit ICollateralManager.RevenueModuleUpdated(address(revenueModule));
        manager.setRevenueModule(address(revenueModule));
        assertEq(manager.revenueModule(), address(revenueModule));
    }

    function test_RescueToken() public {
        address to = address(1);
        uint256 amount = 1e18;

        // Send non collateral token
        collateral2.mint(address(manager), amount);
        assertEq(collateral2.balanceOf(to), 0);
        assertEq(collateral2.balanceOf(address(manager)), amount);

        // Rescue tokens
        vm.prank(owner);
        manager.rescueToken(address(collateral2), to);
        assertEq(collateral2.balanceOf(to), amount);
        assertEq(collateral2.balanceOf(address(manager)), 0);
    }

    function test_Revert_RescueToken() public {
        // invalid caller
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        manager.rescueToken(address(collateral2), address(1));

        // invalid recipient
        vm.expectRevert(ICollateralManager.NonZeroAddress.selector);
        vm.prank(owner);
        manager.rescueToken(address(collateral2), address(0));

        // invalid collateral token
        vm.expectRevert(ICollateralManager.InvalidRescueToken.selector);
        vm.prank(owner);
        manager.rescueToken(address(collateral), address(1));

        // invalid vault token
        vm.expectRevert(ICollateralManager.InvalidRescueToken.selector);
        vm.prank(owner);
        manager.rescueToken(address(vault), address(1));
    }

    function test_ConvertRevenue() public {
        // mint some collateral to manager
        collateral.mint(address(manager), 1000e6);

        // deposit into vault
        vm.prank(curator);
        manager.deposit(address(collateral), 1000e6, 0);

        // simulate vault earning interest
        collateral.mint(address(vault), 1000e6);
        assertApproxEqAbs(manager.getRevenue(address(collateral)), 1000e6, VAULT_TOLERANCE);

        // convert revenue to collateral
        vm.prank(rebalancer);
        manager.convertRevenue(address(collateral), 500e6);

        // check revenue is distributed correctly
        assertApproxEqAbs(manager.getRevenue(address(collateral)), 500e6, VAULT_TOLERANCE);
    }

    function test_Revert_ConvertRevenue() public {
        vm.expectRevert(ICollateralManager.CollateralNotSupported.selector);
        vm.prank(rebalancer);
        manager.convertRevenue(address(this), 500e6);

        vm.expectRevert(ICollateralManager.ExceedsPendingRevenue.selector);
        vm.prank(rebalancer);
        manager.convertRevenue(address(collateral), 500e6);
    }
}
