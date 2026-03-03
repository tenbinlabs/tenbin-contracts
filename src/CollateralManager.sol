// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
    AccessControlUpgradeable
} from "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {ICollateralManager} from "./interface/ICollateralManager.sol";
import {IController} from "./interface/IController.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {ISwapModule} from "./interface/ISwapModule.sol";
import {IUniversalRewardsDistributor} from "./external/morpho/IUniversalRewardsDistributor.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {ReentrancyGuardTransient} from "openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol";

/// @title Collateral Manager
/// @notice The collateral manager holds collateral backing assets in the Tenbin protocol
/// The purpose of the manager is to earn yield on collateral and provide liquidity for orders
/// Each collateral has a respective ERC4626 vault in which assets can be deposited and withdrawn
/// On mint, collateral is transferred to this contract via transferFrom()
/// On redeem, collateral is transferred from this contract via transferFrom()
///
/// The CURATOR_ROLE manages collateral in a non-custodian manner by calling the following functions:
/// deposit()           -> deposit collateral into an ERC4626 vault
/// withdraw()          -> withdraw collateral from an ERC4626 vault
/// swap()              -> swap one collateral for another collateral
///
/// Two functions are used to manage revenue:
/// getRevenue()        -> get pending revenue
/// withdrawRevenue()   -> withdraw revenue from this contract
///
/// The REBALANCER_ROLE is responsible for balancing on/off chain collateral, and can call the following function:
/// rebalance()         -> withdraw collateral to a custodian account, up to a cap
/// convertRevenue()    -> convert revenue to collateral, effectively giving up revenue
///
/// This is a UUPS upgradeable contract meant to be deployed behind an ERC1967 Proxy
contract CollateralManager is ICollateralManager, UUPSUpgradeable, AccessControlUpgradeable, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /* ------------------------------------ CONSTANTS ------------------------------------------ */

    /// @notice Admin role can add new collateral types
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Manager role can call deposit, withdraw, and swap functions
    bytes32 public constant CURATOR_ROLE = keccak256("CURATOR_ROLE");

    /// @notice Rebalancer role can withdraw collateral with cap restrictions
    bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");

    /// @notice Gatekeeper role can pause and unpause this contract
    bytes32 public constant GATEKEEPER_ROLE = keccak256("GATEKEEPER_ROLE");

    // @notice Cap adjuster role can adjust rebalance caps, swap caps, and min swap price
    bytes32 public constant CAP_ADJUSTER_ROLE = keccak256("CAP_ADJUSTER_ROLE");

    /* ------------------------------------ STATE VARIABLES ------------------------------------ */

    /// @notice Controller associated with this contract
    address public controller;

    /// @notice Module for performing collateral swaps for this contract
    address public swapModule;

    /// @notice Responsible for handling revenue and distribution
    address public revenueModule;

    /// @notice Pause status for this contract
    ManagerPauseStatus public pauseStatus;

    /// @notice Vault associated with a collateral token
    /// Each collateral used by the manager MUST have an associated ERC4626 vault
    mapping(address => IERC4626) public vaults;

    /// @notice Pending revenue for a collateral token
    mapping(address => uint256) public pendingRevenue;

    /// @notice Last total amount of collateral tokens in an underlying vault
    mapping(address => uint256) public lastTotalAssets;

    /// @notice Maximum amount the rebalancer can withdraw per collateral
    mapping(address => uint256) public rebalanceCap;

    /// @notice The swap cap for a specific token. When swapping collateral, the cap is decreased
    mapping(address => uint256) public swapCap;

    /// @notice Represents the min token amount out expected per token in
    /// @dev minSwapPrice[srcToken][dstToken]
    /// srcToken => dstToken => amount
    /// ex: minSwapPrice[dai][usdc] = 0.999e6
    /// ex: minSwapPrice[usdc][dai] = 0.999e18
    mapping(address => mapping(address => uint256)) public minSwapPrice;

    /// @notice Stores supported collateral addresses
    EnumerableSet.AddressSet internal collaterals;

    /* ------------------------------------ MODIFIERS ------------------------------------------ */

    /// @dev Revert if zero address
    modifier nonZeroAddress(address addr) {
        if (addr == address(0)) revert NonZeroAddress();
        _;
    }

    /// @dev Revert if contract is paused
    modifier notPaused() {
        if (pauseStatus == ManagerPauseStatus.FMLPause) revert FMLPause();
        _;
    }

    /// @dev Revert if caller is not revenue module
    modifier onlyRevenueModule() {
        if (msg.sender != revenueModule) revert OnlyRevenueModule();
        _;
    }

    /// @dev Disable initializers for implementation contract
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializer for this contract
    /// @param controller_ Controller for this contract
    /// @param owner_ Initial owner for default admin role
    function initialize(address controller_, address owner_) external initializer nonZeroAddress(controller_) {
        controller = controller_;
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, owner_);
    }

    /* ------------------------------------ Owner Config --------------------------------------- */

    /// @dev Add collateral support with an underlying vault
    /// @param collateral Collateral to add support for
    /// @param vault Vault for this collateral
    function addCollateral(address collateral, address vault)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonZeroAddress(collateral)
        nonZeroAddress(vault)
    {
        if (address(vaults[collateral]) != address(0)) revert CollateralAlreadySupported();
        if (IERC4626(vault).asset() != collateral) revert IncompatibleCollateralVault();
        IERC20(collateral).forceApprove(controller, type(uint256).max);
        IERC20(collateral).forceApprove(vault, type(uint256).max);
        vaults[collateral] = IERC4626(vault);
        lastTotalAssets[collateral] = _totalAssets(IERC4626(vault));
        collaterals.add(collateral);
        emit CollateralAdded(collateral, vault);
    }

    /// @notice Function to remove support for a collateral vault
    /// This is an emergency function is used in case of vault malfunction
    /// This function gives up any pending revenue that might have been earned for this collateral
    /// @param collateral Collateral to remove
    function removeCollateral(address collateral) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC4626 vault = vaults[collateral];
        if (address(vault) == address(0)) revert CollateralNotSupported();
        IERC20(collateral).forceApprove(controller, 0);
        IERC20(collateral).forceApprove(address(vault), 0);
        lastTotalAssets[collateral] = 0;
        collaterals.remove(collateral);
        delete vaults[collateral];
        emit CollateralRemoved(collateral, address(vault));
    }

    /// @notice Function to force redeem shares of a legacy vault
    /// This is an emergency function used in case of vault malfunction
    // Cannot redeem shares for an existing vault
    /// @param vault Vault to redeem shares for
    /// @param shares Amount of shares to redeem
    function redeemLegacyShares(IERC4626 vault, uint256 shares) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        address collateral = vault.asset();
        if (address(vaults[collateral]) != address(0)) revert CollateralAlreadySupported();
        vault.redeem(shares, address(this), address(this));
        emit LegacySharesRedeemed(address(vault), shares);
    }

    /// @notice Set a new controller, remove old approvals, and set new approvals
    /// @param newController New controller address
    function updateController(address newController)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonZeroAddress(newController)
    {
        IERC20 token;
        address previousController = controller;
        for (uint16 i = 0; i < collaterals.length(); ++i) {
            token = IERC20(collaterals.at(i));
            token.forceApprove(previousController, 0);
            token.forceApprove(newController, type(uint256).max);
        }
        controller = newController;
        emit ControllerUpdated(newController);
    }

    /// @notice Set a new swap module
    /// @param newSwapModule New swap module
    function setSwapModule(address newSwapModule) external onlyRole(DEFAULT_ADMIN_ROLE) nonZeroAddress(newSwapModule) {
        swapModule = newSwapModule;
        emit SwapModuleUpdated(newSwapModule);
    }

    /// @notice Set a new revenue module
    /// @param newRevenueModule New swap module
    function setRevenueModule(address newRevenueModule)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonZeroAddress(newRevenueModule)
    {
        revenueModule = newRevenueModule;
        emit RevenueModuleUpdated(newRevenueModule);
    }

    /* ------------------------------------ Admin Config --------------------------------------- */

    /// @dev Gatekeeper role can set pause status
    /// @param status New pause status
    function setPauseStatus(ManagerPauseStatus status) external onlyRole(GATEKEEPER_ROLE) {
        pauseStatus = status;
        emit PauseStatusChanged(status);
    }

    /// @notice Set the maximum amount of collateral that can be withdrawn by rebalancer
    /// @param collateral Collateral to set a new cap for
    /// @param amount Maximum amount rebalancer can withdraw
    function setRebalanceCap(address collateral, uint256 amount) external onlyRole(CAP_ADJUSTER_ROLE) {
        rebalanceCap[collateral] = amount;
        emit RebalanceCapChanged(collateral, amount);
    }

    /// @notice Set the swap cap for a collateral token
    /// When swapping a collateral, the cap will be decreased
    /// If attempting to perform a swap higher than the swap cap, the swap will fail
    /// @param collateral Collateral token to set swap cap for
    /// @param newSwapCap New swap cap
    function setSwapCap(address collateral, uint256 newSwapCap) external onlyRole(CAP_ADJUSTER_ROLE) {
        swapCap[collateral] = newSwapCap;
        emit SwapCapUpdated(collateral, newSwapCap);
    }

    /// @notice Set the minimum amount of tokens out per token in when performing a swap
    /// @param srcToken Token to be swapped out
    /// @param dstToken Token to be returned from the swap
    /// @param minAmount Amount of tokens out per token in
    function setMinSwapPrice(address srcToken, address dstToken, uint256 minAmount)
        external
        onlyRole(CAP_ADJUSTER_ROLE)
    {
        minSwapPrice[srcToken][dstToken] = minAmount;
        emit MinSwapPriceUpdated(srcToken, dstToken, minAmount);
    }

    /// @notice Rescue ether sent to this contract
    function rescueEther() external onlyRole(ADMIN_ROLE) {
        // slither-disable-next-line arbitrary-send-eth
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        if (!success) revert RescueEtherFailed();
    }

    /// @notice Rescue non-collateral and non-vault tokens sent to this contract
    /// @param token The address of the ERC20 token to be rescued
    /// @param to Recipient of rescued tokens
    /// @dev The receiver should be a trusted address to avoid external calls attack vectors
    function rescueToken(address token, address to) external onlyRole(DEFAULT_ADMIN_ROLE) nonZeroAddress(to) {
        // check for collateral
        if (address(vaults[token]) != address(0)) revert InvalidRescueToken();
        // check for vault tokens
        IERC4626 vault;
        uint256 length = collaterals.length();
        for (uint16 i = 0; i < length; ++i) {
            vault = vaults[collaterals.at(i)];
            if (address(vault) == token) revert InvalidRescueToken();
        }
        IERC20(token).safeTransfer(to, IERC20(token).balanceOf(address(this)));
    }

    /* ------------------------------------ EXTERNAL ------------------------------------------- */

    /// @inheritdoc ICollateralManager
    function getRevenue(address collateral) external view returns (uint256 revenue) {
        IERC4626 vault = vaults[collateral];
        if (address(vault) == address(0)) revert CollateralNotSupported();
        revenue = _getRevenue(collateral, vault);
    }

    /// @inheritdoc ICollateralManager
    function getVaultAssets(address collateral) external view returns (uint256 assets) {
        IERC4626 vault = vaults[collateral];
        if (address(vault) == address(0)) revert CollateralNotSupported();
        assets = _totalAssets(vault);
    }

    /// @inheritdoc ICollateralManager
    function deposit(address collateral, uint256 amount, uint256 minShares)
        external
        nonReentrant
        notPaused
        onlyRole(CURATOR_ROLE)
    {
        IERC4626 vault = vaults[collateral];
        if (address(vault) == address(0)) revert CollateralNotSupported();
        pendingRevenue[collateral] = _getRevenue(collateral, vault);
        // slither-disable-next-line reentrancy-no-eth
        uint256 shares = vault.deposit(amount, address(this));
        if (shares < minShares) revert InsufficientSharesReceived();
        lastTotalAssets[collateral] = _totalAssets(vault);
        emit Deposit(collateral, amount);
    }

    /// @inheritdoc ICollateralManager
    function withdraw(address collateral, uint256 amount, uint256 maxShares)
        external
        nonReentrant
        notPaused
        onlyRole(CURATOR_ROLE)
    {
        IERC4626 vault = vaults[collateral];
        if (address(vault) == address(0)) revert CollateralNotSupported();
        pendingRevenue[collateral] = _getRevenue(collateral, vault);
        // slither-disable-next-line reentrancy-no-eth
        uint256 shares = vault.withdraw(amount, address(this), address(this));
        if (shares > maxShares) revert ExcessiveSharesRedeemed();
        lastTotalAssets[collateral] = _totalAssets(vault);
        emit Withdraw(collateral, amount);
    }

    /// @inheritdoc ICollateralManager
    function withdrawRevenue(address collateral, uint256 amount) external nonReentrant notPaused onlyRevenueModule {
        IERC4626 vault = vaults[collateral];
        if (address(vault) == address(0)) revert CollateralNotSupported();
        uint256 revenue = _getRevenue(collateral, vault);
        if (amount > revenue) revert ExceedsPendingRevenue();
        IERC20(collateral).safeTransfer(msg.sender, amount);
        pendingRevenue[collateral] = revenue - amount;
        lastTotalAssets[collateral] = _totalAssets(vault);
        emit RevenueWithdraw(collateral, amount);
    }

    /// ICollateralManager
    function convertRevenue(address collateral, uint256 amount) external notPaused onlyRole(REBALANCER_ROLE) {
        IERC4626 vault = vaults[collateral];
        if (address(vault) == address(0)) revert CollateralNotSupported();
        uint256 revenue = _getRevenue(collateral, vault);
        if (revenue < amount) revert ExceedsPendingRevenue();
        pendingRevenue[collateral] = revenue - amount;
        lastTotalAssets[collateral] = _totalAssets(vault);
        emit RevenueConverted(collateral, amount);
    }

    /// @inheritdoc ICollateralManager
    function rebalance(address collateral, uint256 amount) external notPaused onlyRole(REBALANCER_ROLE) {
        if (amount > rebalanceCap[collateral]) revert ExceedsRebalanceCap();
        rebalanceCap[collateral] -= amount;
        IERC20(collateral).safeTransfer(IController(controller).custodian(), amount);
        emit Rebalance(collateral, amount);
    }

    /// @inheritdoc ICollateralManager
    function swap(bytes calldata parameters, bytes calldata data)
        external
        nonReentrant
        notPaused
        onlyRole(CURATOR_ROLE)
    {
        // decode and verify parameters
        ISwapModule.SwapParameters memory params = abi.decode(parameters, (ISwapModule.SwapParameters));
        if (address(vaults[params.srcToken]) == address(0)) revert CollateralNotSupported();
        if (address(vaults[params.dstToken]) == address(0)) revert CollateralNotSupported();

        // enforce swap caps
        uint256 srcTokenCap = swapCap[params.srcToken];
        uint256 dstTokenCap = swapCap[params.dstToken];
        if (params.amount > srcTokenCap) revert SwapCapExceededSrc();
        if (params.minReturnAmount > dstTokenCap) revert SwapCapExceededDst();

        // enforce minimum token amount out per token in
        uint256 minAmountPerToken = minSwapPrice[params.srcToken][params.dstToken];
        uint256 srcDecimals = 10 ** IERC20Metadata(params.srcToken).decimals();
        // minAmountOut = (amount * price) / 10 ^ src_decimals
        uint256 minAmountOut = Math.mulDiv(params.amount, minAmountPerToken, srcDecimals);
        if (params.minReturnAmount < minAmountOut) revert InsufficientSwapPrice();

        // save balance before
        uint256 balanceBefore = IERC20(params.dstToken).balanceOf(address(this));

        // transfer tokens in and perform swap
        // slither-disable-next-line reentrancy-no-eth
        IERC20(params.srcToken).safeTransfer(swapModule, params.amount);
        // slither-disable-next-line reentrancy-no-eth,reentrancy-balance
        ISwapModule(swapModule).swap(parameters, data);

        // ensure correct post-swap state
        uint256 balanceAfter = IERC20(params.dstToken).balanceOf(address(this));
        uint256 actualOut = balanceAfter - balanceBefore;
        if (actualOut < params.minReturnAmount) revert InsufficientAmountReceived();
        if (actualOut > dstTokenCap) revert SwapCapExceededDst();

        // update swap caps and emit event
        swapCap[params.srcToken] = srcTokenCap - params.amount;
        swapCap[params.dstToken] = dstTokenCap - actualOut;
        emit Swap(params.srcToken, params.dstToken, params.amount, actualOut);
    }

    /// @inheritdoc ICollateralManager
    function claimMorphoRewards(address distributor, address reward, uint256 claimable, bytes32[] calldata proof)
        external
        nonReentrant
        onlyRevenueModule
    {
        uint256 balance = IERC20(reward).balanceOf(address(this));
        IUniversalRewardsDistributor(distributor).claim(address(this), reward, claimable, proof);
        IERC20(reward).safeTransfer(revenueModule, IERC20(reward).balanceOf(address(this)) - balance);
    }

    /* ------------------------------------ INTERNAL ------------------------------------------- */

    /// @dev Internal function to calculate total assets for a vault based on balance
    /// @param vault Vault to calculate total assets for
    /// @return totalAssets Total assets for `vault`
    function _totalAssets(IERC4626 vault) internal view returns (uint256 totalAssets) {
        totalAssets = vault.convertToAssets(vault.balanceOf(address(this)));
    }

    /// @dev Internal function to get current total revenue
    /// If a loss is incurred, it will be subtracted from the revenue or zeroed out
    /// @param collateral Collateral to get revenue for
    /// @param vault Collateral corresponding vault
    function _getRevenue(address collateral, IERC4626 vault) internal view returns (uint256 revenue) {
        uint256 previousRevenue = pendingRevenue[collateral];
        uint256 totalAssets = _totalAssets(vault);
        uint256 lastTotal = lastTotalAssets[collateral];
        if (totalAssets > lastTotal) {
            uint256 gain = totalAssets - lastTotal;
            revenue = previousRevenue + gain;
        } else if (totalAssets < lastTotal) {
            uint256 loss = lastTotal - totalAssets;
            revenue = loss >= previousRevenue ? 0 : previousRevenue - loss;
        } else {
            revenue = previousRevenue;
        }
    }

    /// @dev Override this function to allow only default admin role to perform upgrades
    /// @param newImplementation New implementation address
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
