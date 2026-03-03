// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {EchidnaBase} from "./EchidnaBase.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {StakedAsset} from "../../src/StakedAsset.sol";

// echidna test/echidna/StakedAssetEchidna.sol --contract StakedAssetEchidna --config echidna.yaml
contract StakedAssetEchidna is EchidnaBase {
    bytes32 internal constant REWARDER_ROLE = keccak256("REWARDER_ROLE");
    StakedAsset staking;

    constructor() {
        bytes32 salt = bytes32(abi.encodePacked("salt"));
        address stakingImplementation = address(new StakedAsset{salt: salt}());
        bytes memory data = abi.encodeWithSelector(
            StakedAsset.initialize.selector, "Staked Asset", "stAST", address(asset), address(this)
        );
        ERC1967Proxy proxy = new ERC1967Proxy{salt: salt}(stakingImplementation, data);
        staking = StakedAsset(address(proxy));

        // set up
        staking.grantRole(REWARDER_ROLE, address(this));
        grantRole(REWARDER_ROLE, address(staking));
        grantRole(ADMIN_ROLE, address(staking));
        grantRole(RESTRICTER_ROLE, address(staking));

        asset.approve(address(staking), type(uint256).max);
    }

    // Only REWARDER_ROLE can call reward()
    function echidna_setSignerStatus_only_signerManager_callable() public returns (bool) {
        try staking.reward(1e18) {
            return false;
        } catch {
            return true;
        }
    }

    // Only ADMIN_ROLE can call setVestingPeriod()
    function echidna_setVestingPeriod_only_admin_callable() public returns (bool) {
        try staking.setVestingPeriod(1e18) {
            return false;
        } catch {
            return true;
        }
    }

    // Only ADMIN_ROLE can call setCooldownPeriod()
    function echidna_setCooldownPeriod_only_admin_callable() public returns (bool) {
        try staking.setCooldownPeriod(1e18) {
            return false;
        } catch {
            return true;
        }
    }

    //Only ADMIN_ROLE can call rescueToken()
    function echidna_rescueToken_only_admin_callable() public returns (bool) {
        try staking.rescueToken(address(asset), address(1)) {
            return false;
        } catch {
            return true;
        }
    }

    // Only RESTRICTER_ROLE can call setIsRestricted()
    function echidna_setIsRestricted_only_restricter_callable() public returns (bool) {
        try staking.setIsRestricted(address(1), true) {
            return false;
        } catch {
            return true;
        }
    }

    // Pending rewards is zero if vesting.period == 0
    function echidna_vesting_pending_reward() external view returns (bool) {
        (, uint128 period,) = staking.vesting();
        uint256 pending = staking.pendingRewards();
        return period > 0 || (period == 0 && pending == 0);
    }

    // _pendingRewards() <= total assets always and pending rewards never exceeds vesting.assets
    function echidna_pending_rewards_lt_total_assets() external view returns (bool) {
        uint256 pending = staking.pendingRewards();
        uint256 totalAssets = staking.totalAssets();

        return pending <= totalAssets;
    }

    // Calling setVestingPeriod(new) respects bounds
    function echidna_setVestingPeriod_bounds() public view returns (bool) {
        (, uint128 period,) = staking.vesting();
        return period == 0 || (period > staking.MIN_VESTING_PERIOD() && period < staking.MAX_VESTING_PERIOD());
    }

    /// totalAssets() + pendingRewards() == asset.balanceOf(staking)
    function echidna_totalAssets_pending_sum_matches_balance() external view returns (bool) {
        uint256 balance = asset.balanceOf(address(staking));
        uint256 pending = staking.pendingRewards();
        uint256 totalAssets = staking.totalAssets();

        return totalAssets + pending == balance;
    }

    // Cooldown period cannot exceed max
    function echidna_cooldownPeriod_in_bounds() external view returns (bool) {
        return staking.cooldownPeriod() < staking.MAX_COOLDOWN_PERIOD();
    }
}
