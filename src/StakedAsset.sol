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
} from "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {AssetSilo} from "./AssetSilo.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IRestrictedRegistry} from "./interface/IRestrictedRegistry.sol";
import {IStakedAsset} from "./interface/IStakedAsset.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC20PermitUpgradeable
} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {
    ERC4626Upgradeable
} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol";

/// @title StakedAsset
/// @notice Allows staking an asset token for a staking token
/// Rewards can be sent to this contract to reward stakers proportionally to their stake
/// Includes a vesting period over which pending rewards are linearly vested
/// Whenever a reward is paid to the contract, the vesting period resets
/// Includes a cooldown period over which a user must wait between cooldown and withdraw
/// When cooldownPeriod > 0, the normal withdraw() and redeem() functions will revert
/// Users call cooldownShares() and cooldownAssets() to initiate cooldown
/// Users can have multiple cooldowns at once denominated by cooldownIds[account]
/// Users do not earn rewards for assets during the cooldown period
/// Assets in cooldown are stored in a Silo contract until cooldown is complete
/// After the cooldown is completed, users can call unstake(id) to claim their asset tokens
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

    /// @notice Instant redeemer role can redeem shares on behalf of an owner and bypass the cooldown period
    bytes32 constant INSTANT_UNSTAKER_ROLE = keccak256("INSTANT_UNSTAKER_ROLE");

    /// @notice Cap adjuster role can change instant redemption caps
    bytes32 constant CAP_ADJUSTER_ROLE = keccak256("CAP_ADJUSTER_ROLE");

    /// @notice Max cooldown period
    uint256 public constant MAX_COOLDOWN_PERIOD = 90 days;

    /// @notice Max vesting period
    uint256 public constant MAX_VESTING_PERIOD = 90 days;

    /// @notice Min vesting period to prevent rounding errors when calculating rewards within 0.1%
    uint256 public constant MIN_VESTING_PERIOD = 1200 seconds;

    /// @notice Precision for fee calculations
    uint256 constant FEE_PRECISION = 1e18;

    /// @notice Max instant unstaking fee = 100%
    uint256 constant MAX_INSTANT_UNSTAKE_FEE = 1e18;

    /* ------------------------------------ STATE VARIABLES ------------------------------------ */

    /// @notice AssetSilo holds assets during cooldown
    AssetSilo public silo;

    /// @notice Amount of shares in cooldown for an account
    mapping(address => mapping(uint256 => Cooldown)) public cooldowns;

    /// @notice Next cooldown ID for an account
    mapping(address => uint256) cooldownIds;

    /// @notice Cooldown period for unstaking in seconds
    uint256 public cooldownPeriod;

    /// @notice Vesting data
    Vesting public vesting;

    /// @notice Keep track of restricted addresses
    mapping(address => bool) public isRestricted;

    /// @notice Cap for instant unstaking. When an instant unstake is performed, this value is decremented
    uint256 public instantUnstakeCap;

    /// @notice Instant unstaking fee charged in assets
    uint256 public instantUnstakeFee;

    /// @notice Account which receives instant unstaking fees
    address public feeRecipient;

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
    function initialize(
        string memory name_,
        string memory symbol_,
        address asset_,
        address owner_,
        uint256 _instantUnstakeFee,
        address _feeRecipient
    ) external initializer nonZeroAddress(asset_) nonZeroAddress(owner_) {
        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(name_);
        __ERC4626_init(IERC20(asset_));
        __AccessControl_init();
        silo = new AssetSilo(address(this), address(asset_));
        if (_instantUnstakeFee > MAX_INSTANT_UNSTAKE_FEE) revert ExceedsMaxInstantUnstakeFee();
        if (_feeRecipient == address(this)) revert InvalidFeeRecipient();
        instantUnstakeFee = _instantUnstakeFee;
        feeRecipient = _feeRecipient;
        _grantRole(DEFAULT_ADMIN_ROLE, owner_);
    }

    /* ------------------------------------ EXTERNAL ------------------------------------------- */

    /// @notice Get pending rewards for this contract
    /// @return amount Pending unvested rewards
    function pendingRewards() external view returns (uint256 amount) {
        amount = _pendingRewards();
    }

    /// @inheritdoc IStakedAsset
    function cooldownShares(uint256 shares) external nonRestricted(msg.sender) returns (uint256 assets, uint256 id) {
        if (shares == 0) revert InvalidCooldownAmount();
        if (shares > maxRedeem(msg.sender)) revert CooldownExceededMaxRedeem();
        // increment cooldown ID for this user
        id = cooldownIds[msg.sender]++;
        assets = previewRedeem(shares);
        uint256 cooldownEnd = (block.timestamp + cooldownPeriod);

        // store cooldown
        Cooldown storage cooldown = cooldowns[msg.sender][id];
        cooldown.assets = assets.toUint160();
        cooldown.end = cooldownEnd.toUint96();

        _withdraw(_msgSender(), address(silo), msg.sender, assets, shares);
        emit CooldownStarted(msg.sender, assets, shares, id, cooldownEnd);
        return (shares, id);
    }

    /// @inheritdoc IStakedAsset
    function cooldownAssets(uint256 assets) external nonRestricted(msg.sender) returns (uint256 shares, uint256 id) {
        if (assets == 0) revert InvalidCooldownAmount();
        if (assets > maxWithdraw(msg.sender)) revert CooldownExceededMaxWithdraw();
        shares = previewWithdraw(assets);
        // increment cooldown ID for this user
        id = cooldownIds[msg.sender]++;
        assets = previewRedeem(shares);
        uint256 cooldownEnd = (block.timestamp + cooldownPeriod);

        // store cooldown
        Cooldown storage cooldown = cooldowns[msg.sender][id];
        cooldown.assets = assets.toUint160();
        cooldown.end = cooldownEnd.toUint96();

        _withdraw(_msgSender(), address(silo), msg.sender, assets, shares);
        emit CooldownStarted(msg.sender, assets, shares, id, cooldownEnd);
    }

    /// @inheritdoc IStakedAsset
    function cancelCooldown(uint256 id) external nonRestricted(msg.sender) returns (uint256 shares) {
        if (id >= cooldownIds[msg.sender]) revert NonexistentCooldown();
        Cooldown memory cooldown = cooldowns[msg.sender][id];
        uint256 assets = uint256(cooldown.assets);
        if (assets == 0) revert ZeroCooldownAssets();
        delete cooldowns[msg.sender][id];
        shares = silo.cancel(msg.sender, assets);
        emit CooldownCancelled(msg.sender, assets, shares, id);
    }

    /// @notice Unstake shares that are in cooldown
    /// @param receiver Account to transfer assets to
    function unstake(address receiver, uint256 id)
        external
        nonRestricted(msg.sender)
        nonRestricted(receiver)
        nonZeroAddress(receiver)
    {
        Cooldown memory cooldown = cooldowns[msg.sender][id];
        if (cooldown.assets == 0) revert ZeroCooldownAssets();
        if (cooldown.end > block.timestamp) revert CooldownInProgress();
        delete cooldowns[msg.sender][id];
        silo.withdraw(receiver, cooldown.assets);
        emit Unstake(msg.sender, receiver, cooldown.assets, id);
    }

    /// @inheritdoc IStakedAsset
    function instantUnstake(uint256 assets, address receiver, address owner)
        external
        onlyRole(INSTANT_UNSTAKER_ROLE)
        nonRestricted(owner)
        nonRestricted(receiver)
        returns (uint256 shares, uint256 fee)
    {
        if (assets > instantUnstakeCap) revert ExceedsInstantUnstakeCap();
        instantUnstakeCap -= assets;

        // If instant unstake fee is set, withdraw fees to fee receiver
        fee = 0;
        if (instantUnstakeFee > 0 && feeRecipient != address(0)) {
            fee = Math.mulDiv(instantUnstakeFee, assets, FEE_PRECISION);
            shares += super.withdraw(fee, feeRecipient, owner);
        }

        // withdraw remaining assets to receiver
        shares += super.withdraw(assets - fee, receiver, owner);
        emit InstantUnstake(owner, receiver, assets, shares);
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

    /// @notice Set instant unstake cap
    /// @param cap New instant unstake cap
    function setInstantUnstakeCap(uint256 cap) external onlyRole(CAP_ADJUSTER_ROLE) {
        instantUnstakeCap = cap;
        emit InstantUnstakeCapChanged(cap);
    }

    /// @notice Set instant unstake fee as a percentage where 1e18 = 100%
    /// @param fee Instant unstaking fee
    function setInstantUnstakeFee(uint256 fee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (fee > MAX_INSTANT_UNSTAKE_FEE) revert ExceedsMaxInstantUnstakeFee();
        instantUnstakeFee = fee;
        emit InstantUnstakeFeeChanged(fee);
    }

    /// @notice Set an account to receive fees from instant unstaking
    /// @param newFeeRecipient New recipient for unstaking fees
    function setFeeRecipient(address newFeeRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newFeeRecipient == address(this)) revert InvalidFeeRecipient();
        if (instantUnstakeFee == 0 && newFeeRecipient == address(0)) revert InvalidFeeRecipient();
        feeRecipient = newFeeRecipient;
        emit FeeRecipientUpdated(newFeeRecipient);
    }

    /// @notice Withdraw assets from a restricted account.
    /// Without the ability to redeem frozen shares, a portion of rewards will be stuck in the contract
    /// Always redeems the full balance of the restricted account
    /// @param from Restricted account to redeem shares from
    /// @param to Account to transfer assets to
    /// @param isCooldown Flag to specify if restricted account is in cooldown
    /// @param id Id of cooldown
    function transferRestrictedAssets(address from, address to, bool isCooldown, uint256 id)
        external
        nonZeroAddress(to)
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (!isRestricted[from]) revert NonRestrictedAccount();
        uint256 shares = balanceOf(from);
        uint256 assets = previewRedeem(shares);

        // withdraw if restricted account has shares
        if (shares > 0) {
            _withdraw(from, to, from, assets, shares);
        }

        // withdraw from silo if account is in cooldown, ignoring cooldown time
        if (isCooldown) {
            Cooldown memory cooldown = cooldowns[from][id];
            if (cooldown.assets == 0) revert ZeroCooldownAssets();
            delete cooldowns[from][id];
            silo.withdraw(to, cooldown.assets);
            emit Unstake(from, to, cooldown.assets, id);
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
