// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IBebopHook, Swap} from "./IBebopHook.sol";
import {IController} from "../../interface/IController.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {Ownable, Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Bebop Hook
/// @notice Executes controller mint and redeem orders through the Bebop hook interface.
///  - Router approves exactly the filled input amount per execution (needsApproval semantics).
///  - Controller orders are fixed-size ⇒ partial fills are unsupported: any fill other than
///  100% reverts with InputAmountMismatch. Maker must quote these orders fill-or-kill.
///  - Rebasing input tokens are unsupported
/// @dev https://github.com/bebop-dex/bebop-rfqa/blob/master/README.md#hooks
contract BebopHook is IBebopHook, Ownable2Step {
    using SafeERC20 for IERC20;

    /// @notice Data supplied by the Bebop router for a hook execution.
    /// @param action The controller order type to execute.
    /// @param inputToken The token transferred from the market maker.
    /// @param outputToken The token expected by the market maker.
    /// @param quoteOutputAmount The quoted amount of the output token.
    /// @param issuerData ABI-encoded controller order and authorization data.
    struct HookData {
        uint8 action;
        address inputToken;
        address outputToken;
        uint256 quoteInputAmount;
        uint256 quoteOutputAmount;
        bytes issuerData;
    }

    /// @notice Controller data required to execute a mint or redeem order.
    /// @param order The controller order to execute.
    /// @param orderSignature The signature authorizing the order.
    /// @param context Additional controller order context.
    /// @param approval The signature approving the order context.
    struct IssuerData {
        IController.Order order;
        IController.Signature orderSignature;
        IController.Context context;
        IController.Signature approval;
    }

    /// @notice Thrown when input and output amounts differ
    error InputAmountMismatch();

    /// @notice Thrown when the matching swap legs produce a zero input or output amount.
    error InvalidAmount();

    /// @notice Thrown when hook data input token is not correct order input token
    error InvalidInputToken();

    /// @notice Thrown when the hook is called with the wrong market maker address
    error InvalidMaker();

    /// @notice Thrown when faulty order is sent
    error InvalidOrder();

    /// @notice Thrown when order type doesn't match the hook data action
    error InvalidOrderType();

    /// @notice Thrown when hook data output token is not correct order output token
    error InvalidOutputToken();

    /// @notice Thrown when produced amount is not expected output amount
    error InvalidProducedAmount();

    /// @notice Thrown when the hook receives more swaps than allowed.
    error InvalidSwapCount();

    /// @notice Thrown when swap amounts differ
    error InvalidSwapAmount();

    /// @notice Thrown when swap token doesn't match the hook token
    error InvalidSwapToken();

    /// @notice Thrown when a caller other than the configured Bebop router invokes the hook.
    error OnlyRouter();

    /// @notice Thrown when the requested hook action is not supported.
    error UnsupportedAction();

    /// @notice Zero address not allowed
    error NonZeroAddress();

    /// @notice Emitted when market maker address was updated
    event MarketMakerUpdated(address indexed maker);

    /// @notice The Bebop router permitted to call this hook.
    address public immutable router;

    /// @notice The market maker whose signatures are accepted through ERC-1271.
    address public marketMaker;

    /// @notice The controller used to execute mint and redeem orders.
    IController public immutable controller;

    /// @notice Initializes the Bebop hook.
    /// @param router_ The Bebop router permitted to call the hook.
    /// @param marketMaker_ The market maker whose signatures are accepted.
    /// @param controller_ The controller used to execute orders.
    /// @param owner_ The initial contract owner.
    /// @dev marketMaker_ must already be a whitelisted signer in the controller
    constructor(address router_, address marketMaker_, address controller_, address owner_) Ownable(owner_) {
        if (router_ == address(0) || marketMaker_ == address(0) || controller_ == address(0)) {
            revert NonZeroAddress();
        }
        router = router_;
        marketMaker = marketMaker_;
        controller = IController(controller_);
        controller.setDelegateStatus(marketMaker_, true);
    }

    /// @notice Restricts function execution to the configured Bebop router.
    modifier onlyRouter() {
        require(msg.sender == router, OnlyRouter());
        _;
    }

    /// @inheritdoc IBebopHook
    /// @dev Decodes the hook and issuer data, then dispatches to the corresponding
    /// mint or redeem implementation.
    function bebopHook(address makerAddress, bytes calldata data, Swap[] calldata swaps) external override onlyRouter {
        if (makerAddress != marketMaker) revert InvalidMaker();
        if (swaps.length != 1) revert InvalidSwapCount();
        HookData memory hookData = abi.decode(data, (HookData));
        // Controller orders are fixed-size ⇒ partial fills are unsupported: any fill other than
        // 100% reverts with InputAmountMismatch. Maker must quote these orders
        // fill-or-kill.
        IssuerData memory issuerData = abi.decode(hookData.issuerData, (IssuerData));
        Swap memory swap = swaps[0];

        // 1. Output the PMM self-swap order will pull from the router must match swap data
        uint256 outputAmount = swap.makerAmount;
        // rebasing input tokens are unsupported
        IERC20 inputToken = IERC20(hookData.inputToken);
        // router approves exactly the filled input amount per execution (needsApproval semantics)
        uint256 inputAmount = inputToken.allowance(router, address(this));
        uint256 orderInputAmount = (hookData.action == uint8(IController.OrderType.Mint))
            ? issuerData.order.collateral_amount
            : issuerData.order.asset_amount;
        if (inputAmount != orderInputAmount) revert InputAmountMismatch();

        // 2. Verify hook and order data
        verifyHookData(hookData, issuerData.order, swap, inputAmount, outputAmount);

        // 3. Pull the input and convert it on the issuer's primary market.
        // slither-disable-next-line arbitrary-send-erc20
        inputToken.safeTransferFrom(router, address(this), inputAmount);
        inputToken.forceApprove(address(controller), inputAmount);

        uint256 beforeBalance = IERC20(hookData.outputToken).balanceOf(address(this));

        if (hookData.action == uint8(IController.OrderType.Mint)) {
            if (outputAmount != issuerData.order.asset_amount) revert InvalidAmount();
            // slither-disable-next-line reentrancy-balance
            controller.mint(issuerData.order, issuerData.orderSignature, issuerData.context, issuerData.approval);
        } else if (hookData.action == uint8(IController.OrderType.Redeem)) {
            if (outputAmount != issuerData.order.collateral_amount) revert InvalidAmount();
            // slither-disable-next-line reentrancy-balance
            controller.redeem(issuerData.order, issuerData.orderSignature, issuerData.context, issuerData.approval);
        }

        uint256 produced = IERC20(hookData.outputToken).balanceOf(address(this)) - beforeBalance;

        // 4. Verify and forward actual production.
        if (produced < outputAmount) revert InvalidProducedAmount();

        IERC20(hookData.outputToken).safeTransfer(router, outputAmount);
    }

    /// @notice Updates the market maker address allowed to interact with this hook
    /// @param maker New maker address
    /// @dev maker must already be a whitelisted signer in the controller
    /// @dev Requires new maker to have previously added the hook as recipient
    function setMarketMaker(address maker) external onlyOwner {
        if (maker == address(0)) revert NonZeroAddress();
        // verify hook is already a valid recipient
        if (controller.recipients(maker, address(this))) revert InvalidMaker();
        // remove delegate status of current maker
        // slither-disable-next-line reentrancy-no-eth
        controller.setDelegateStatus(marketMaker, false);
        marketMaker = maker;
        // sets new maker as delegate for hook
        // slither-disable-next-line reentrancy-no-eth
        controller.setDelegateStatus(maker, true);
        emit MarketMakerUpdated(maker);
    }

    /// @notice Allows the owner to recover tokens accidentally left on the hook.
    function rescueToken(address token, address to) external onlyOwner {
        if (token == address(0) || to == address(0)) revert NonZeroAddress();
        IERC20(token).safeTransfer(to, IERC20(token).balanceOf(address(this)));
    }

    /// @notice Allows owner to change the delegate status for an address
    /// @param maker Whitelisted signer account to delegate to
    /// @param status Status for maker signer
    function setDelegateStatus(address maker, bool status) external onlyOwner {
        controller.setDelegateStatus(maker, status);
    }

    /// @notice Verifies the order against the hook data.
    /// @param data Hook data
    /// @param order Order sent inside the issuer data
    /// @param swap Single-leg swap info
    /// @param inputAmount Amount of tokens taken
    /// @param outputAmount Amount of tokens to make
    function verifyHookData(
        HookData memory data,
        IController.Order memory order,
        Swap memory swap,
        uint256 inputAmount,
        uint256 outputAmount
    ) internal view {
        if (data.action > 1) revert UnsupportedAction();
        if (uint8(order.order_type) != data.action) revert InvalidOrderType();
        // slither-disable-start incorrect-equality
        if (inputAmount == 0 || outputAmount == 0 || data.quoteInputAmount == 0 || data.quoteOutputAmount == 0) {
            revert InvalidAmount();
        }
        // slither-disable-end incorrect-equality
        // Maker-signed rate bound: output/input must not exceed the signed quote.
        // outputAmount / inputAmount <= quoteOutputAmount / quoteInputAmount
        if (Math.mulDiv(outputAmount, data.quoteInputAmount, inputAmount) > data.quoteOutputAmount) {
            revert InvalidAmount();
        }
        if (order.payer != address(this) || order.recipient != address(this)) revert InvalidOrder();
        if (data.action == uint8(IController.OrderType.Mint)) {
            if (order.collateral_token != data.inputToken) revert InvalidInputToken();
            if (order.order_token != data.outputToken) revert InvalidOutputToken();
        } else {
            if (order.order_token != data.inputToken) revert InvalidInputToken();
            if (order.collateral_token != data.outputToken) revert InvalidOutputToken();
        }
        // PMM self swap, not the real pair
        if (swap.makerToken != swap.takerToken || swap.makerToken != data.outputToken) revert InvalidSwapToken();
        if (swap.takerAmount != swap.makerAmount) revert InvalidSwapAmount();
    }
}
