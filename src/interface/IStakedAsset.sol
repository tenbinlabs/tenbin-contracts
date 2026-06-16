// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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
    /// @notice Instant redeem amount exceeds cap
    error ExceedsInstantUnstakeCap();
    /// @notice Max cooldown period exceeded
    error ExceedsMaxCooldownPeriod();
    /// @notice Max vesting period exceeded
    error ExceedsMaxVestingPeriod();
    /// @notice Cannot cooldown zero assets or shares
    error InvalidCooldownAmount();
    /// @notice Cannot rescue asset token from staking contract
    error InvalidRescueToken();
    /// @notice Cannot reward zero assets
    error InvalidRewardAmount();
    /// @notice Cooldown does not exist for this account and ID
    error NonexistentCooldown();
    /// @notice Only zero address
    error NonZeroAddress();
    /// @notice Redeem and withdrawal require cooldown
    error RequiresCooldown();
    /// @notice Min cooldown period subceeded
    error SubceedsMinVestingPeriod();
    /// @notice Cooldown has already been unstaked or does not exist
    error ZeroCooldownAssets();

    /// @notice Emitted when new rewards are received by this contract
    /// @param assets Amount of asset tokens rewarded
    event RewardsReceived(uint256 assets);

    /// @notice Emitted when a linear vesting period starts for this contract
    /// @param total Total assets to vest
    /// @param end Timestamp at which vesting is completed
    event VestingStarted(uint256 total, uint256 end);

    /// @notice Emitted when an account enters cooldown for `amount`
    /// @param owner Account which entered cooldown
    /// @param shares Amount of shares redeemed to begin cooldown
    /// @param assets Amount of asset tokens to cooldown
    /// @param id Owner unique identifier for cooldown
    /// @param cooldownEnd Timestamp at which assets can be unstaked
    event CooldownStarted(address indexed owner, uint256 assets, uint256 shares, uint256 id, uint256 cooldownEnd);

    /// @notice Emitted when `from` unstakes and transfers `amount` to `to`
    /// @param owner Account which is unstaking assets
    /// @param receiver Account to receive assets
    /// @param assets Amount of assets transferred
    /// @param id Owner unique identifier for this cooldown
    event Unstake(address indexed owner, address receiver, uint256 assets, uint256 id);

    /// @notice Emitted when `from` unstakes and transfers `amount` to `to`
    /// @param owner Account which is unstaking assets
    /// @param receiver Account to receive assets
    /// @param assets Amount of assets transferred
    /// @param shares Amount of shares redeemed
    event InstantUnstake(address indexed owner, address receiver, uint256 assets, uint256 shares);

    /// @notice Emitted when an account cancels a cooldown and recevies newly minted shares
    /// @param owner Account which cancelled cooldown
    /// @param assets Amount of assets returned to the staking pool
    /// @param shares Amount of new shares minted for owner
    /// @param id Owner unique identifier for the cooldown which was cancelled
    event CooldownCancelled(address indexed owner, uint256 assets, uint256 shares, uint256 id);

    /// @notice Emitted when the vesting period gets updated
    /// @param newVestingPeriod New vesting period
    event VestingPeriodUpdated(uint128 newVestingPeriod);

    /// @notice Emitted when the cooldown period gets updated
    /// @param newCooldownPeriod New cooldown period
    event CooldownPeriodUpdated(uint256 newCooldownPeriod);

    /// @notice Emitted when the instant unstake cap is updated
    /// @param newInstantUnstakeCap New instant unstake cap
    event InstantUnstakeCapChanged(uint256 newInstantUnstakeCap);

    /// @notice Get pending rewards for this contract
    /// @return pending Pending unvested token reward
    function pendingRewards() external view returns (uint256 pending);

    /// @notice Enter cooldown for amount of `shares`
    /// Assets in cooldown are transferred to the silo contract and withdrawable at the end of cooldown
    /// @dev WARNING: Once an account enters cooldown, assets are locked and do not earn yield
    /// until the cooldown period has passed. Once cooldown has passed, call unstake() to withdraw tokens.
    /// The cancelCooldown() function can be used to cancel an active cooldown and mint shares from the assets in cooldown.
    /// @param shares Amount of shares to enter cooldown
    /// @return assets Amount of assets withdrawn for cooldown
    /// @return id Owner unique identifier for this cooldown
    function cooldownShares(uint256 shares) external returns (uint256 assets, uint256 id);

    /// @notice Enter cooldown for amount of `amount`
    /// Assets in cooldown are transferred the silo contract and withdrawable at the end of cooldown
    /// @dev WARNING: Once an account enters cooldown, assets are locked and do not earn yield
    /// until the cooldown period has passed. Once cooldown has passed, call unstake() to withdraw tokens.
    /// The cancelCooldown() function can be used to cancel an active cooldown and mint shares from the assets in cooldown.
    /// @param assets Amount of asset tokens to enter cooldown
    /// @return shares Amount of shares redeemed for cooldown
    /// @return id Owner unique identifier for this cooldown
    function cooldownAssets(uint256 assets) external returns (uint256 shares, uint256 id);

    /// @notice Cancel a cooldown for an account
    /// @dev This will mint new shares using assets in the silo
    /// @param id Owner unique identifier for this cooldown
    /// @return shares Amount of shares minted to `owner` when cancelling cooldown
    function cancelCooldown(uint256 id) external returns (uint256 shares);

    /// @notice Unstake assets in cooldown for a specific ID
    /// @param to Account to receive assets
    /// @param id Unique identifier for account in cooldown
    function unstake(address to, uint256 id) external;

    /// @notice Force withdraw assets by bypassing cooldown
    /// If set, enforces an instant unstaking cap and charges a fee
    /// Can only be initiated by INSTANT_UNSTAKER_ROLE
    /// @param assets Amount of assets to withdraw
    /// @param receiver Account to receive assets
    /// @param owner Account which hold staked assets
    /// @return shares Shares redeemed by this function
    function instantUnstake(uint256 assets, address receiver, address owner) external returns (uint256 shares);

    /// @notice Adds new rewards to the contract and extends vesting period
    /// @dev WARNING: This resets the vesting end time to block.timestamp + vesting.period,
    /// which can delay distribution of previously pending rewards.
    /// Rewarding the contract excessively and with low reward amounts can cause vesting to reset and extend currently vesting rewards.
    /// Rewards should be distributed infrequently (once per 1-3 days) and in consistent amounts to ensure smooth vesting.
    /// @param assets Amount of asset tokens to transfer to this contract as a reward
    function reward(uint256 assets) external;
}
