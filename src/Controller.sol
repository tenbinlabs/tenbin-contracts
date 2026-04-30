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

import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {AssetToken} from "./AssetToken.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import {ICollateralManager} from "./interface/ICollateralManager.sol";
import {IController} from "./interface/IController.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC1271} from "openzeppelin-contracts/contracts/interfaces/IERC1271.sol";
import {IOracleAdapter} from "./interface/IOracleAdapter.sol";
import {IRestrictedRegistry} from "./interface/IRestrictedRegistry.sol";
import {IStakedAsset} from "./interface/IStakedAsset.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Controller
/// @notice The Controller handles mint and redemption orders for the Tenbin protocol
///
/// Tenbin is an asset token issuance platform with the goal of creating liquid, composable financial assets.
/// Assets in the Tenbin protocol are backed by two positions: off-chain futures contracts and on-chain collateral.
/// An off-chain hedging system maintains a delta one exposure of an underlying asset. On-chain collateral is used to earn low-risk yield.
/// So long as the on-chain yield equals or exceeds the off-chain funding costs, the protocol is able to peg Tenbin assets to the spot price of the real asset.
///
/// The controller contract is responsible for minting and redeeming assets in the Tenbin protocol
/// Orders are signed by KYC-approved signers and specify order details such as order type, collateral amount, asset amount, and deadline.
/// All orders have an approval signed by a minter key stored in a hardware security module and controlled by the Tenbin backend.
/// To successfully execute an order, any account can call the mint or redeem with an order, signature, context, and approval.
/// Orders are executed atomically: collateral is transferred and tokens are minted/burned in a single transaction.
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
/// Staked assets can be redeemed by specifying the staked asset address as part of the order.
/// Redeeming staked assets requires approving the controller to spend staked assets.
///
/// The `Context` struct allows passing in a flag to indicate an order should be curated as part of the transaction.
/// When performing an on demand curation, the CollateralManager `withdraw()` or `deposit()` function is called
/// before a redemption or after a mint, respectively. An additional `share_price` is passed along with curated orders
/// to act as a slippage guard when interacting with the CollateralManager vaults.
///
/// Mint and redemption limits are configurable per block. Limits are always denominated in asset amount.
/// Setting the block mint limit to max uint will disable the limit
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

    /// @dev Max amount that can be set for mint and redeem limits
    uint128 private constant MAX_LIMIT_AMOUNT = type(uint128).max;

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
    bytes32 public constant ORDER_TYPEHASH = keccak256(
        "Order(uint8 order_type,uint256 nonce,uint256 expiry,address payer,address recipient,address collateral_token,uint256 collateral_amount,address order_token,uint256 asset_amount)"
    );

    /// @notice Context typehash
    bytes32 public constant CONTEXT_TYPEHASH =
        keccak256("Context(bytes32 order_hash,uint256 share_price,bool is_curated)");

    /// @notice MAGICVALUE to be used in ERC1271 verification
    bytes4 public constant MAGICVALUE = bytes4(keccak256("isValidSignature(bytes32,bytes)"));

    /// @notice Semantic version
    string public constant VERSION = "1.4.0";

    /// @notice Asset token used for this controller
    address public immutable asset;

    /// @notice Staked asset token used for this controller
    address public immutable stakedAsset;

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
    mapping(address => mapping(uint256 => bool)) public nonces;

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

    /// @notice Asset mint limit per block
    uint128 public blockMintLimit;

    /// @notice Asset redeem limit per block
    uint128 public blockRedeemLimit;

    /// @notice Track amount minted in a block to enforce limits
    Limit mintLimit;

    /// @notice Track amount redeemed in a block to enforce limits
    Limit redeemLimit;

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
    constructor(address asset_, address stakedAsset_, uint256 ratio_, address custodian_, address owner_)
        EIP712("TenbinController", VERSION)
    {
        if (ratio_ > RATIO_PRECISION) revert InvalidRatio();
        asset = asset_;
        stakedAsset = stakedAsset_;
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
    /// @dev New delegations require signer to be active
    function setDelegateStatus(address signer, bool status) external {
        if (status && !signers[signer]) revert InvalidSigner();
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

    /// @notice Set block mint limit
    function setBlockMintLimit(uint128 newBlockMintLimit) external onlyRole(DEFAULT_ADMIN_ROLE) {
        blockMintLimit = newBlockMintLimit;
        emit MintLimitUpdated(newBlockMintLimit);
    }

    /// @notice Set block redeem limit
    function setBlockRedeemLimit(uint128 newBlockRedeemLimit) external onlyRole(DEFAULT_ADMIN_ROLE) {
        blockRedeemLimit = newBlockRedeemLimit;
        emit RedeemLimitUpdated(newBlockRedeemLimit);
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
    function mint(
        Order calldata order,
        Signature calldata signature,
        Context calldata context,
        Signature calldata approval
    ) external override {
        if (pauseStatus != ControllerPauseStatus.None) revert MintRedeemPaused();
        if (order.order_type != OrderType.Mint) revert InvalidOrderType();

        // verify order and invalidate nonce
        (address signer, bytes32 orderHash) = verifyOrder(order, signature);
        nonces[order.payer][order.nonce] = true;

        // if limit is set, enforce block mint limit
        {
            /* forge-lint: disable-start(unsafe-typecast) */
            uint256 blockLimit = blockMintLimit;
            if (blockLimit < MAX_LIMIT_AMOUNT) {
                Limit memory limit = mintLimit;
                if (block.number > limit.blockNumber) {
                    if (order.asset_amount > blockLimit) revert ExceedsBlockMintLimit();
                    mintLimit.amount = uint128(order.asset_amount);
                    mintLimit.blockNumber = uint128(block.number);
                } else {
                    uint256 newMints = limit.amount + order.asset_amount;
                    if (newMints > blockLimit) revert ExceedsBlockMintLimit();
                    mintLimit.amount = uint128(newMints);
                }
            }
            /* forge-lint: disable-end(unsafe-typecast) */
        }

        //  verify context order hash matches
        if (context.order_hash != orderHash) revert ContextOrderHashMisMatch();

        // verify approval is signed by a minter key
        verifyContext(context, approval);

        // calculate custodian amount
        uint256 custodianAmount = 0;
        uint256 currentRatio = ratio;
        if (currentRatio > 0) {
            custodianAmount = Math.mulDiv(order.collateral_amount, currentRatio, RATIO_PRECISION);
        }

        // transfer collateral to from payer to custodian and manager
        // slither-disable-next-line arbitrary-send-erc20
        IERC20(order.collateral_token).safeTransferFrom(order.payer, custodian, custodianAmount);
        // slither-disable-next-line arbitrary-send-erc20
        IERC20(order.collateral_token).safeTransferFrom(order.payer, manager, order.collateral_amount - custodianAmount);

        /// deposit in vault if is_curated enabled
        if (context.is_curated && currentRatio < RATIO_PRECISION) {
            ICollateralManager(manager)
                .deposit(order.collateral_token, order.collateral_amount - custodianAmount, context.share_price);
        }

        // mint asset tokens to recipients
        AssetToken(asset).mint(order.recipient, order.asset_amount);

        emit Mint(
            msg.sender,
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
    function redeem(
        Order calldata order,
        Signature calldata signature,
        Context calldata context,
        Signature calldata approval
    ) external override {
        if (pauseStatus != ControllerPauseStatus.None) revert MintRedeemPaused();
        if (order.order_type != OrderType.Redeem) revert InvalidOrderType();

        // verify order and invalidate nonce
        (address signer, bytes32 orderHash) = verifyOrder(order, signature);
        nonces[order.payer][order.nonce] = true;

        // if limit is set, enforce block redeem limit
        {
            /* forge-lint: disable-start(unsafe-typecast) */
            uint256 blockLimit = blockRedeemLimit;
            if (blockLimit < MAX_LIMIT_AMOUNT) {
                Limit memory limit = redeemLimit;
                if (block.number > limit.blockNumber) {
                    if (order.asset_amount > blockLimit) revert ExceedsBlockRedeemLimit();
                    redeemLimit.amount = uint128(order.asset_amount);
                    redeemLimit.blockNumber = uint128(block.number);
                } else {
                    uint256 newMints = limit.amount + order.asset_amount;
                    if (newMints > blockLimit) revert ExceedsBlockRedeemLimit();
                    redeemLimit.amount = uint128(newMints);
                }
            }
            /* forge-lint: disable-end(unsafe-typecast) */
        }

        //  verify context order hash matches
        if (context.order_hash != orderHash) revert ContextOrderHashMisMatch();

        // verify approval is signed by a minter key
        verifyContext(context, approval);

        // if curated, perform withdrawal from manager vault
        if (context.is_curated) {
            ICollateralManager(manager).withdraw(order.collateral_token, order.collateral_amount, context.share_price);
        }

        // slither-disable-next-line arbitrary-send-erc20
        IERC20(order.collateral_token).safeTransferFrom(manager, order.recipient, order.collateral_amount);

        // handle redemption for staked assets
        if (order.order_token == stakedAsset) {
            IStakedAsset(stakedAsset).instantUnstake(order.asset_amount, order.payer, order.payer);
        }

        // burn asset tokens
        AssetToken(asset).burn(order.payer, order.asset_amount);

        emit Redeem(
            msg.sender,
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
        if (order.order_token != asset && order.order_token != stakedAsset) revert InvalidOrderToken();
        if (order.order_type == OrderType.Mint && order.order_token != asset) revert InvalidOrderToken();
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
    function verifyContext(Context calldata context, Signature calldata approval) public view override {
        if (approval.signature_type != SignatureType.EIP712) revert InvalidSignatureType();
        if (approval.signature_bytes.length != 65) revert InvalidERC712Signature();
        bytes32 contextHash = hashContext(context);
        address approver = ECDSA.recover(contextHash, approval.signature_bytes);
        if (!hasRole(MINTER_ROLE, approver)) revert InvalidApproval();
        if (context.is_curated && context.share_price == 0) revert InvalidSharePrice();
    }

    /// @inheritdoc IController
    function hashOrder(Order calldata order) public view override returns (bytes32 orderHash) {
        orderHash = _hashTypedDataV4(keccak256(encodeOrder(order)));
    }

    /// @inheritdoc IController
    function hashContext(Context calldata context) public view override returns (bytes32 contextHash) {
        contextHash = _hashTypedDataV4(keccak256(encodeContext(context)));
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
            order.order_token,
            order.asset_amount
        );
    }

    /// @dev Encode context data according to EIP712 specification
    /// @param context Context data
    /// @return ABI encoded context
    function encodeContext(Context calldata context) public pure returns (bytes memory) {
        return abi.encode(CONTEXT_TYPEHASH, context.order_hash, context.share_price, context.is_curated);
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
