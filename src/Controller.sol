// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {AssetToken} from "src/AssetToken.sol";
import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {IController} from "src/interface/IController.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC1271} from "lib/openzeppelin-contracts/contracts/interfaces/IERC1271.sol";
import {IOracleAdapter} from "src/interface/IOracleAdapter.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IRestrictedRegistry} from "src/interface/IRestrictedRegistry.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Controller
/// @notice The Controller handles mint and redemption orders for the Tenbin protocol
///
/// Tenbin is an asset token issuance platform with the goal of creating liquid, composable financial assets.
/// Assets in the Tenbin protocol are backed by two positions: off-chain futures contracts and on-chain collateral.
/// An off-chain hedging system maintains a delta one exposure of an underlying asset. On-chain collateral is used to earn low-risk yield.
/// So long as the on-chain yield equals or exceeds the off-chain funding costs, the protocol is able to peg Tenbin assets to the spot price of the real asset.
///
/// The controller contract is responsible for minting and redeeming assets in the Tenbin protocol
/// Mint and redemptions are encoded as an Order. Orders are signed by KYC-approved signers and specify order details such as
/// collateral amount, asset amount, and deadline. To successfully execute an order, a minter account calls the mint or redeem
/// with an order and signature. Orders are executed atomically: collateral is transferred and tokens are minted/burned in a single transaction.
/// All orders are executed by a minter key stored in a hardware security module and controlled by the Tenbin backend.
///
/// When a mint is executed, the collateral is split between a custodian account and a manager account.
/// The controller ratio represents the percentage of collateral to transfer to the the custodian account.
///
/// The controller has several administrative functions to manage order signers, add order beneficiaries, and allow delegating to a signer.
/// Signers are whitelisted by the SIGNER_MANAGER_ROLE.
/// Once a signer is whitelisted, orders signed by this signer are valid so long as the signer == order.payer, or the payer has delegated to a signer.
/// A signer can maintain a list of approved recipients. Only approved recipients for a signer can receive tokens during an order execution.
///
/// The controller never holds any tokens - collateral is held in a CollateralManager contract or off-ramped by a custodian account.
/// An oracle is used as a backstop to prevent order price from deviating from the oracle price.
/// However, order price is not determined by the oracle on-chain.
///
/// The controller is intended to be the only account which can mint asset tokens. In the case a new controller is created,
/// the old controller is deprecated and minting permission is set to the new controller.
contract Controller is IController, IRestrictedRegistry, AccessControl, EIP712 {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Metadata;

    /* ------------------------------------ CONSTANTS ------------------------------------------ */

    /// @dev Precision used for ratio calculations
    uint256 private constant RATIO_PRECISION = 1e18;

    /// @dev Max oracle delta tolerance. 1e18 = 100%
    uint96 private constant MAX_ORACLE_TOLERANCE = 1e18;

    /// @notice Minter role can call mint() and redeem() functions
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Admin role can add new collateral types
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // @notice Signer manager role can add or remove signers
    bytes32 public constant SIGNER_MANAGER_ROLE = keccak256("SIGNER_MANAGER_ROLE");

    /// @notice Gatekeeper role can pause and unpause functionality
    bytes32 public constant GATEKEEPER_ROLE = keccak256("GATEKEEPER_ROLE");

    /// @notice Restricter role can change restricted status of accounts
    bytes32 constant RESTRICTER_ROLE = keccak256("RESTRICTER_ROLE");

    /// @notice Order typehash
    bytes32 private constant ORDER_TYPEHASH = keccak256(
        "Order(uint8 order_type,uint256 nonce,uint256 expiry,address payer,address recipient,address collateral_token,uint256 collateral_amount,uint256 asset_amount)"
    );

    /// @notice MAGICVALUE to be used in ERC1271 verification
    bytes4 public constant MAGICVALUE = bytes4(keccak256("isValidSignature(bytes32,bytes)"));

    /// @notice Semantic version
    string public constant VERSION = "1.1.0";

    /// @notice Asset token this controller manages
    address public immutable asset;

    /* ------------------------------------ STATE VARIABLES ------------------------------------ */

    /// @notice Pause status
    ControllerPauseStatus public pauseStatus;

    /// @notice Mapping of restricted accounts
    mapping(address => bool) public isRestricted;

    /// @notice Supported collateral tokens
    mapping(address => bool) public isCollateral;

    /// @notice Whitelist for signer accounts
    mapping(address => bool) public signers;

    /// @notice Keeps track of which nonces a payer has used
    mapping(address => mapping(uint256 => bool)) nonces;

    /// @notice Approved recipients are accounts set by a whitelisted signer to receive tokens
    mapping(address => mapping(address => bool)) public recipients;

    /// @notice Payer accounts which have delegated a signer to sign orders on their behalf
    mapping(address => mapping(address => bool)) public delegates;

    /// @notice Percentage of collateral to transfer to custodian
    uint256 public ratio;

    /// @notice Address to transfer the custody portion of collateral to
    address public custodian;

    /// @notice Address to transfer the on-chain portion of collateral to
    address public manager;

    /// @notice The price oracle is used to prevent orders from exceeding a delta tolerance
    /// The oracle struct contains an oracle adapter to normalize price, and an oracle tolerance
    /// This is a security measure to prevent minting excessive tokens / redeeming at a price away from spot
    /// The oracle is not used to determine exact price, rather it enforces a price delta tolerance
    Oracle public oracle;

    /* ------------------------------------ MODIFIERS ------------------------------------------ */

    /// @dev Revert if zero address
    modifier nonZeroAddress(address addr) {
        if (addr == address(0)) revert NonZeroAddress();
        _;
    }

    /* ------------------------------------ CONSTRUCTOR ---------------------------------------- */

    /// @dev Constructor
    /// @param asset_ Address of asset token
    /// @param ratio_ Ratio of collateral transferred to custodian during mints
    /// @param custodian_ Custodian account
    /// @param owner_ Account to set as the DEFAULT_ADMIN_ROLE
    constructor(address asset_, uint256 ratio_, address custodian_, address owner_)
        EIP712("TenbinController", VERSION)
    {
        if (ratio_ > RATIO_PRECISION) revert InvalidRatio();
        asset = asset_;
        ratio = ratio_;
        custodian = custodian_;
        _grantRole(DEFAULT_ADMIN_ROLE, owner_);
    }

    /* ------------------------------------ CONFIG --------------------------------------------- */

    /// @notice Signer manager can set allowed signers
    /// @param account Signer account
    /// @param status Signer allowed status
    function setSignerStatus(address account, bool status) external onlyRole(SIGNER_MANAGER_ROLE) {
        if (status) recipients[account][account] = true;
        signers[account] = status;
        emit SignerStatusChanged(account, status);
    }

    /// @notice Set whether or not an account is a recipient for a given signer
    /// Recipients for a signer can receive tokens when an order is executed
    /// @param recipient Account to change recipient status for
    /// @param status True if an account is a valid recipient address for a signer
    function setRecipientStatus(address recipient, bool status) external {
        if (!signers[msg.sender]) revert InvalidSigner();
        recipients[msg.sender][recipient] = status;
        emit RecipientStatusChanged(msg.sender, recipient, status);
    }

    /// @notice Allow an account to delegate a signer to sign orders on their behalf
    /// @param signer Signer account to delegate to
    /// @param status Status for delegate signer
    function setDelegateStatus(address signer, bool status) external {
        if (!signers[signer]) revert InvalidSigner();
        delegates[msg.sender][signer] = status;
        emit DelegateStatusChanged(msg.sender, signer, status);
    }

    /// @dev Gatekeeper role can set pause status
    /// @param status New pause status
    function setPauseStatus(ControllerPauseStatus status) external onlyRole(GATEKEEPER_ROLE) {
        pauseStatus = status;
        emit PauseStatusChanged(status);
    }

    /// @inheritdoc IRestrictedRegistry
    function setIsRestricted(address account, bool status) external onlyRole(RESTRICTER_ROLE) {
        isRestricted[account] = status;
        emit RestrictedStatusChanged(account, status);
    }

    /// @dev Add or remove supported collateral
    /// @param collateral Collateral to change status for
    /// @param status New status
    function setIsCollateral(address collateral, bool status)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonZeroAddress(collateral)
    {
        uint8 decimals = IERC20Metadata(collateral).decimals();
        if (decimals > 18 || decimals < 6) revert InvalidCollateralDecimals();
        isCollateral[collateral] = status;
        emit CollateralStatusChanged(collateral, status);
    }

    /// @dev Change the custodian account
    /// @param newCustodian New custodian account
    function setCustodian(address newCustodian) external onlyRole(DEFAULT_ADMIN_ROLE) nonZeroAddress(newCustodian) {
        custodian = newCustodian;
        emit CustodianUpdated(newCustodian);
    }

    /// @dev Change the manager account
    /// @param newManager New manager account
    function setManager(address newManager) external onlyRole(DEFAULT_ADMIN_ROLE) nonZeroAddress(newManager) {
        manager = newManager;
        emit ManagerUpdated(newManager);
    }

    /// @dev Change the ratio. The ratio must be 1-1e18.
    /// @param newRatio New ratio
    function setRatio(uint256 newRatio) external onlyRole(ADMIN_ROLE) {
        if (newRatio > RATIO_PRECISION) revert InvalidRatio();
        ratio = newRatio;
        emit RatioUpdated(newRatio);
    }

    /// @dev Change the oracle price delta tolerance. 1e18 = 100%
    /// @param newTolerance New delta tolerance
    function setOracleTolerance(uint96 newTolerance) external onlyRole(ADMIN_ROLE) {
        if (newTolerance > MAX_ORACLE_TOLERANCE) revert NewToleranceExceedsMax();
        oracle.tolerance = newTolerance;
        emit OracleToleranceUpdated(newTolerance);
    }

    /// @dev Change the oracle tolerance. 1e18 = 100%
    /// Setting the adapter to address(0) will disable it and reset the tolerance to zero
    /// @param newAdapter New oracle adapter
    function setOracleAdapter(address newAdapter) external onlyRole(ADMIN_ROLE) {
        oracle.adapter = newAdapter;
        if (newAdapter == address(0)) oracle.tolerance = 0;
        emit OracleAdapterUpdated(newAdapter);
    }

    /// @notice Rescue tokens sent to this contract
    /// @param token The address of the ERC20 token to be rescued
    /// @param to Recipient of rescued tokens
    /// @dev The receiver should be a trusted address to avoid external calls attack vectors
    function rescueToken(address token, address to) external onlyRole(ADMIN_ROLE) nonZeroAddress(to) {
        IERC20(token).safeTransfer(to, IERC20(token).balanceOf(address(this)));
    }

    /// @notice Rescue ether sent to this contract
    function rescueEther() external onlyRole(ADMIN_ROLE) {
        // slither-disable-next-line arbitrary-send-eth
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        if (!success) revert RescueEtherFailed();
    }

    /* ------------------------------------ EXTERNAL ------------------------------------------- */

    /// @dev Allow batched calls to this contract
    /// @param data Data to delegatecall on this contract
    function multicall(bytes[] calldata data) external {
        for (uint256 i = 0; i < data.length; ++i) {
            (bool success, bytes memory returnData) = address(this).delegatecall(data[i]);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(32, returnData), mload(returnData))
                }
            }
        }
    }

    /// @inheritdoc IController
    function mint(Order calldata order, Signature calldata signature) external override onlyRole(MINTER_ROLE) {
        if (pauseStatus != ControllerPauseStatus.None) revert MintRedeemPaused();
        if (order.order_type != OrderType.Mint) revert InvalidOrderType();

        // verify order and invalidate nonce
        (address signer,) = verifyOrder(order, signature);
        nonces[order.payer][order.nonce] = true;

        // calculate custodian and manager amounts
        uint256 custodianAmount = 0;
        if (ratio > 0) {
            custodianAmount = Math.mulDiv(order.collateral_amount, ratio, RATIO_PRECISION);
        }
        uint256 managerAmount = order.collateral_amount - custodianAmount;

        // slither-disable-next-line arbitrary-send-erc20
        IERC20(order.collateral_token).safeTransferFrom(order.payer, custodian, custodianAmount);
        // slither-disable-next-line arbitrary-send-erc20
        IERC20(order.collateral_token).safeTransferFrom(order.payer, manager, managerAmount);
        AssetToken(asset).mint(order.recipient, order.asset_amount);
        emit Mint(
            signer,
            order.nonce,
            order.payer,
            order.recipient,
            order.collateral_token,
            order.collateral_amount,
            order.asset_amount
        );
    }

    /// @inheritdoc IController
    function redeem(Order calldata order, Signature calldata signature) external override onlyRole(MINTER_ROLE) {
        if (pauseStatus != ControllerPauseStatus.None) revert MintRedeemPaused();
        if (order.order_type != OrderType.Redeem) revert InvalidOrderType();

        // verify order and invalidate nonce
        (address signer,) = verifyOrder(order, signature);
        nonces[order.payer][order.nonce] = true;

        // slither-disable-next-line arbitrary-send-erc20
        IERC20(order.collateral_token).safeTransferFrom(manager, order.recipient, order.collateral_amount);
        AssetToken(asset).burn(order.payer, order.asset_amount);
        emit Redeem(
            signer,
            order.nonce,
            order.payer,
            order.recipient,
            order.collateral_token,
            order.collateral_amount,
            order.asset_amount
        );
    }

    /// @inheritdoc IController
    function verifyNonce(address payer, uint256 nonce) external view override {
        _verifyNonce(payer, nonce);
    }

    /// @notice Allows a payer to invalidate a specific nonce to cancel pending orders
    /// @param nonce The nonce to invalidate
    function invalidateNonce(uint256 nonce) external {
        nonces[msg.sender][nonce] = true;
        emit NonceInvalidated(msg.sender, nonce);
    }

    /* -------------------------------- PUBLIC --------------------------------- */

    /// @inheritdoc IController
    function verifyOrder(Order calldata order, Signature calldata signature)
        public
        view
        override
        returns (address signer, bytes32 orderHash)
    {
        // hash order and handle signature type
        orderHash = hashOrder(order);
        if (signature.signature_type == SignatureType.EIP712) {
            signer = ECDSA.recover(orderHash, signature.signature_bytes);
        } else if (signature.signature_type == SignatureType.ERC1271) {
            if (IERC1271(order.payer).isValidSignature(orderHash, signature.signature_bytes) == MAGICVALUE) {
                signer = order.payer;
            } else {
                revert InvalidERC1271Signature();
            }
        }
        // get signer and recipient details
        bool isSigner = signers[signer];
        bool isRecipient = recipients[signer][order.recipient];

        // validate order details
        if (!isSigner) revert InvalidSigner();
        _verifyNonce(order.payer, order.nonce);
        if (order.payer != signer && !delegates[order.payer][signer]) revert InvalidPayer();
        if (!isRecipient) revert InvalidRecipient();
        if (isRestricted[order.payer] || isRestricted[order.recipient]) revert AccountRestricted();
        if (!isCollateral[order.collateral_token]) revert CollateralNotSupported();
        if (order.collateral_amount == 0) revert InvalidCollateralAmount();
        if (order.asset_amount == 0) revert InvalidAssetAmount();
        if (block.timestamp > order.expiry) revert OrderExpired();

        // Calculate price and revert if delta exceeds tolerance
        Oracle memory oracleData = oracle;
        if (oracle.adapter != address(0)) {
            uint256 oraclePrice = IOracleAdapter(oracle.adapter).getPrice();

            // normalize collateral amount to 18 decimals
            uint256 decimals = IERC20Metadata(order.collateral_token).decimals();
            uint256 collateralAmount;
            if (decimals == 18) collateralAmount = order.collateral_amount;
            else collateralAmount = order.collateral_amount * 10 ** (18 - decimals);

            // calculate price delta and revert if it exceeds the oracle tolerance
            uint256 price = Math.mulDiv(collateralAmount, 1e18, order.asset_amount);
            uint256 difference = price >= oraclePrice ? price - oraclePrice : oraclePrice - price;
            uint256 delta = Math.mulDiv(difference, 1e18, oraclePrice);
            if (delta > oracleData.tolerance) revert ExceedsOracleDeltaTolerance();
        }
    }

    /// @inheritdoc IController
    function hashOrder(Order calldata order) public view override returns (bytes32 digest) {
        digest = _hashTypedDataV4(keccak256(encodeOrder(order)));
    }

    /// @dev Encode order data according to EIP712 specification
    /// @param order Order data
    /// @return ABI encoded order
    function encodeOrder(Order calldata order) public pure returns (bytes memory) {
        return abi.encode(
            ORDER_TYPEHASH,
            order.order_type,
            order.nonce,
            order.expiry,
            order.payer,
            order.recipient,
            order.collateral_token,
            order.collateral_amount,
            order.asset_amount
        );
    }

    /// @dev Get the domain separator for this contract
    /// @return Domain separator for this contract
    function getDomainSeparator() public view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @notice Contract semantic version
    /// @return Contract version
    function version() public pure returns (string memory) {
        return VERSION;
    }

    /* ------------------------------------ INTERNAL ------------------------------------------- */

    /// @dev Reverts if nonce was previously used by a payer
    /// @param payer Payer to verify nonce for
    /// @param nonce Nonce to be verified
    function _verifyNonce(address payer, uint256 nonce) internal view {
        if (nonces[payer][nonce]) revert InvalidNonce();
    }
}
