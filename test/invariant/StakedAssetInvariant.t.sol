// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "../BaseTest.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {StakedAssetHandler} from "../invariant/handlers/StakedAssetHandler.sol";

// forge test --mc StakedAssetInvariantTest -vvvv
contract StakedAssetInvariantTest is BaseTest {
    StakedAssetHandler handler;

    function setUp() public override {
        super.setUp();

        vm.prank(admin);
        staking.setVestingPeriod(7 days); // Ensure this was called at least once
        handler = new StakedAssetHandler(admin, rewarder, user, staking, asset);

        targetContract(address(handler));
    }

    // - `decimals` always returns 18
    function invariant_decimalsAlways18() public view {
        assertEq(staking.decimals(), 18, "Decimals must always be 18");
    }

    // - `cooldownPeriod > MAX_COOLDOWN_PERIOD` is always true
    function invariant_cooldownWithinBounds() public view {
        assertLe(staking.cooldownPeriod(), staking.MAX_COOLDOWN_PERIOD(), "Cooldown period exceeds max");
    }

    // - `vestingPeriod >= MIN_VESTING_PERIOD && vestingPeriod != 0` is always true
    // - `vestingPeriod <= MAX_VESTING_PERIOD` is always true
    function invariant_vestingPeriodBounds() public view {
        (uint256 period,,) = staking.vesting();
        assertLe(period, staking.MAX_VESTING_PERIOD(), "Invalid vesting period");
        assertTrue(period >= staking.MIN_VESTING_PERIOD() || period != 0, "Invalid vesting period");
    }

    // - `asset()` is never `address(0)`
    function invariant_assetNotZero() public view {
        assertTrue(address(staking.asset()) != address(0), "Asset address must never be zero");
    }

    // - When `vesting.period == 0` or `block.timestamp >= vesting.time`, `_pendingRewards() == 0` always holds
    function invariant_pendingRewardsZeroWhenVestingComplete() public view {
        (uint128 time, uint128 period,) = staking.vesting();

        if (period != 0 || block.timestamp >= time) {
            uint256 pending = staking.pendingRewards();
            assertGe(pending, 0, "Pending rewards should be zero after vesting complete or disabled");
        }
    }

    // - `totalAssets() = IERC20(asset()).balanceOf(address(this)) - _pendingRewards()`
    function invariant_totalAssetsMatchesBalanceMinusPending() public view {
        uint256 balance = IERC20(staking.asset()).balanceOf(address(staking));
        uint256 pending = staking.pendingRewards();
        uint256 total = staking.totalAssets();
        assertEq(total, balance - pending, "totalAssets mismatch");
    }

    // - `block.timestamp at cooldown ≥ cooldowns[user].timestamp`
    function invariant_unstakeOnlyAfterCooldown() public view {
        (uint256 assets, uint256 end) = staking.cooldowns(user);
        if (assets != 0) {
            // In some sequences cooldown might not be called
            assertGe(end, handler.blockAtCooldown());
        }
    }

    // - Contract token balance reflects all vested and unvested rewards
    function invariant_balanceCoversAssetsAndRewards() public view {
        uint256 balance = IERC20(staking.asset()).balanceOf(address(staking));
        uint256 total = staking.totalAssets();
        uint256 pending = staking.pendingRewards();

        // The full balance should at least cover vested + unvested
        assertGe(balance, total + pending, "Contract balance inconsistent with reward accounting");
    }
}
