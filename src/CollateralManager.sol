// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
    AccessControlUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ICollateralManager} from "src/interface/ICollateralManager.sol";
import {IController} from "src/interface/IController.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {ISwapModule} from "src/interface/ISwapModule.sol";
import {ReentrancyGuardTransient} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {UUPSUpgradeable} from "lib/openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol";

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
/// The COLLECTOR_ROLE collects revenue. Revenue is calculated separately from collateral.
/// Two functions are used to manage revenue:
/// getRevenue()        -> get pending revenue
/// withdrawRevenue()   -> withdraw revenue from this contract
///
/// The REBALANCER_ROLE is responsible for balancing on/off chain collateral, and can call the following function:
/// rebalance()         -> withdraw collateral to a custodian account, up to a cap
///
/// This is a UUPS upgradeable contract meant to be deployed behind an ERC1967 Proxy
contract CollateralManager is ICollateralManager, UUPSUpgradeable, AccessControlUpgradeable, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    /* ------------------------------------ CONSTANTS ------------------------------------------ */

    /// @notice Admin role can add new collateral types
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Manager role can call deposit, withdraw, and swap functions
    bytes32 public constant CURATOR_ROLE = keccak256("CURATOR_ROLE");

    /// @notice Collector role can collect revenue earned by underlying vaults
    bytes32 public constant COLLECTOR_ROLE = keccak256("COLLECTOR_ROLE");

    /// @notice Rebalancer role can withdraw collateral with cap restrictions
    bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");

    /// @notice Gatekeeper role can pause and unpause this contract
    bytes32 public constant GATEKEEPER_ROLE = keccak256("GATEKEEPER_ROLE");

    // @notice Cap adjuster role can adjust rebalance caps and swap caps
    bytes32 public constant CAP_ADJUSTER_ROLE = keccak256("CAP_ADJUSTER_ROLE");

    /// @notice Precision for basis calculations. 10,000 = 100%
    uint256 internal constant BASIS_PRECISION = 10_000;

    /* ------------------------------------ STATE VARIABLES ------------------------------------ */

    /// @notice Controller associated with this contract
    address public controller;

    /// @notice Module for performing collateral swaps for this contract
    address public swapModule;

    /// @notice Pause status for this contract
    ManagerPauseStatus public pauseStatus;

    /// @notice Vault associated with a collateral token
    /// Each collateral used by the manager must have an associated ERC4626 vault
    mapping(address => IERC4626) public vaults;

    /// @notice Pending revenue for a collateral token
    mapping(address => uint256) public pendingRevenue;

    /// @notice Last total amount of collateral tokens in an underlying vault
    mapping(address => uint256) public lastTotalAssets;

    /// @notice Maximum amount the rebalancer can withdraw per collateral
    mapping(address => uint256) public rebalanceCap;

    /// @notice The swap cap for a specific token. When swapping collateral, the cap is decreased
    mapping(address => uint256) public swapCap;

    /// @notice Stores the allowed slippage between two tokens in basis points
    mapping(address => mapping(address => uint256)) public swapTolerance;

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

    /// @dev Disable initializers for implementation contract
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializer for this contract
    /// @param controller_ Controller for this contract
    /// @param owner_ Initial owner for default admin role
    function initialize(address controller_, address owner_) external initializer nonZeroAddress(controller_) {
        controller = controller_;
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
        IERC20(collateral).safeIncreaseAllowance(controller, type(uint256).max);
        IERC20(collateral).safeIncreaseAllowance(vault, type(uint256).max);
        vaults[collateral] = IERC4626(vault);
        lastTotalAssets[collateral] = IERC4626(vault).totalAssets();
        emit CollateralAdded(collateral, vault);
    }

    /// @notice Function to remove support for a collateral vault
    /// This is an emergency function is used in case of vault malfunction
    /// This function gives up any pending revenue that might have been earned for this collateral
    /// @param collateral Collateral to remove
    function removeCollateral(address collateral) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(vaults[collateral]) == address(0)) revert CollateralNotSupported();
        IERC4626 vault = vaults[collateral];
        uint256 controllerAllowance = IERC20(collateral).allowance(address(this), controller);
        uint256 vaultAllowance = IERC20(collateral).allowance(address(this), address(vault));
        IERC20(collateral).safeDecreaseAllowance(controller, controllerAllowance);
        IERC20(collateral).safeDecreaseAllowance(address(vault), vaultAllowance);
        lastTotalAssets[collateral] = 0;
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
    /// When calling this function, the admin must ensure all collaterals are included in `collaterals`
    /// @param newController New controller address
    /// @param collaterals Collateral addresses for this contract
    function updateController(address newController, address[] calldata collaterals)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonZeroAddress(newController)
    {
        IERC20 token;
        address previousController = controller;
        for (uint16 i = 0; i < collaterals.length; ++i) {
            token = IERC20(collaterals[i]);
            if (address(vaults[address(token)]) == address(0)) revert CollateralNotSupported();
            uint256 allowance = token.allowance(address(this), previousController);
            if (allowance > 0) {
                token.safeDecreaseAllowance(previousController, allowance);
            }
            token.safeIncreaseAllowance(newController, type(uint256).max);
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

    /// @notice Set the slippage tolerance between two collateral tokens
    /// @param tokenIn Token to be swapped
    /// @param tokenOut Token to be returned from the swap
    /// @param tolerance Tolerance ratio between the tokens in bps
    function setSwapTolerance(address tokenIn, address tokenOut, uint256 tolerance) external onlyRole(ADMIN_ROLE) {
        swapTolerance[tokenIn][tokenOut] = tolerance;
        emit SwapToleranceUpdated(tokenIn, tokenOut, tolerance);
    }

    /// @notice Rescue ether sent to this contract
    function rescueEther() external onlyRole(ADMIN_ROLE) {
        // slither-disable-next-line arbitrary-send-eth
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        if (!success) revert RescueEtherFailed();
    }

    /* ------------------------------------ EXTERNAL ------------------------------------------- */

    /// @inheritdoc ICollateralManager
    function getRevenue(address collateral) external view returns (uint256 revenue) {
        if (address(vaults[collateral]) == address(0)) revert CollateralNotSupported();
        return pendingRevenue[collateral] + _computeNewRevenue(collateral, vaults[collateral]);
    }

    /// @inheritdoc ICollateralManager
    function deposit(address collateral, uint256 amount) external nonReentrant notPaused onlyRole(CURATOR_ROLE) {
        IERC4626 vault = vaults[collateral];
        if (address(vault) == address(0)) revert CollateralNotSupported();
        _realizeRevenue(collateral, vault);
        // slither-disable-next-line reentrancy-no-eth
        vault.deposit(amount, address(this));
        lastTotalAssets[collateral] = vault.totalAssets();
        emit Deposit(collateral, amount);
    }

    /// @inheritdoc ICollateralManager
    function withdraw(address collateral, uint256 amount) external nonReentrant notPaused onlyRole(CURATOR_ROLE) {
        IERC4626 vault = vaults[collateral];
        if (address(vault) == address(0)) revert CollateralNotSupported();
        _realizeRevenue(collateral, vault);
        // slither-disable-next-line reentrancy-no-eth
        vault.withdraw(amount, address(this), address(this));
        lastTotalAssets[collateral] = vault.totalAssets();
        emit Withdraw(collateral, amount);
    }

    /// @inheritdoc ICollateralManager
    function withdrawRevenue(address collateral, uint256 amount)
        external
        nonReentrant
        notPaused
        onlyRole(COLLECTOR_ROLE)
    {
        IERC4626 vault = vaults[collateral];
        if (address(vault) == address(0)) revert CollateralNotSupported();
        _realizeRevenue(collateral, vault);
        uint256 totalRevenue = pendingRevenue[collateral];
        if (amount > totalRevenue) revert ExceedsPendingRevenue();
        IERC20(collateral).safeTransfer(msg.sender, amount);
        unchecked {
            pendingRevenue[collateral] = totalRevenue - amount;
        }
        lastTotalAssets[collateral] = vault.totalAssets();
        emit RevenueWithdraw(collateral, amount);
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
        if (params.amount > srcTokenCap) revert InvalidSwapAmount();
        if (params.minReturnAmount > dstTokenCap) revert InvalidSwapAmount();

        // verify swap slippage tolerance
        _verifySlippage(params);

        // save balance before
        uint256 balanceBefore = IERC20(params.dstToken).balanceOf(address(this));

        // transfer tokens in and perform swap
        // slither-disable-next-line reentrancy-no-eth
        IERC20(params.srcToken).safeTransfer(swapModule, params.amount);
        // slither-disable-next-line reentrancy-no-eth
        ISwapModule(swapModule).swap(parameters, data);

        // ensure correct post-swap state
        uint256 balanceAfter = IERC20(params.dstToken).balanceOf(address(this));
        if (balanceAfter - balanceBefore < params.minReturnAmount) revert InsufficientAmountReceived();

        // update swap caps and emit event
        swapCap[params.srcToken] = srcTokenCap - params.amount;
        swapCap[params.dstToken] = dstTokenCap - (balanceAfter - balanceBefore);
        emit Swap(params.srcToken, params.dstToken, params.amount, balanceAfter - balanceBefore);
    }

    /* ------------------------------------ INTERNAL ------------------------------------------- */

    /// @notice Verifies slippage tolerance before performing a swap
    /// @param params Swap parameters containing src token, dst token, amounts, and min return amount
    function _verifySlippage(ISwapModule.SwapParameters memory params) internal view {
        // normalize decimal amounts to compare slippage
        uint256 expectedAmountOut = _normalizeTo18(params.amount, IERC20Metadata(params.srcToken).decimals());
        uint256 minAmountOut = _normalizeTo18(params.minReturnAmount, IERC20Metadata(params.dstToken).decimals());

        // Calculate bps and verify slippage is within tolerance
        uint256 slippageBps = (expectedAmountOut - minAmountOut) * BASIS_PRECISION / expectedAmountOut;
        if (slippageBps > swapTolerance[params.srcToken][params.dstToken]) revert InvalidSlippage();
    }

    /// @dev Normalizes a token amount to 18-decimal precision.
    /// @param amount The token amount to normalize.
    /// @param decimals The token's native decimal precision.
    /// @return normalizedAmount The 18-decimal equivalent of the input amount.
    function _normalizeTo18(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        if (decimals < 18) return amount * 10 ** (18 - decimals);
        return amount / 10 ** (decimals - 18);
    }

    /// @dev Internal function to calculate and store new revenue for a collateral
    /// @param collateral Collateral to update revenue for
    /// @param vault Collateral corresponding vault
    function _realizeRevenue(address collateral, IERC4626 vault) internal {
        uint256 newRevenue = _computeNewRevenue(collateral, vault);
        if (newRevenue > 0) pendingRevenue[collateral] += newRevenue;
    }

    /// @dev Internal function to calculate new revenue for a collateral
    /// @param collateral Collateral to compute revenue for
    /// @param vault Collateral corresponding vault
    /// @return revenue New revenue earned by the collateral vault
    function _computeNewRevenue(address collateral, IERC4626 vault) internal view returns (uint256 revenue) {
        uint256 totalAssets = vault.totalAssets();
        uint256 lastTotal = lastTotalAssets[collateral];
        if (totalAssets > lastTotal) {
            unchecked {
                revenue = totalAssets - lastTotal;
            }
        }
    }

    /// @dev Override this function to allow only default admin role to perform upgrades
    /// @param newImplementation New implementation address
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
