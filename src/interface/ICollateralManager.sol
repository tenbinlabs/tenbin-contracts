// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title ICollateralManager
/// @notice The collateral manager manages onchain yield and liquidity for the Tenbin protocol
interface ICollateralManager {
    /// @notice Contract pause states
    /// @param None Contract not paused
    /// @param FMLPause Emergency pause
    enum ManagerPauseStatus {
        None,
        FMLPause
    }

    /// @notice Collateral is already supported
    error CollateralAlreadySupported();
    /// @notice Collateral not supported
    error CollateralNotSupported();
    /// @notice Withdraw amount exceeds pending revenue
    error ExceedsPendingRevenue();
    /// @notice Rebalance withdrawal exceeds cap
    error ExceedsRebalanceCap();
    /// @notice Emergency pause
    error FMLPause();
    /// @notice Collateral vault not compatible with collateral token
    error IncompatibleCollateralVault();
    /// @notice Emitted when a swap exceeds the allowable slippage threshold.
    error InvalidSlippage();
    /// @notice Emitted when a swap amount exceeds the allowable cap threshold.
    error InvalidSwapAmount();
    /// @notice Insufficient amount received in swap
    error InsufficientAmountReceived();
    /// @notice Zero address not allowed
    error NonZeroAddress();
    /// @notice Emitted if rescue ether fails
    error RescueEtherFailed();

    /// @notice Emitted when collateral is deposited into its underlying vault
    /// @param collateral The collateral deposited
    /// @param amount Amount of collateral deposited
    event Deposit(address indexed collateral, uint256 amount);

    /// @notice Emitted when collateral is withdrawn from its underlying vault
    /// @param collateral The collateral withdrawn
    /// @param amount Amount of collateral withdrawn
    event Withdraw(address indexed collateral, uint256 amount);

    /// @notice Emitted when revenue is withdrawn
    /// @param collateral The collateral withdrawn
    /// @param amount Amount of collateral withdrawn
    event RevenueWithdraw(address indexed collateral, uint256 amount);

    /// @notice Emitted when rebalancer withdraws revenue
    /// @param collateral The collateral withdrawn
    /// @param amount Amount of collateral withdrawn
    event Rebalance(address indexed collateral, uint256 amount);

    /// @notice Emitted when a swap occurs for this contract
    /// @param srcToken Collateral token swapped out
    /// @param dstToken Collateral received after this swap
    /// @param srcAmount Amount of collateral swapped
    /// @param dstAmount Amount of collateral received from this swap
    event Swap(address indexed srcToken, address indexed dstToken, uint256 srcAmount, uint256 dstAmount);

    /// @notice Emitted when the pause status is changed for this contract
    /// @param status New pause status for this contract
    event PauseStatusChanged(ManagerPauseStatus status);

    /// @notice Emitted when the rebalance cap is changed for a collateral
    /// @param collateral Collateral for which cap has changed
    /// @param amount New max amount that can be withdrawn during a rebalance
    event RebalanceCapChanged(address indexed collateral, uint256 amount);

    /// @notice Emitted when token swap cap amount gets updated
    /// @param collateral Token to be capped
    /// @param newSwapCap Cap amount
    event SwapCapUpdated(address collateral, uint256 newSwapCap);

    /// @notice Emitted when token swap tolerance amount gets updated
    /// @param tokenIn Token to be swapped
    /// @param tokenOut Token to be returned from the swap
    /// @param tolerance tolerance ratio between the tokens
    event SwapToleranceUpdated(address indexed tokenIn, address indexed tokenOut, uint256 tolerance);

    /// @notice Emitted when a new collateral token is added
    /// @param token Collateral token address
    /// @param vault Respective vault for the collateral token
    event CollateralAdded(address indexed token, address indexed vault);

    /// @notice Emitted when an existing collateral token is removed
    /// @param token Collateral token address
    /// @param vault Respective vault for the collateral token
    event CollateralRemoved(address indexed token, address indexed vault);

    /// @notice Emitted when aggregation router gets updated
    /// @param swapModule Address of new swap module
    event SwapModuleUpdated(address indexed swapModule);

    /// @notice Emitted when controller gets updated
    /// @param controller New controller address
    event ControllerUpdated(address indexed controller);

    /// @notice Emitted when legacy shares are redeemed
    /// @param vault Vault to redeem shares for
    /// @param shares Amount of shares redeemed
    event LegacySharesRedeemed(address vault, uint256 shares);

    /// @notice Get pending revenue for a collateral type
    /// @param collateral Get revenue for a specific collateral
    function getRevenue(address collateral) external view returns (uint256 revenue);

    /// @notice Deposit collateral into underlying vault
    /// @param collateral Collateral used to deposit into vault
    /// @param amount Amount of collateral to deposit
    function deposit(address collateral, uint256 amount) external;

    /// @notice Withdraw collateral from underlying vault
    /// @param collateral Collateral to withdraw from vault
    /// @param amount Amount of collateral to withdraw
    function withdraw(address collateral, uint256 amount) external;

    /// @notice Withdraw revenue accumulated by underlying vault
    /// @param collateral Collateral to withdraw
    /// @param amount Amount of collateral to withdraw
    function withdrawRevenue(address collateral, uint256 amount) external;

    /// @notice Allow rebalancer to withdraw collateral with limitations
    /// @param collateral Collateral to withdraw
    /// @param amount Amount of collateral to withdraw
    function rebalance(address collateral, uint256 amount) external;

    /// @notice Swap one collateral for another
    /// @param params Generic swap parameters used to enforce swap constraints
    /// @param data Additional data passed to swap module
    function swap(bytes calldata params, bytes calldata data) external;
}
