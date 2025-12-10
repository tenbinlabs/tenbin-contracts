// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IStakedAsset
/// @notice Staked asset interface
interface IStakedAsset {
    /// @notice Vesting data
    /// @param period Vesting period in seconds
    /// @param end Timestamp at which vesting ends
    /// @param assets Amount of assets vesting
    struct Vesting {
        uint128 period;
        uint128 end;
        uint256 assets;
    }

    /// @notice Cooldown data in a packed struct
    /// @param assets Amount of assets in cooldown
    /// @param end Timestamp at which cooldown is completed
    struct Cooldown {
        uint160 assets;
        uint96 end;
    }

    /// @notice Cannot withdraw more than max redeem
    error CooldownExceededMaxRedeem();
    /// @notice Cannot withdraw more than max withdraw
    error CooldownExceededMaxWithdraw();
    /// @notice Cooldown has not completed
    error CooldownInProgress();
    /// @notice Max cooldown period exceeded
    error ExceedsMaxCooldownPeriod();
    /// @notice Max vesting period exceeded
    error ExceedsMaxVestingPeriod();
    /// @notice Cannot rescue asset token from staking contract
    error InvalidRescueToken();
    /// @notice Only restricted account
    error NonRestrictedAccount();
    /// @notice Only zero address
    error NonZeroAddress();
    /// @notice Redeem and withdrawal require cooldown
    error RequiresCooldown();
    /// @notice Min cooldown period subceeded
    error SubceedsMinVestingPeriod();
    /// @notice Must not be vesting
    error VestingNotCompleted();

    /// @notice Emitted when new rewards are received by this contract
    /// @param assets Amount of asset tokens rewarded
    event RewardsReceived(uint256 assets);

    /// @notice Emitted when a linear vesting period starts for this contract
    /// @param total Total assets to vest
    /// @param end Timestamp at which vesting is completed
    event VestingStarted(uint256 total, uint256 end);

    /// @notice Emitted when an account enters cooldown for `amount`
    /// @param account Account which entered cooldown
    /// @param assets Amount of asset tokens to cooldown
    event CooldownStarted(address indexed account, uint256 assets);

    /// @notice Emitted when `from` unstakes and transfers `amount` to `to`
    /// @param from Account which is unstaking
    /// @param to Account to receive assets
    /// @param assets Amount of assets transferred
    event Unstake(address indexed from, address to, uint256 assets);

    /// @notice Emitted when the vesting period gets updated
    /// @param newVestingPeriod New vesting period
    event VestingPeriodUpdated(uint128 newVestingPeriod);

    /// @notice Emitted when the cooldown period gets updated
    /// @param newCooldownPeriod New cooldown period
    event CooldownPeriodUpdated(uint256 newCooldownPeriod);

    /// @notice Get pending rewards for this contract
    /// @return pending Pending unvested token reward
    function pendingRewards() external view returns (uint256 pending);

    /// @notice Reward this contract with asset tokens
    /// Rewarding the contract resets the vesting period
    /// @param assets Amount of asset tokens to transfer to this contract
    function reward(uint256 assets) external;

    /// @notice Enter cooldown for amount of `shares`
    /// Assets in cooldown are transferred to the silo contract and withdrawable at the end of cooldown
    /// If a cooldown already exists, the cooldown asset amount is increased and cooldown resets
    /// @param shares Amount of shares to enter cooldown
    /// @return assets Amount of assets withdrawn for cooldown
    function cooldownShares(uint256 shares) external returns (uint256 assets);

    /// @notice Enter cooldown for amount of `amount`
    /// Assets in cooldown are transferred the silo contract and withdrawable at the end of cooldown
    /// If a cooldown already exists, the cooldown asset amount is increased and cooldown resets
    /// @param assets Amount of asset tokens to enter cooldown
    /// @return shares Amount of shares redeemed for cooldown
    function cooldownAssets(uint256 assets) external returns (uint256 shares);

    /// @notice Unstake all assets that are in cooldown
    /// @param to Account to receive assets
    function unstake(address to) external;
}
