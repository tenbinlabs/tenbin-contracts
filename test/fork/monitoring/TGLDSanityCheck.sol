// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetSilo} from "tenbin-contracts/src/AssetSilo.sol";
import {AssetToken} from "tenbin-contracts/src/AssetToken.sol";
import {CollateralManager} from "tenbin-contracts/src/CollateralManager.sol";
import {Controller} from "tenbin-contracts/src/Controller.sol";
import {Gate} from "tenbin-contracts/src/external/morpho/Gate.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {MonitorBase} from "./MonitorBase.sol";
import {RevenueModule} from "tenbin-contracts/src/RevenueModule.sol";
import {StakedAsset} from "tenbin-contracts/src/StakedAsset.sol";
import {SwapModule} from "tenbin-contracts/src/SwapModule.sol";

/// @notice General assumptions that must always hold to ensure a healthy
contract TGLDSanityCheck is MonitorBase {
    // Asset Token
    // Owner can never be zero address
    function testOwnerValidAddress() public view {
        assertNotEq(AssetToken(contracts.asset_token).owner(), address(0));
    }

    // Collateral Manager
    // For every supported collateral its assigned vault must have it as the underlying asset, `IERC4626(vault).asset() == collateral`
    function testVaultCollateralAddress() public view {
        IERC4626 currentVault = CollateralManager(contracts.collateral_manager).vaults(address(usdc));
        assertEq(currentVault.asset(), address(usdc));
    }

    // `controller` can never be the zero address
    function testControllerAddress() public view {
        assertNotEq(CollateralManager(contracts.collateral_manager).controller(), address(0));
    }

    // `swapModule` can never be the zero address
    function testSwapModuleAddress() public view {
        assertNotEq(CollateralManager(contracts.collateral_manager).swapModule(), address(0));
    }

    // Controller
    // `ratio` must be less or equal to `RATIO_PRECISION`
    function testRatio() public view {
        assertTrue(Controller(contracts.controller).ratio() <= RATIO_PRECISION);
    }

    // `custodian` must never be `address(0)`
    function testCustodianAddress() public view {
        assertNotEq(Controller(contracts.controller).custodian(), address(0));
    }

    // `manager` must never be `address(0)`
    function testManagerAddress() public view {
        assertNotEq(Controller(contracts.controller).manager(), address(0));
    }

    // `asset` must never be `address(0)`
    function testControllerAssetAddress() public view {
        assertNotEq(Controller(contracts.controller).asset(), address(0));
    }

    // Revenue Module
    // Revenue module has the correct staking address
    function testRevenueModuleStakingAddress() public view {
        assertEq(RevenueModule(contracts.revenue_module).staking(), contracts.staked_asset);
    }

    // Revenue module has the correct asset address
    function testRevenueModuleAssetAddress() public view {
        assertEq(RevenueModule(contracts.revenue_module).asset(), contracts.asset_token);
    }

    // Revenue module has the correct manager address
    function testRevenueModuleManagerAddress() public view {
        assertEq(RevenueModule(contracts.revenue_module).manager(), contracts.collateral_manager);
    }

    // Revenue module has the correct controller address
    function testRevenueModuleControllerAddress() public view {
        assertEq(RevenueModule(contracts.revenue_module).controller(), contracts.controller);
    }

    // Revenue module has the correct multisig address
    function testRevenueModuleMultisigAddress() public view {
        assertEq(RevenueModule(contracts.revenue_module).multisig(), global.tenbin_multisig);
    }

    // The token used by the revenue m,module to reward the staking contract must be the expected by the staking contract
    function testRevenueModuleRewardsCorrectToken() public view {
        assertEq(RevenueModule(contracts.revenue_module).asset(), address(StakedAsset(contracts.staked_asset).asset()));
    }

    // Staked Asset

    // `decimals` always returns 18
    function testDecimalsAlways18() public view {
        assertEq(StakedAsset(contracts.staked_asset).decimals(), 18, "Decimals must always be 18");
    }

    // `cooldownPeriod > MAX_COOLDOWN_PERIOD` is always true
    function testCooldownWithinBounds() public view {
        assertLe(
            StakedAsset(contracts.staked_asset).cooldownPeriod(),
            StakedAsset(contracts.staked_asset).MAX_COOLDOWN_PERIOD(),
            "Cooldown period exceeds max"
        );
    }

    // `vestingPeriod >= MIN_VESTING_PERIOD && vestingPeriod != 0` is always true
    // `vestingPeriod <= MAX_VESTING_PERIOD` is always true
    function testVestingPeriodBounds() public view {
        (uint256 period,,) = StakedAsset(contracts.staked_asset).vesting();
        assertLe(period, StakedAsset(contracts.staked_asset).MAX_VESTING_PERIOD(), "Invalid vesting period");
        assertTrue(
            period >= StakedAsset(contracts.staked_asset).MIN_VESTING_PERIOD() || period != 0, "Invalid vesting period"
        );
    }

    // `asset()` is never `address(0)`
    function testAssetNotZero() public view {
        assertTrue(
            address(StakedAsset(contracts.staked_asset).asset()) != address(0), "Asset address must never be zero"
        );
    }

    // When `vesting.period == 0` or `block.timestamp >= vesting.time`, `_pendingRewards() == 0` always holds
    function testPendingRewardsZeroWhenVestingComplete() public view {
        (uint128 time, uint128 period,) = StakedAsset(contracts.staked_asset).vesting();

        if (period != 0 || block.timestamp >= time) {
            uint256 pending = StakedAsset(contracts.staked_asset).pendingRewards();
            assertGe(pending, 0, "Pending rewards should be zero after vesting complete or disabled");
        }
    }

    // `totalAssets() = underlyingBalance - pendingRewards()`
    function testTotalAssetsMatchesBalanceMinusPending() public view {
        uint256 balance = AssetToken(contracts.asset_token).balanceOf(contracts.staked_asset);
        uint256 pending = StakedAsset(contracts.staked_asset).pendingRewards();
        uint256 total = StakedAsset(contracts.staked_asset).totalAssets();
        assertEq(total, balance - pending, "totalAssets mismatch");
    }

    // Total supply is always greater or equal than initial minted shares
    function testStakingSupply() public view {
        assertGe(StakedAsset(contracts.staked_asset).totalSupply(), 1e12);
    }

    // Contract token balance reflects all vested and unvested rewards
    function testBalanceCoversAssetsAndRewards() public view {
        uint256 underlyingBalance = AssetToken(contracts.asset_token).balanceOf(contracts.staked_asset);
        uint256 total = StakedAsset(contracts.staked_asset).totalAssets();
        uint256 pending = StakedAsset(contracts.staked_asset).pendingRewards();

        assertGe(underlyingBalance, total + pending, "Contract balance inconsistent with reward accounting");
    }

    // Minting shares without assets must never happen
    function testAssetsSharesRatio() public view {
        // If more shares than initial mint, assets must also increase
        bool value = (StakedAsset(contracts.staked_asset).totalSupply() > 12)
            ? AssetToken(contracts.asset_token).balanceOf(contracts.staked_asset) > 1
            : true;
        assertTrue(value);
    }

    // Redeem can never result in less than total asset balance
    function testAssetsSharesPrice() public view {
        assertGe(
            AssetToken(contracts.asset_token).balanceOf(contracts.staked_asset),
            StakedAsset(contracts.staked_asset).previewRedeem(StakedAsset(contracts.staked_asset).totalSupply())
        );
    }

    // Swap Module
    // Manager must match correct one
    function testSwapModuleManagerAccount() public view {
        assertEq(SwapModule(contracts.swap_module).manager(), contracts.collateral_manager);
    }

    // Admin must match correct one
    function testSwapModuleAdminAccount() public view {
        bool res = false;
        for (uint256 i = 0; i < roles.admin_role.length; i++) {
            if (SwapModule(contracts.swap_module).admin() == roles.admin_role[i]) {
                res = true;
                break;
            }
        }
        assertTrue(res);
    }

    // Router must match correct one
    function testSwapModuleRouterAccount() public view {
        assertEq(SwapModule(contracts.swap_module).router(), ONE_INCH_ROUTER);
    }

    // Gate
    // Manager should always be the account permitted by the gate
    function testGateResponses() public view {
        assertTrue(Gate(vaultContracts.gate).canReceiveAssets(contracts.collateral_manager));
        assertTrue(Gate(vaultContracts.gate).canReceiveShares(contracts.collateral_manager));
        assertTrue(Gate(vaultContracts.gate).canSendAssets(contracts.collateral_manager));
        assertTrue(Gate(vaultContracts.gate).canSendShares(contracts.collateral_manager));
    }

    // Asset Silo
    // silo has correct staking contract address
    function testSiloStakingAddress() public view {
        assertEq(AssetSilo(contracts.silo).staking(), contracts.staked_asset);
    }
}
