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
    /// @notice Excessive number of shares redeemed during a withdrawal
    error ExcessiveSharesRedeemed();
    /// @notice Emergency pause
    error FMLPause();
    /// @notice Collateral vault not compatible with collateral token
    error IncompatibleCollateralVault();
    /// @notice Cannot rescue collateral token or vault token
    error InvalidRescueToken();
    /// @notice Insufficient amount received in swap
    error InsufficientAmountReceived();
    /// @notice Insufficient shares received during a vault deposit
    error InsufficientSharesReceived();
    /// @notice Emitted when a swap amount out is insufficient given price thresholds
    error InsufficientSwapPrice();
    /// @notice Zero address not allowed
    error NonZeroAddress();
    /// @notice Emitted when caller is not revenue module
    error OnlyRevenueModule();
    /// @notice Emitted if rescue ether fails
    error RescueEtherFailed();
    /// @notice Emitted if swap cap exceeded for dst token
    error SwapCapExceededDst();
    /// @notice Emitted if swap cap exceeded for src token
    error SwapCapExceededSrc();

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

    /// @notice Emitted when minimum swap price is updated for a pair of tokens
    /// @param srcToken Token to be swapped
    /// @param dstToken Token to be returned from the swap
    /// @param minAmount Minimum amount per token in
    event MinSwapPriceUpdated(address srcToken, address dstToken, uint256 minAmount);

    /// @notice Emitted when a new collateral token is added
    /// @param token Collateral token address
    /// @param vault Respective vault for the collateral token
    event CollateralAdded(address token, address vault);

    /// @notice Emitted when an existing collateral token is removed
    /// @param token Collateral token address
    /// @param vault Respective vault for the collateral token
    event CollateralRemoved(address token, address vault);

    /// @notice Emitted when revenue module gets updated
    /// @param newRevenueModule Address of new revenue module
    event RevenueModuleUpdated(address newRevenueModule);

    /// @notice Emitted when aggregation router gets updated
    /// @param swapModule Address of new swap module
    event SwapModuleUpdated(address swapModule);

    /// @notice Emitted when controller gets updated
    /// @param controller New controller address
    event ControllerUpdated(address controller);

    /// @notice Emitted when legacy shares are redeemed
    /// @param vault Vault to redeem shares for
    /// @param shares Amount of shares redeemed
    event LegacySharesRedeemed(address vault, uint256 shares);

    /// @notice Emitted when revenue is converted to collateral
    /// @param collateral Collateral token to convert
    /// @param amount Amount of revenue to convert
    event RevenueConverted(address collateral, uint256 amount);

    /// @notice Get pending revenue for a collateral type
    /// @param collateral Get revenue for a specific collateral
    function getRevenue(address collateral) external view returns (uint256 revenue);

    /// @notice Get vault total assets for a collateral
    /// @param collateral Collateral to get vault assets for
    /// @return assets Total asset value of vault for a collateral
    function getVaultAssets(address collateral) external view returns (uint256 assets);

    /// @notice Deposit collateral into underlying vault
    /// @param collateral Collateral used to deposit into vault
    /// @param amount Amount of collateral to deposit
    /// @param minShares Minimum number of shares to receive
    function deposit(address collateral, uint256 amount, uint256 minShares) external;

    /// @notice Withdraw collateral from underlying vault
    /// @param collateral Collateral to withdraw from vault
    /// @param amount Amount of collateral to withdraw
    /// @param maxShares Maximum number of shares to redeem
    function withdraw(address collateral, uint256 amount, uint256 maxShares) external;

    /// @notice Withdraw revenue accumulated by underlying vault
    /// @param collateral Collateral to withdraw
    /// @param amount Amount of collateral to withdraw
    function withdrawRevenue(address collateral, uint256 amount) external;

    /// @notice Convert revenue to collateral by declining to take revenue
    /// Used as an accounting method to "realize" revenue and offset operational costs
    /// @param collateral Collateral token to convert
    /// @param amount Amount of revenue to convert
    function convertRevenue(address collateral, uint256 amount) external;

    /// @notice Allow rebalancer to withdraw collateral with limitations
    /// @param collateral Collateral to withdraw
    /// @param amount Amount of collateral to withdraw
    function rebalance(address collateral, uint256 amount) external;

    /// @notice Swap one collateral for another
    /// @param params Generic swap parameters used to enforce swap constraints
    /// @param data Additional data passed to swap module
    function swap(bytes calldata params, bytes calldata data) external;

    /// @notice Claim rewards from Morpho's Universal Rewards Distributor
    /// @param distributor The URD contract address
    /// @param reward The reward token address (e.g., MORPHO)
    /// @param claimable The total claimable amount from merkle tree
    /// @param proof The merkle proof for this claim
    function claimMorphoRewards(address distributor, address reward, uint256 claimable, bytes32[] calldata proof)
        external;
}
