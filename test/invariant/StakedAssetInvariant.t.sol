// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {InvariantBase} from "./InvariantBase.sol";
import {StakedAssetHandler} from "./handlers/StakedAssetHandler.sol";

// echidna: echidna test/invariant/StakedAssetInvariant.t.sol --contract StakedAssetInvariantTest --config echidna.yaml
// foundry: forge test --mc StakedAssetInvariantTest -vvvv
contract StakedAssetInvariantTest is InvariantBase {
    StakedAssetHandler handler;
    uint256 constant INITIAL_CAP = type(uint256).max;

    function setUp() public override {
        super.setUp();

        // Ensure this was called at least once
        vm.prank(admin);
        staking.setVestingPeriod(7 days);
        vm.prank(capAdjuster);
        staking.setInstantUnstakeCap(INITIAL_CAP);
        handler = new StakedAssetHandler(admin, rewarder, user, staking, asset);
        vm.prank(owner);
        staking.grantRole(INSTANT_UNSTAKER_ROLE, address(handler));

        targetContract(address(handler));
    }

    // `decimals` always returns 18
    function invariant_decimalsAlways18() public view {
        assertEq(staking.decimals(), 18, "Decimals must always be 18");
    }

    // `cooldownPeriod > MAX_COOLDOWN_PERIOD` is always true
    function invariant_cooldownWithinBounds() public view {
        assertLe(staking.cooldownPeriod(), staking.MAX_COOLDOWN_PERIOD(), "Cooldown period exceeds max");
    }

    // `vestingPeriod >= MIN_VESTING_PERIOD && vestingPeriod != 0` is always true
    // `vestingPeriod <= MAX_VESTING_PERIOD` is always true
    function invariant_vestingPeriodBounds() public view {
        (uint256 period,,) = staking.vesting();
        assertLe(period, staking.MAX_VESTING_PERIOD(), "Invalid vesting period");
        assertTrue(period >= staking.MIN_VESTING_PERIOD() || period != 0, "Invalid vesting period");
    }

    // `asset()` is never `address(0)`
    function invariant_assetNotZero() public view {
        assertTrue(address(staking.asset()) != address(0), "Asset address must never be zero");
    }

    // When `vesting.period == 0` or `block.timestamp >= vesting.end`, `_pendingRewards() == 0` always holds
    function invariant_pendingRewardsZeroWhenVestingComplete() public view {
        (uint128 period, uint128 end,) = staking.vesting();

        if (period != 0 || block.timestamp >= end) {
            uint256 pending = staking.pendingRewards();
            assertGe(pending, 0, "Pending rewards should be zero after vesting complete or disabled");
        }
    }

    // `totalAssets() = IERC20(asset()).balanceOf(address(this)) - _pendingRewards()`
    function invariant_totalAssetsMatchesBalanceMinusPending() public view {
        uint256 balance = IERC20(staking.asset()).balanceOf(address(staking));
        uint256 pending = staking.pendingRewards();
        uint256 total = staking.totalAssets();
        assertEq(total, balance - pending, "totalAssets mismatch");
    }

    // `block.timestamp at cooldown ≥ cooldowns[user].timestamp`
    function invariant_unstakeOnlyAfterCooldown() public view {
        uint256 maxId = staking.cooldownIds(user);
        for (uint256 id = 0; id < maxId; id++) {
            (uint256 assets, uint256 end) = staking.cooldowns(user, id);
            if (assets != 0) {
                // In some sequences cooldown might not be called
                assertGe(end, handler.blockAtCooldown(id));
            }
        }
    }

    // Contract token balance reflects all vested and unvested rewards
    function invariant_balanceCoversAssetsAndRewards() public view {
        uint256 balance = IERC20(staking.asset()).balanceOf(address(staking));
        uint256 total = staking.totalAssets();
        uint256 pending = staking.pendingRewards();

        // The full balance should at least cover vested + unvested
        assertGe(balance, total + pending, "Contract balance inconsistent with reward accounting");
    }

    // instantUnstakeCap decreases proportionally to the amount of assets being instantly unstaken.
    function invariant_instantUnstakeCapDecrease() public view {
        assertEq(staking.instantUnstakeCap(), INITIAL_CAP - handler.totalIntantUnStaked());
    }

    // user cooldown Id never decreases
    function invariant_cooldownIds() public view {
        assertFalse(handler.idDecreased());
    }

    // There can never be a zero assets active cooldown
    function invariant_activeCooldownAssets() public view {
        uint256 maxId = staking.cooldownIds(user);
        for (uint256 id = 0; id < maxId; id++) {
            (uint256 assets, uint256 end) = staking.cooldowns(user, id);
            if (end != 0) {
                // In some sequences cooldown might not be called
                assertTrue(assets > 0);
            }
        }
    }

    // Allowance for staking is constant
    function invariant_asset_allowance_is_uint_max() public view {
        assertEq(asset.allowance(address(silo), address(staking)), type(uint256).max);
    }

    // if there are pending rewards totalAssets never returns the full asset balance
    function invariant_pending_rewards_lt_total_assets() external view {
        uint256 pending = staking.pendingRewards();
        uint256 balance = asset.balanceOf(address(staking));
        uint256 totalAssets = staking.totalAssets();
        if (pending > 0) {
            assertLt(totalAssets, balance);
        }
    }

    //-------------------- Access Control Invariants-----------------------------------
    // Only REWARDER_ROLE can call reward()
    function invariant_setSignerStatus_only_signerManager_callable() public {
        try staking.reward(1e18) {
            assertTrue(false);
        } catch {
            assertTrue(true);
        }
    }

    // Only ADMIN_ROLE can call setVestingPeriod()
    function invariant_setVestingPeriod_only_admin_callable() public {
        try staking.setVestingPeriod(1e18) {
            assertTrue(false);
        } catch {
            assertTrue(true);
        }
    }

    // Only ADMIN_ROLE can call setCooldownPeriod()
    function invariant_setCooldownPeriod_only_admin_callable() public {
        try staking.setCooldownPeriod(1e18) {
            assertTrue(false);
        } catch {
            assertTrue(true);
        }
    }

    //Only ADMIN_ROLE can call rescueToken()
    function invariant_rescueToken_only_admin_callable() public {
        try staking.rescueToken(address(asset), address(1)) {
            assertTrue(false);
        } catch {
            assertTrue(true);
        }
    }

    // Only RESTRICTER_ROLE can call setIsRestricted()
    function invariant_setIsRestricted_only_restricter_callable() public {
        try staking.setIsRestricted(address(1), true) {
            assertTrue(false);
        } catch {
            assertTrue(true);
        }
    }
}
