// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IController
/// @notice The Controller handles mint and redemption orders for the Tenbin protocol.
interface IController {
    /// @notice Supported signature types
    /// @param EIP712 EIP712 signature
    /// @param ERC1271 ERC1271 signature
    enum SignatureType {
        EIP712,
        ERC1271
    }

    /// @notice Supported order types
    /// @param Mint Mint order type
    /// @param Redeem Redemption order type
    enum OrderType {
        Mint,
        Redeem
    }

    /// @notice Signature data structure with support for multiple signature types
    /// @param signature_type Type of signature used to sign data
    /// @param signature_bytes Signed data
    struct Signature {
        SignatureType signature_type;
        bytes signature_bytes;
    }

    /// @notice Order data structure
    /// @param order_type Order type
    /// @param nonce Signer nonce
    /// @param expiry Order expiration time
    /// @param payer Account to transfer tokens from
    /// @param recipient Account to transfer tokens to
    /// @param collateral_token Collateral token
    /// @param collateral_amount Amount of collateral
    /// @param asset_amount Amount of asset tokens
    struct Order {
        OrderType order_type;
        uint256 nonce;
        uint256 expiry;
        address payer;
        address recipient;
        address collateral_token;
        uint256 collateral_amount;
        uint256 asset_amount;
    }

    /// @notice Oracle data structure to hold oracle adapter and tolerance
    /// @param adapter Oracle adapter used to get normalized price
    /// @param tolerance Percentage tolerance from oracle price. 1e18 = 100%
    struct Oracle {
        address adapter;
        uint96 tolerance;
    }

    /// @notice Pause states
    /// @param None Contract is not in a pause state
    /// @param MintRedeemPause Contract is not in a pause state
    /// @param FMLPause Emergency pause state
    enum ControllerPauseStatus {
        None,
        MintRedeemPause,
        FMLPause
    }

    /// @notice Event emitted when an asset is minted
    /// @param signer Signer account which signed the order
    /// @param nonce Nonce used by signer
    /// @param payer Payer account which provided collateral
    /// @param recipient Recipient account which received assets
    /// @param collateralToken Collateral used for this mint
    /// @param collateralAmount Collateral amount sent
    /// @param mintAmount Amount of asset tokens minted
    event Mint(
        address indexed signer,
        uint256 nonce,
        address indexed payer,
        address indexed recipient,
        address collateralToken,
        uint256 collateralAmount,
        uint256 mintAmount
    );

    /// @notice Event emitted when an asset is redeemed
    /// @param signer Signer account which signed the order
    /// @param nonce Nonce used by signer
    /// @param payer Payer account which provided assets
    /// @param recipient Recipient account which received collateral
    /// @param collateralToken Collateral used for this redeem
    /// @param collateralAmount Collateral amount received
    /// @param redeemAmount Amount of asset redeemed
    event Redeem(
        address indexed signer,
        uint256 nonce,
        address indexed payer,
        address indexed recipient,
        address collateralToken,
        uint256 collateralAmount,
        uint256 redeemAmount
    );

    /// @notice Emitted when mint & redemption pause status changes
    /// @param status New mint and redemption pause status
    event MintRedeemPauseStatusChanged(bool status);

    /// @notice Emitted when emergency pause status changes
    /// @param status New emergency pause status
    event PauseStatusChanged(ControllerPauseStatus status);

    /// @notice Emitted when allowed signer status changes
    /// @param signer Signer account
    /// @param status Signer allowed status
    event SignerStatusChanged(address indexed signer, bool status);

    /// @notice Emitted when a signer adds or removes an approved recipient
    /// @param signer Signer which has set status for a recipient account
    /// @param recipient Account which can receive tokens during order execution
    /// @param status Recipient status: true if a recipient can receive tokens
    event RecipientStatusChanged(address indexed signer, address indexed recipient, bool status);

    /// @notice Emitted when an account delegates a signer to sign orders on their behalf
    /// @param payer Account which allows signer to sign orders on its behalf
    /// @param signer Signer which can sign orders on behalf of payer
    /// @param status Delegate status: true if a signer can use tokens from payer during order execution
    event DelegateStatusChanged(address indexed payer, address indexed signer, bool status);

    /// @notice Emitted when collateral support status is updated
    /// @param collateral New collateral account
    /// @param status Collateral allowed status
    event CollateralStatusChanged(address indexed collateral, bool status);

    /// @notice Emitted when custodian is updated
    /// @param newCustodian New custodian account
    event CustodianUpdated(address newCustodian);

    /// @notice Emitted when manager is updated
    /// @param newManager New manager account
    event ManagerUpdated(address newManager);

    /// @notice Emitted when ratio is updated
    /// @param newRatio New ratio amount
    event RatioUpdated(uint256 newRatio);

    /// @notice Emitted when oracle tolerance is updated
    /// @param newTolerance New tolerance amount
    event OracleToleranceUpdated(uint96 newTolerance);

    /// @notice Emitted when oracle adapter is updated
    /// @param newAdapter New adapter account
    event OracleAdapterUpdated(address newAdapter);

    /// @notice Unsupported collateral type
    error CollateralNotSupported();
    /// @notice Order price exceeds oracle tolerance
    error ExceedsOracleDeltaTolerance();
    /// @notice Emergency Pause
    error FMLPause();
    /// @notice Invalid asset amount
    error InvalidAssetAmount();
    /// @notice Invalid collateral amount
    error InvalidCollateralAmount();
    /// @notice Collateral token has an invalid number of decimals
    error InvalidCollateralDecimals();
    /// @notice Invalid ERC1271 signature
    error InvalidERC1271Signature();
    /// @notice Invalid nonce
    error InvalidNonce();
    /// @notice Invalid order type
    error InvalidOrderType();
    /// @notice Invalid ratio
    error InvalidRatio();
    /// @notice Invalid payer account
    error InvalidPayer();
    /// @notice Invalid recipient account
    error InvalidRecipient();
    /// @notice Invalid signer
    error InvalidSigner();
    /// @notice Mint and Redemption Paused
    error MintRedeemPaused();
    /// @notice New oracle tolerance exceeds the maximum tolerance
    error NewToleranceExceedsMax();
    /// @notice Invalid zero address
    error NonZeroAddress();
    /// @notice Order past expiration time
    error OrderExpired();

    /// @notice Get asset token this controller manages
    /// @return Asset token address
    function asset() external view returns (address);

    /// @notice Get custodian address for this controller
    /// @return Custodian address
    function custodian() external view returns (address);

    /// @notice Get manager address for this controller
    /// @return Manager address
    function manager() external view returns (address);

    /// @notice Get the EIP712 typed data hash of an order.
    /// @param order Order data
    /// @return orderHash EIP712 typed data hash of `order`
    function hashOrder(Order calldata order) external view returns (bytes32 orderHash);

    /// @notice Verify an order signed with EIP712
    /// @param order Order data
    /// @param signature Signature of hashed order
    /// @return signer Signer of this order
    /// @return orderHash Order hash of verified order
    function verifyOrder(Order calldata order, Signature calldata signature)
        external
        view
        returns (address signer, bytes32 orderHash);

    /// @notice Verify a signer nonce.
    /// @param account to verify for
    /// @param nonce Nonce to check
    function verifyNonce(address account, uint256 nonce) external view;

    /// @notice Mint asset tokens
    /// @param order Order data
    /// @param signature Signature of hashed order
    function mint(Order calldata order, Signature calldata signature) external;

    /// @notice Redeem asset tokens
    /// @param order Order data
    /// @param signature ECDSA signature of hashed order
    function redeem(Order calldata order, Signature calldata signature) external;
}
