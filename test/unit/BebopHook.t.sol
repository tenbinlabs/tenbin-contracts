// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "../BaseTest.sol";
import {BebopHook} from "../../src/external/bebop/BebopHook.sol";
import {IController} from "../../src/interface/IController.sol";
import {Swap} from "../../src/external/bebop/IBebopHook.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {Ownable, Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";

contract BebopHookTest is BaseTest {
    BebopHook hook;
    address hookRouter = vm.addr(0x001);
    uint256 makerKey = 0xA000;
    address maker = vm.addr(makerKey);
    IController.Order validMintOrder;
    IController.Order validRedeemOrder;

    function setUp() public override {
        super.setUp();
        allowSigner(maker);
        hook = new BebopHook(hookRouter, maker, address(controller), owner);
        vm.prank(owner);
        controller.grantRole(MINTER_ROLE, maker);

        // configure ratio to simplify accounting
        vm.prank(admin);
        controller.setRatio(0);

        validMintOrder = IController.Order({
            order_type: IController.OrderType.Mint,
            expiry: block.timestamp + 1000,
            nonce: 0,
            payer: address(hook),
            recipient: address(hook),
            collateral_token: address(collateral),
            collateral_amount: 1 ether,
            order_token: address(asset),
            asset_amount: 1 ether
        });
        validRedeemOrder = IController.Order({
            order_type: IController.OrderType.Redeem,
            expiry: block.timestamp + 1000,
            nonce: 0,
            payer: address(hook),
            recipient: address(hook),
            collateral_token: address(collateral),
            collateral_amount: 1 ether,
            order_token: address(asset),
            asset_amount: 1 ether
        });
    }

    function test_SetUp() public view {
        assertEq(hook.router(), hookRouter);
        assertEq(hook.marketMaker(), maker);
        assertEq(address(hook.controller()), address(controller));
        assertEq(hook.owner(), owner);
    }

    function test_MintFromHook(uint256 amount) public {
        // set bounds
        amount = bound(amount, 1, 1e40);

        processMint(amount);

        // check balances
        assertEq(collateral.balanceOf(address(manager)), amount, "Manager balance incorrect after mint");
        assertEq(asset.balanceOf(hookRouter), amount, "Asset balance incorrect after mint");
        // Maker and hook hold no inventory
        assertEq(asset.balanceOf(maker), 0, "Asset balance incorrect after mint");
        assertEq(collateral.balanceOf(address(hook)), 0, "Hook must not hold funds");
        assertEq(asset.balanceOf(address(hook)), 0, "Hook must not hold funds");
    }

    function test_Reverts() public {
        IController.Order memory order;
        IController.Signature memory signature;
        IController.Context memory context;
        IController.Signature memory approval;

        BebopHook.IssuerData memory issuerData =
            BebopHook.IssuerData({order: order, orderSignature: signature, context: context, approval: approval});

        BebopHook.HookData memory hookData = BebopHook.HookData({
            action: uint8(IController.OrderType.Mint),
            inputToken: address(collateral),
            outputToken: address(asset),
            quoteInputAmount: 100 ether,
            quoteOutputAmount: 100 ether,
            issuerData: abi.encode(issuerData)
        });

        Swap[] memory swaps = new Swap[](1);
        swaps[0] =
            Swap({takerToken: address(collateral), makerToken: address(asset), takerAmount: 0, makerAmount: 100e18});

        vm.expectRevert(BebopHook.InvalidAmount.selector);

        vm.prank(hookRouter);
        hook.bebopHook(maker, abi.encode(hookData), swaps);

        vm.expectRevert(BebopHook.OnlyRouter.selector);
        hook.bebopHook(maker, bytes(""), swaps);
    }

    function test_RedeemFromHook(uint256 amount) public {
        // set bounds
        amount = bound(amount, 1, 1e40);

        processMint(amount);

        // Swap collateral token -> tToken
        vm.prank(hookRouter);
        asset.approve(address(hook), amount);

        IController.Order memory redeemOrder = IController.Order({
            order_type: IController.OrderType.Redeem,
            expiry: block.timestamp + 1000,
            nonce: 1,
            payer: address(hook),
            recipient: address(hook),
            collateral_token: address(collateral),
            collateral_amount: amount,
            order_token: address(asset),
            asset_amount: amount
        });

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(makerKey, hashOrder(redeemOrder));
        IController.Signature memory redeemSignature = IController.Signature({
            signature_type: IController.SignatureType.EIP712, signature_bytes: abi.encodePacked(r, s, v)
        });
        IController.Context memory redeemContext = getContext(hashOrder(redeemOrder), 0, false);
        IController.Signature memory redeemApproval = signContext(makerKey, hashContext(redeemContext));

        BebopHook.IssuerData memory redeemIssuerData = BebopHook.IssuerData({
            order: redeemOrder, orderSignature: redeemSignature, context: redeemContext, approval: redeemApproval
        });

        BebopHook.HookData memory redeemHookData = BebopHook.HookData({
            action: uint8(IController.OrderType.Redeem),
            inputToken: address(asset),
            outputToken: address(collateral),
            quoteInputAmount: amount,
            quoteOutputAmount: amount,
            issuerData: abi.encode(redeemIssuerData)
        });

        Swap[] memory redeemSwaps = new Swap[](1);
        redeemSwaps[0] = Swap({
            takerToken: address(collateral), makerToken: address(collateral), takerAmount: amount, makerAmount: amount
        });

        vm.prank(hookRouter);
        hook.bebopHook(maker, abi.encode(redeemHookData), redeemSwaps);

        assertEq(collateral.balanceOf(hookRouter), amount, "Maker collateral balance incorrect after redeem");
        // hook and maker hold no inventory
        assertEq(asset.balanceOf(maker), 0, "Maker asset balance incorrect after redeem");
        assertEq(collateral.balanceOf(address(hook)), 0, "Hook must not hold collateral");
        assertEq(asset.balanceOf(address(hook)), 0, "Hook must not hold assets");
    }

    function test_RevertWhen_MakerIsInvalid() public {
        Swap[] memory swaps = new Swap[](1);

        vm.expectRevert(BebopHook.InvalidMaker.selector);
        vm.prank(hookRouter);
        hook.bebopHook(address(0xBEEF), bytes(""), swaps);
    }

    function test_RevertWhen_InvalidSwap(uint256 amount) public {
        // set bounds
        amount = bound(amount, 1, 1e40);
        // less swaps amount than allowed
        Swap[] memory swaps = new Swap[](0);

        vm.expectRevert(BebopHook.InvalidSwapCount.selector);
        vm.prank(hookRouter);
        hook.bebopHook(maker, bytes(""), swaps);

        // more swaps amount than allowed
        swaps = new Swap[](2);

        vm.expectRevert(BebopHook.InvalidSwapCount.selector);
        vm.prank(hookRouter);
        hook.bebopHook(maker, bytes(""), swaps);

        // set up
        // mint collateral, approve controller, and allow hook to sign order
        collateral.mint(hookRouter, amount);

        vm.prank(maker);
        controller.setRecipientStatus(address(hook), true);

        // create and sign mint order
        IController.Order memory order = IController.Order({
            order_type: IController.OrderType.Mint,
            expiry: block.timestamp + 1000,
            nonce: 0,
            payer: address(hook),
            recipient: address(hook),
            collateral_token: address(collateral),
            collateral_amount: amount,
            order_token: address(asset),
            asset_amount: amount
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(makerKey, hashOrder(order));
        IController.Signature memory signature = IController.Signature({
            signature_type: IController.SignatureType.EIP712, signature_bytes: abi.encodePacked(r, s, v)
        });
        IController.Context memory context = getContext(hashOrder(order), 0, false);
        IController.Signature memory approval = signContext(makerKey, hashContext(context));

        // Swap tToken -> collateral token
        swaps = _singleSwap(address(asset), amount, amount);

        BebopHook.IssuerData memory issuerData =
            BebopHook.IssuerData({order: order, orderSignature: signature, context: context, approval: approval});

        BebopHook.HookData memory hookData = BebopHook.HookData({
            action: uint8(IController.OrderType.Mint),
            inputToken: address(collateral),
            outputToken: address(asset),
            quoteInputAmount: amount,
            quoteOutputAmount: amount,
            issuerData: abi.encode(issuerData)
        });

        vm.prank(hookRouter);
        collateral.approve(address(hook), amount);

        // Invalid swap amounts
        swaps[0].takerAmount += 1;
        vm.prank(hookRouter);
        vm.expectRevert(BebopHook.InvalidSwapAmount.selector);
        hook.bebopHook(maker, abi.encode(hookData), swaps);
        // restore amounts
        swaps[0].takerAmount -= 1;

        // Invalid swap token
        swaps[0].takerToken = address(this);
        vm.expectRevert(BebopHook.InvalidSwapToken.selector);
        vm.prank(hookRouter);
        hook.bebopHook(maker, abi.encode(hookData), swaps);
    }

    function test_RevertWhen_CallerIsNotRouter() public {
        Swap[] memory swaps = new Swap[](1);

        vm.expectRevert(BebopHook.OnlyRouter.selector);
        hook.bebopHook(maker, bytes(""), swaps);
    }

    function test_RevertWhen_ActionIsInvalid() public {
        // router setup
        collateral.mint(hookRouter, 1 ether);
        vm.prank(hookRouter);
        collateral.approve(address(hook), 1 ether);

        // Unsupported action
        BebopHook.HookData memory hookData = _hookData({
            action: type(uint8).max,
            inputToken: address(collateral),
            outputToken: address(asset),
            order: validMintOrder,
            quoteInputAmount: 1 ether,
            quoteOutputAmount: 1 ether
        });

        Swap[] memory swaps = _singleSwap(address(asset), 1 ether, 1 ether);

        vm.expectRevert(BebopHook.UnsupportedAction.selector);
        vm.prank(hookRouter);
        hook.bebopHook(maker, abi.encode(hookData), swaps);

        // wrong order type for action
        hookData = _hookData({
            action: uint8(IController.OrderType.Redeem), // Redeem action
            inputToken: address(collateral),
            outputToken: address(asset),
            order: validMintOrder, // mint order
            quoteInputAmount: 1 ether,
            quoteOutputAmount: 1 ether
        });

        vm.expectRevert(BebopHook.InvalidOrderType.selector);
        vm.prank(hookRouter);
        hook.bebopHook(maker, abi.encode(hookData), swaps);
    }

    function test_RevertWhen_OrderCollateralAmountIsZero() public {
        validMintOrder.collateral_amount = 0;

        BebopHook.HookData memory hookData = _hookData({
            action: uint8(IController.OrderType.Mint),
            inputToken: address(collateral),
            outputToken: address(asset),
            order: validMintOrder,
            quoteInputAmount: 1 ether,
            quoteOutputAmount: 1 ether
        });

        Swap[] memory swaps = _singleSwap(address(asset), 1 ether, 1 ether);

        vm.expectRevert(BebopHook.InvalidAmount.selector);
        vm.prank(hookRouter);
        hook.bebopHook(maker, abi.encode(hookData), swaps);
    }

    function test_RevertWhen_ExecutionRateIsBelowSignedQuote() public {
        BebopHook.HookData memory hookData = _hookData({
            action: uint8(IController.OrderType.Mint),
            inputToken: address(collateral),
            outputToken: address(asset),
            order: validMintOrder,
            quoteInputAmount: validMintOrder.collateral_amount,
            quoteOutputAmount: validMintOrder.asset_amount + 1
        });

        Swap[] memory swaps = _singleSwap(address(asset), validMintOrder.asset_amount, validMintOrder.asset_amount);

        vm.expectRevert(BebopHook.InputAmountMismatch.selector);
        vm.prank(hookRouter);
        hook.bebopHook(maker, abi.encode(hookData), swaps);
    }

    function test_RevertWhen_OrderPayerIsNotHook() public {
        // router setup
        collateral.mint(hookRouter, 1 ether);
        vm.prank(hookRouter);
        collateral.approve(address(hook), 1 ether);
        validMintOrder.payer = address(0xBEEF);

        BebopHook.HookData memory hookData = _hookData({
            action: uint8(IController.OrderType.Mint),
            inputToken: address(collateral),
            outputToken: address(asset),
            order: validMintOrder,
            quoteInputAmount: 1 ether,
            quoteOutputAmount: 1 ether
        });

        Swap[] memory swaps = _singleSwap(address(asset), 1 ether, 1 ether);

        vm.expectRevert(BebopHook.InvalidOrder.selector);
        vm.prank(hookRouter);
        hook.bebopHook(maker, abi.encode(hookData), swaps);
    }

    function test_RevertWhen_OrderRecipientIsNotHook() public {
        // router setup
        collateral.mint(hookRouter, 1 ether);
        vm.prank(hookRouter);
        collateral.approve(address(hook), 1 ether);

        validMintOrder.recipient = address(0xBEEF);

        BebopHook.HookData memory hookData = _hookData({
            action: uint8(IController.OrderType.Mint),
            inputToken: address(collateral),
            outputToken: address(asset),
            order: validMintOrder,
            quoteInputAmount: 1 ether,
            quoteOutputAmount: 1 ether
        });

        Swap[] memory swaps = _singleSwap(address(asset), 1 ether, 1 ether);

        vm.expectRevert(BebopHook.InvalidOrder.selector);
        vm.prank(hookRouter);
        hook.bebopHook(maker, abi.encode(hookData), swaps);
    }

    function test_RevertWhen_MintCollateralTokenDoesNotMatchInputToken() public {
        // router setup
        vm.prank(address(controller));
        asset.mint(hookRouter, 1 ether);
        vm.prank(hookRouter);
        asset.approve(address(hook), 1 ether);

        BebopHook.HookData memory hookData = _hookData({
            action: uint8(IController.OrderType.Mint),
            inputToken: address(asset),
            outputToken: address(asset),
            order: validMintOrder,
            quoteInputAmount: 1 ether,
            quoteOutputAmount: 1 ether
        });

        Swap[] memory swaps = _singleSwap(address(asset), 1 ether, 1 ether);

        vm.expectRevert(BebopHook.InvalidInputToken.selector);
        vm.prank(hookRouter);
        hook.bebopHook(maker, abi.encode(hookData), swaps);
    }

    function test_RevertWhen_MintOrderTokenDoesNotMatchOutputToken() public {
        // router setup
        collateral.mint(hookRouter, 1 ether);
        vm.prank(hookRouter);
        collateral.approve(address(hook), 1 ether);

        // for mint
        BebopHook.HookData memory hookData = _hookData({
            action: uint8(IController.OrderType.Mint),
            inputToken: address(collateral),
            outputToken: address(collateral),
            order: validMintOrder,
            quoteInputAmount: 1 ether,
            quoteOutputAmount: 1 ether
        });

        Swap[] memory swaps = _singleSwap(address(collateral), 1 ether, 1 ether);

        vm.expectRevert(BebopHook.InvalidOutputToken.selector);
        vm.prank(hookRouter);
        hook.bebopHook(maker, abi.encode(hookData), swaps);
    }

    function test_RevertWhen_RedeemTokensDoNotMatchHookData() public {
        uint256 amount = 1 ether;

        // Fund the router with the redeem input token.
        vm.prank(address(controller));
        asset.mint(hookRouter, amount);

        vm.prank(hookRouter);
        asset.approve(address(hook), amount);

        Swap[] memory swaps = _singleSwap(address(collateral), amount, amount);

        // Check invalid input token
        BebopHook.HookData memory invalidInputHookData = _hookData({
            action: uint8(IController.OrderType.Redeem),
            inputToken: address(collateral), // Should be asset
            outputToken: address(collateral),
            order: validRedeemOrder,
            quoteInputAmount: amount,
            quoteOutputAmount: amount
        });

        collateral.mint(hookRouter, amount);

        vm.prank(hookRouter);
        collateral.approve(address(hook), amount);

        vm.expectRevert(BebopHook.InvalidInputToken.selector);
        vm.prank(hookRouter);
        hook.bebopHook(maker, abi.encode(invalidInputHookData), swaps);

        // Check invalid output token
        BebopHook.HookData memory invalidOutputHookData = _hookData({
            action: uint8(IController.OrderType.Redeem),
            inputToken: address(asset),
            outputToken: address(asset), // Should be collateral
            order: validRedeemOrder,
            quoteInputAmount: amount,
            quoteOutputAmount: amount
        });

        swaps = _singleSwap(address(asset), amount, amount);

        vm.expectRevert(BebopHook.InvalidOutputToken.selector);
        vm.prank(hookRouter);
        hook.bebopHook(maker, abi.encode(invalidOutputHookData), swaps);
    }

    function test_RevertWhen_SwapIsNotSelfSwap() public {
        // router setup
        collateral.mint(hookRouter, 1 ether);
        vm.prank(hookRouter);
        collateral.approve(address(hook), 1 ether);

        BebopHook.HookData memory hookData = _hookData({
            action: uint8(IController.OrderType.Mint),
            inputToken: address(collateral),
            outputToken: address(asset),
            order: validMintOrder,
            quoteInputAmount: 1 ether,
            quoteOutputAmount: 1 ether
        });

        Swap[] memory swaps = new Swap[](1);
        swaps[0] = Swap({
            takerToken: address(collateral), makerToken: address(asset), takerAmount: 1 ether, makerAmount: 1 ether
        });

        vm.expectRevert(BebopHook.InvalidSwapToken.selector);
        vm.prank(hookRouter);
        hook.bebopHook(maker, abi.encode(hookData), swaps);
    }

    function test_RevertWhen_SetMarketMakerToZeroAddress() public {
        vm.expectRevert(BebopHook.NonZeroAddress.selector);
        vm.prank(owner);
        hook.setMarketMaker(address(0));
    }

    function test_RevertWhen_NonOwnerSetsMarketMaker() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        hook.setMarketMaker(address(0xBEEF));
    }

    function test_RevertWhen_IsZeroAddress() public {
        vm.expectRevert(BebopHook.NonZeroAddress.selector);
        new BebopHook(address(0), maker, address(controller), owner);

        vm.expectRevert(BebopHook.NonZeroAddress.selector);
        new BebopHook(hookRouter, address(0), address(controller), owner);

        vm.expectRevert(BebopHook.NonZeroAddress.selector);
        new BebopHook(hookRouter, maker, address(0), owner);
    }

    function test_RevertPriceDrift() public {
        // Router has exactly the signed input amount.
        collateral.mint(hookRouter, 1 ether);

        vm.prank(hookRouter);
        collateral.approve(address(hook), 1 ether);

        IController.Order memory order = validMintOrder;

        // Signed quote: 1 collateral -> 1 asset.
        uint256 quoteInput = 1 ether;
        uint256 quoteOutput = 1 ether;

        // Actual order tries to mint more than quoted.
        order.collateral_amount = 1 ether;
        order.asset_amount = 1.01 ether;

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(makerKey, hashOrder(order));

        IController.Signature memory signature = IController.Signature({
            signature_type: IController.SignatureType.EIP712, signature_bytes: abi.encodePacked(r, s, v)
        });

        IController.Context memory context = getContext(hashOrder(order), 0, false);

        IController.Signature memory approval = signContext(makerKey, hashContext(context));

        BebopHook.IssuerData memory issuerData =
            BebopHook.IssuerData({order: order, orderSignature: signature, context: context, approval: approval});

        BebopHook.HookData memory hookData = BebopHook.HookData({
            action: uint8(IController.OrderType.Mint),
            inputToken: address(collateral),
            outputToken: address(asset),
            quoteInputAmount: quoteInput,
            quoteOutputAmount: quoteOutput,
            issuerData: abi.encode(issuerData)
        });

        Swap[] memory swaps = _singleSwap(address(asset), order.asset_amount, order.asset_amount);

        vm.expectRevert(BebopHook.InvalidAmount.selector);

        vm.prank(hookRouter);
        hook.bebopHook(maker, abi.encode(hookData), swaps);
    }

    function test_setMarketMaker() public {
        address newMaker = makeAddr("newMaker");
        allowSigner(newMaker);

        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit BebopHook.MarketMakerUpdated(newMaker);
        hook.setMarketMaker(newMaker);
        assertEq(hook.marketMaker(), newMaker);
    }

    function test_RevertSetMarketMaker() public {
        address newMaker = makeAddr("newMaker");
        allowSigner(newMaker);

        // zero address as new maker
        vm.prank(owner);
        vm.expectRevert(BebopHook.NonZeroAddress.selector);
        hook.setMarketMaker(address(0));

        // non owner call
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        hook.setMarketMaker(newMaker);
    }

    function test_setDelegateStatus() public {
        address signer = makeAddr("signer");
        allowSigner(signer);

        vm.prank(owner);
        hook.setDelegateStatus(signer, true);
        bool isDelegate = controller.delegates(address(hook), signer);
        assertTrue(isDelegate);
    }

    function test_RevertSetDelegateStatus() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        hook.setDelegateStatus(makeAddr("signer"), true);
    }

    function test_RevertWhen_ProducedAmountIsLessThanOutputAmount() public {
        uint256 amount = 1 ether;

        // Fund the router with the input token.
        collateral.mint(hookRouter, amount);

        vm.prank(hookRouter);
        collateral.approve(address(hook), amount);

        BebopHook.HookData memory hookData = _hookData({
            action: uint8(IController.OrderType.Mint),
            inputToken: address(collateral),
            outputToken: address(asset),
            order: validMintOrder,
            quoteInputAmount: amount,
            quoteOutputAmount: amount
        });

        Swap[] memory swaps = _singleSwap(address(asset), amount, amount);

        // Mock a successful controller call that produces no output tokens.
        // Therefore: produced == 0 < outputAmount.
        vm.mockCall(address(controller), abi.encodeWithSelector(IController.mint.selector), bytes(""));

        vm.expectRevert(BebopHook.InvalidProducedAmount.selector);
        vm.prank(hookRouter);
        hook.bebopHook(maker, abi.encode(hookData), swaps);
    }

    function test_RevertWhen_WrongOutputAmount() public {
        uint256 inputAmount = 1 ether;
        uint256 wrongOutputAmount = 0.9 ether;

        collateral.mint(hookRouter, inputAmount);

        vm.prank(hookRouter);
        collateral.approve(address(hook), inputAmount);

        BebopHook.HookData memory mintHookData = _hookData({
            action: uint8(IController.OrderType.Mint),
            inputToken: address(collateral),
            outputToken: address(asset),
            order: validMintOrder,
            quoteInputAmount: inputAmount,
            quoteOutputAmount: inputAmount
        });

        Swap[] memory mintSwaps = _singleSwap(address(asset), wrongOutputAmount, wrongOutputAmount);

        vm.expectRevert(BebopHook.InvalidAmount.selector);
        vm.prank(hookRouter);
        hook.bebopHook(maker, abi.encode(mintHookData), mintSwaps);

        // for redeem
        vm.prank(address(controller));
        asset.mint(hookRouter, inputAmount);

        vm.prank(hookRouter);
        asset.approve(address(hook), inputAmount);

        BebopHook.HookData memory redeemHookData = _hookData({
            action: uint8(IController.OrderType.Redeem),
            inputToken: address(asset),
            outputToken: address(collateral),
            order: validRedeemOrder,
            quoteInputAmount: inputAmount,
            quoteOutputAmount: inputAmount
        });

        Swap[] memory redeemSwaps = _singleSwap(address(collateral), wrongOutputAmount, wrongOutputAmount);

        vm.expectRevert(BebopHook.InvalidAmount.selector);
        vm.prank(hookRouter);
        hook.bebopHook(maker, abi.encode(redeemHookData), redeemSwaps);
    }

    function test_Revert_RescueToken() public {
        vm.prank(owner);
        vm.expectRevert(BebopHook.NonZeroAddress.selector);
        hook.rescueToken(address(collateral), address(0));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        hook.rescueToken(address(collateral), address(1));
    }

    function test_RescueToken() public {
        address to = address(1);

        // Send non asset token
        collateral.mint(address(hook), 1e18);
        assertEq(collateral.balanceOf(to), 0);
        assertEq(collateral.balanceOf(address(hook)), 1e18);

        // Rescue tokens
        vm.prank(owner);
        hook.rescueToken(address(collateral), to);
        assertEq(collateral.balanceOf(to), 1e18);
        assertEq(collateral.balanceOf(address(hook)), 0);
    }

    // Helpers
    function processMint(uint256 amount) internal {
        // mint collateral, approve controller, and allow hook to sign order
        collateral.mint(hookRouter, amount);

        vm.prank(maker);
        controller.setRecipientStatus(address(hook), true);

        // create and sign mint order
        IController.Order memory order = IController.Order({
            order_type: IController.OrderType.Mint,
            expiry: block.timestamp + 1000,
            nonce: 0,
            payer: address(hook),
            recipient: address(hook),
            collateral_token: address(collateral),
            collateral_amount: amount,
            order_token: address(asset),
            asset_amount: amount
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(makerKey, hashOrder(order));
        IController.Signature memory signature = IController.Signature({
            signature_type: IController.SignatureType.EIP712, signature_bytes: abi.encodePacked(r, s, v)
        });
        IController.Context memory context = getContext(hashOrder(order), 0, false);
        IController.Signature memory approval = signContext(makerKey, hashContext(context));

        // Swap tToken -> collateral token
        Swap[] memory swaps = _singleSwap(address(asset), amount, amount);

        BebopHook.IssuerData memory issuerData =
            BebopHook.IssuerData({order: order, orderSignature: signature, context: context, approval: approval});

        BebopHook.HookData memory hookData = BebopHook.HookData({
            action: uint8(IController.OrderType.Mint),
            inputToken: address(collateral),
            outputToken: address(asset),
            quoteInputAmount: amount,
            quoteOutputAmount: amount,
            issuerData: abi.encode(issuerData)
        });

        vm.prank(hookRouter);
        collateral.approve(address(hook), amount);

        vm.prank(hookRouter);
        hook.bebopHook(maker, abi.encode(hookData), swaps);
    }

    function _hookData(
        uint8 action,
        address inputToken,
        address outputToken,
        IController.Order memory order,
        uint256 quoteInputAmount,
        uint256 quoteOutputAmount
    ) internal pure returns (BebopHook.HookData memory) {
        IController.Signature memory signature;
        IController.Context memory context;
        IController.Signature memory approval;

        BebopHook.IssuerData memory issuerData =
            BebopHook.IssuerData({order: order, orderSignature: signature, context: context, approval: approval});

        return BebopHook.HookData({
            action: action,
            inputToken: inputToken,
            outputToken: outputToken,
            quoteInputAmount: quoteInputAmount,
            quoteOutputAmount: quoteOutputAmount,
            issuerData: abi.encode(issuerData)
        });
    }

    function _singleSwap(address token, uint256 takerAmount, uint256 makerAmount)
        internal
        pure
        returns (Swap[] memory swaps)
    {
        swaps = new Swap[](1);
        swaps[0] = Swap({takerToken: token, makerToken: token, takerAmount: takerAmount, makerAmount: makerAmount});
    }
}
