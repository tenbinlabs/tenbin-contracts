///   __/\\\\\\\\\\\\\\\__________________________/\\\____________________________
///    _\///////\\\/////__________________________\/\\\____________________________
///     _______\/\\\_______________________________\/\\\_________/\\\_______________
///      _______\/\\\______/\\\\\\\\___/\\/\\\\\\___\/\\\________\///___/\\/\\\\\\___
///       _______\/\\\____/\\\/////\\\_\/\\\////\\\__\/\\\\\\\\\___/\\\_\/\\\////\\\__
///        _______\/\\\___/\\\\\\\\\\\__\/\\\__\//\\\_\/\\\////\\\_\/\\\_\/\\\__\//\\\_
///         _______\/\\\__\//\\///////___\/\\\___\/\\\_\/\\\__\/\\\_\/\\\_\/\\\___\/\\\_
///          _______\/\\\___\//\\\\\\\\\\_\/\\\___\/\\\_\/\\\\\\\\\__\/\\\_\/\\\___\/\\\_
///           _______\///_____\//////////__\///____\///__\/////////___\///__\///____\///__

// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
    AccessControlUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {AssetSilo} from "src/AssetSilo.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IRestrictedRegistry} from "src/interface/IRestrictedRegistry.sol";
import {IStakedAsset} from "src/interface/IStakedAsset.sol";
import {ERC20Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC20PermitUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {
    ERC4626Upgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SafeCast} from "lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {UUPSUpgradeable} from "lib/openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol";

/// @title StakedAsset
/// @notice Allows staking an asset token for a staking token
/// Rewards can be sent to this contract to reward stakers proportionally to their stake
/// Includes a vesting period over which pending rewards are linearly vested
/// Whenever a reward is paid to the contract, the vesting period resets
/// Includes a cooldown period over which a user must wait between cooldown and withdrawing
/// When cooldownPeriod > 0, the normal withdraw() and redeem() functions will revert
/// Users call cooldownShares() and cooldownAssets() to initiate cooldown
/// If a cooldown already exists for a user, initiating cooldown again with additional assets will reset the cooldown time
/// Users do not earn rewards for assets during the cooldown period
/// Assets in cooldown are stored in a Silo contract until cooldown is complete
/// After the cooldown is completed, users can call unstake() to claim their asset tokens
///
/// In order to avoid a first depositor donation attack a minimum stake should be made in the same transaction as the contract deployment
/// This is a UUPS upgradeable contract meant to be deployed behind an ERC1967 Proxy
contract StakedAsset is
    IStakedAsset,
    IRestrictedRegistry,
    UUPSUpgradeable,
    ERC20PermitUpgradeable,
    ERC4626Upgradeable,
    AccessControlUpgradeable
{
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    /* ------------------------------------ CONSTANTS ------------------------------------------ */

    /// @notice Rewarder role transfers asset tokens into the contract
    bytes32 constant REWARDER_ROLE = keccak256("REWARDER_ROLE");

    /// @notice Admin role can change vesting and cooldown period
    bytes32 constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Restricter role can change restricted status of accounts
    bytes32 constant RESTRICTER_ROLE = keccak256("RESTRICTER_ROLE");

    /// @notice Max cooldown period
    uint256 public constant MAX_COOLDOWN_PERIOD = 90 days;

    /// @notice Max vesting period
    uint256 public constant MAX_VESTING_PERIOD = 90 days;

    /// @notice Min vesting period to prevent rounding errors when calculating rewards within 0.1%
    uint256 public constant MIN_VESTING_PERIOD = 1200 seconds;

    /* ------------------------------------ STATE VARIABLES ------------------------------------ */

    /// @notice AssetSilo holds assets during cooldown
    AssetSilo public silo;

    /// @notice Amount of shares in cooldown for an account
    mapping(address => Cooldown) public cooldowns;

    /// @notice Cooldown period for unstaking in seconds
    uint256 public cooldownPeriod;

    /// @notice Vesting data
    Vesting public vesting;

    /// @notice Keep track of restricted addresses
    mapping(address => bool) public isRestricted;

    /* ------------------------------------ MODIFIERS ------------------------------------------ */

    /// @dev Revert if zero address
    modifier nonZeroAddress(address addr) {
        if (addr == address(0)) revert NonZeroAddress();
        _;
    }

    /// @dev Reverts if account is restricted
    modifier nonRestricted(address account) {
        if (isRestricted[account]) revert AccountRestricted();
        _;
    }

    /// @dev Disable initializers for implementation contract
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializer for this contract
    /// @param name_ Name of this token
    /// @param symbol_ Symbol for this token
    /// @param asset_ Asset to stake and reward
    /// @param owner_ Default admin role for this contract
    function initialize(string memory name_, string memory symbol_, address asset_, address owner_)
        external
        initializer
        nonZeroAddress(asset_)
        nonZeroAddress(owner_)
    {
        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(name_);
        __ERC4626_init(IERC20(asset_));
        __AccessControl_init();
        silo = new AssetSilo(address(this), address(asset_));
        _grantRole(DEFAULT_ADMIN_ROLE, owner_);
    }

    /* ------------------------------------ EXTERNAL ------------------------------------------- */

    /// @notice Get pending rewards for this contract
    /// @return amount Pending unvested rewards
    function pendingRewards() external view returns (uint256 amount) {
        amount = _pendingRewards();
    }

    /// @inheritdoc IStakedAsset
    function cooldownShares(address owner, uint256 shares)
        external
        nonRestricted(msg.sender)
        nonRestricted(owner)
        returns (uint256 assets)
    {
        if (shares == 0) revert InvalidCooldownAmount();
        if (shares > maxRedeem(owner)) revert CooldownExceededMaxRedeem();
        assets = previewRedeem(shares);
        cooldowns[owner].assets += assets.toUint160();
        cooldowns[owner].end = (block.timestamp + cooldownPeriod).toUint96();
        _withdraw(_msgSender(), address(silo), owner, assets, shares);
        emit CooldownStarted(owner, assets);
    }

    /// @inheritdoc IStakedAsset
    function cooldownAssets(address owner, uint256 assets)
        external
        nonRestricted(msg.sender)
        nonRestricted(owner)
        returns (uint256 shares)
    {
        if (assets == 0) revert InvalidCooldownAmount();
        if (assets > maxWithdraw(owner)) revert CooldownExceededMaxWithdraw();
        shares = previewWithdraw(assets);
        cooldowns[owner].assets += assets.toUint160();
        cooldowns[owner].end = (block.timestamp + cooldownPeriod).toUint96();
        _withdraw(_msgSender(), address(silo), owner, assets, shares);
        emit CooldownStarted(owner, assets);
    }

    /// @notice Unstake shares that are in cooldown
    /// @param to Account to transfer assets to
    function unstake(address to) external nonRestricted(msg.sender) nonRestricted(to) nonZeroAddress(to) {
        Cooldown memory cooldown = cooldowns[msg.sender];
        if (cooldown.end > block.timestamp) revert CooldownInProgress();
        delete cooldowns[msg.sender];
        silo.withdraw(to, cooldown.assets);
        emit Unstake(msg.sender, to, cooldown.assets);
    }

    /// @notice Cancel a cooldown for an account
    /// @dev This will mint new shares using assets in the silo
    /// An account can only cancel its entire cooldown amount
    function cancelCooldown() external nonRestricted(msg.sender) {
        Cooldown memory cooldown = cooldowns[msg.sender];
        uint256 assets = uint256(cooldown.assets);
        if (assets == 0) revert RequiresCooldown();
        delete cooldowns[msg.sender];
        silo.cancel(msg.sender, assets);
        emit CooldownCancelled(msg.sender, assets);
    }

    /// @inheritdoc IStakedAsset
    function reward(uint256 assets) external onlyRole(REWARDER_ROLE) {
        if (vesting.period > 0) {
            uint256 pending = _pendingRewards();
            vesting.assets = pending + assets;
            vesting.end = uint128(block.timestamp) + vesting.period;
            emit VestingStarted(pending + assets, uint128(block.timestamp) + vesting.period);
        }
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);
        emit RewardsReceived(assets);
    }

    /// @notice Set a new vesting period
    /// @param newVestingPeriod New vesting period
    /// @dev Note: setting low vesting periods causes rounding issues
    /// Warning: Setting a new vesting period will cause the current vesting period to reset
    /// with the remaining rewards vested over the new vesting period
    function setVestingPeriod(uint128 newVestingPeriod) external onlyRole(ADMIN_ROLE) {
        if (newVestingPeriod > MAX_VESTING_PERIOD) revert ExceedsMaxVestingPeriod();
        if (newVestingPeriod < MIN_VESTING_PERIOD && newVestingPeriod != 0) revert SubceedsMinVestingPeriod();
        // get pending rewards and reset vesting if pending rewards > 0
        uint256 pending = _pendingRewards();
        if (pending > 0) {
            vesting.assets = pending;
            vesting.end = uint128(block.timestamp) + newVestingPeriod;
            emit VestingStarted(pending, uint128(block.timestamp) + newVestingPeriod);
        }
        vesting.period = newVestingPeriod;
        emit VestingPeriodUpdated(newVestingPeriod);
    }

    /// @notice Set a new cooldown period
    /// @param newCooldownPeriod New cooldown period
    function setCooldownPeriod(uint256 newCooldownPeriod) external onlyRole(ADMIN_ROLE) {
        if (newCooldownPeriod > MAX_COOLDOWN_PERIOD) revert ExceedsMaxCooldownPeriod();
        cooldownPeriod = newCooldownPeriod;

        emit CooldownPeriodUpdated(newCooldownPeriod);
    }

    /// @inheritdoc IRestrictedRegistry
    function setIsRestricted(address account, bool newStatus) external onlyRole(RESTRICTER_ROLE) {
        isRestricted[account] = newStatus;
        emit RestrictedStatusChanged(account, newStatus);
    }

    /// @notice Withdraw assets from a restricted account.
    /// Without the ability to redeem frozen shares, a portion of rewards will be stuck in the contract
    /// Always redeems the full balance of the restricted account
    /// @param from Restricted account to redeem shares from
    /// @param to Account to transfer assets to
    function transferRestrictedAssets(address from, address to)
        external
        nonZeroAddress(to)
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (!isRestricted[from]) revert NonRestrictedAccount();
        uint256 shares = balanceOf(from);
        uint256 assets = previewRedeem(shares);
        _withdraw(from, to, from, assets, shares);

        Cooldown memory cooldown = cooldowns[from];
        if (cooldown.assets > 0) {
            delete cooldowns[from];
            silo.withdraw(to, cooldown.assets);
        }
    }

    /* ------------------------------------ PUBLIC --------------------------------------------- */

    /// @dev Overrides the deposit function to include restricted address check.
    function deposit(uint256 assets, address receiver)
        public
        override
        nonRestricted(msg.sender)
        nonRestricted(receiver)
        returns (uint256 shares)
    {
        shares = super.deposit(assets, receiver);
    }

    /// @dev Overrides the mint function to include restricted address check
    function mint(uint256 shares, address receiver)
        public
        override
        nonRestricted(msg.sender)
        nonRestricted(receiver)
        returns (uint256 assets)
    {
        assets = super.mint(shares, receiver);
    }

    /// @notice Get number of decimals for this token
    /// @return Decimals for this token
    function decimals() public view override(ERC4626Upgradeable, ERC20Upgradeable) returns (uint8) {
        return ERC4626Upgradeable.decimals();
    }

    /// @notice Withdraw function which reverts when cooldown is active
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonRestricted(msg.sender)
        nonRestricted(receiver)
        nonRestricted(owner)
        returns (uint256)
    {
        if (cooldownPeriod > 0) revert RequiresCooldown();
        return super.withdraw(assets, receiver, owner);
    }

    /// @notice Redeem function which requires cooldown
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        nonRestricted(msg.sender)
        nonRestricted(receiver)
        nonRestricted(owner)
        returns (uint256)
    {
        if (cooldownPeriod > 0) revert RequiresCooldown();
        return super.redeem(shares, receiver, owner);
    }

    /// @notice Calculate total assets minus pending reward
    /// @return Total assets not including pending reward
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) - _pendingRewards();
    }

    /// @notice Rescue tokens sent to this contract
    /// @param token The address of the ERC20 token to be rescued
    /// @param to Recipient of rescued tokens
    /// @dev the receiver should be a trusted address to avoid external calls attack vectors
    function rescueToken(address token, address to) external onlyRole(ADMIN_ROLE) nonZeroAddress(to) {
        if (token == asset()) revert InvalidRescueToken();
        IERC20(token).safeTransfer(to, IERC20(token).balanceOf(address(this)));
    }

    /// @dev Override transfer function to prevent restricted accounts from transferring
    function transfer(address to, uint256 value)
        public
        override(IERC20, ERC20Upgradeable)
        nonRestricted(msg.sender)
        nonRestricted(to)
        returns (bool)
    {
        return super.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value)
        public
        override(IERC20, ERC20Upgradeable)
        nonRestricted(from)
        nonRestricted(to)
        nonRestricted(msg.sender)
        returns (bool)
    {
        return super.transferFrom(from, to, value);
    }

    /* ------------------------------------ INTERNAL ------------------------------------------- */

    /// @dev Calculate pending reward based on vesting time and period
    /// @return pending Pending unvested rewards
    function _pendingRewards() internal view returns (uint256 pending) {
        Vesting memory data = vesting;
        uint256 end = data.end;
        uint256 period = data.period;
        uint256 assets = data.assets;
        // slither-disable-next-line incorrect-equality
        if (period == 0) return 0;
        if (block.timestamp >= end) return 0;
        pending = Math.mulDiv(assets, end - block.timestamp, period);
    }

    /// @dev Override this function to allow only default admin role to perform upgrades
    /// @param newImplementation New implementation address
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
