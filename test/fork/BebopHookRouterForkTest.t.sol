// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {stdStorage, StdStorage} from "forge-std/StdStorage.sol";
import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IController} from "../../src/interface/IController.sol";
import {IBebopHook} from "../external/bebop/IBebopHook.sol";
import {IBebopRouter} from "../external/bebop/IBebopRouter.sol";
import {IBebopRouterOrder} from "../external/bebop/IBebopRouterOrder.sol";

interface IControllerRouterForkRoles {
    function delegates(address payer, address signer) external view returns (bool);
    function recipients(address signer, address recipient) external view returns (bool);
    function hasRole(bytes32 role, address account) external view returns (bool);
    function setRecipientStatus(address recipient, bool status) external;
    function setSignerStatus(address account, bool status) external;
    function verifyNonce(address account, uint256 nonce) external view;
}

interface IBebopSettlementLike {
    struct SingleOrder {
        uint256 expiry;
        address taker_address;
        address maker_address;
        uint256 maker_nonce;
        address taker_token;
        address maker_token;
        uint256 taker_amount;
        uint256 maker_amount;
        address receiver;
        uint256 packed_commands;
        uint256 flags;
    }

    struct MakerSignature {
        bytes signature;
        uint256 flags;
    }

    function swapSingle(SingleOrder calldata order, MakerSignature calldata makerSignature, uint256 filledTakerAmount)
        external;
}

/// @notice Router-tier fork test: deployed BebopRouter/BebopSettlement and live TenbinController.
/// @dev The router signer is changed only in forked state. Taker and maker signatures are test keys;
///      this proves the on-chain settlement wire format and scaling behavior, not Bebop's RFQ service.
contract BebopHookRouterForkTest is Test {
    using stdStorage for StdStorage;

    struct HookData {
        uint8 action;
        address inputToken;
        address outputToken;
        uint256 quoteInputAmount;
        uint256 quoteOutputAmount;
        bytes issuerData;
    }

    struct IssuerData {
        IController.Order order;
        IController.Signature orderSignature;
        IController.Context context;
        IController.Signature approval;
    }

    address internal constant CONTROLLER = 0x5e631388b24ec493619DAEEAef6fc34B33d97Dcd;
    address internal constant TGLD = 0x6a547b25534234bb79CE6961a23Db13DE154b6F4;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant COLLATERAL_MANAGER = 0x42F3F01D45E67294e20cE98AcFDC24dD7EA75dEa;
    address internal constant BEBOP_ROUTER = 0xBeb0009ACa35087ce7cCF11637E24dd1Aad3bf2A;
    address internal constant BEBOP_SETTLEMENT = 0xbbbbbBB520d69a9775E85b458C58c648259FAD5F;
    uint256 internal constant FORK_BLOCK = 25_605_310;

    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 internal constant SIGNER_MANAGER_ROLE = keccak256("SIGNER_MANAGER_ROLE");
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 internal constant PMM_SINGLE_ORDER_TYPEHASH = keccak256(
        "SingleOrder(uint64 partner_id,uint256 expiry,address taker_address,address maker_address,uint256 maker_nonce,address taker_token,address maker_token,uint256 taker_amount,uint256 maker_amount,address receiver,uint256 packed_commands)"
    );
    uint256 internal constant BPS = 10_000;
    uint256 internal constant SPREAD_BPS = 100;
    uint256 internal constant TENBIN_MINT_USDC_PER_TGLD = 4_078_945_652;
    uint256 internal constant TENBIN_REDEEM_USDC_PER_TGLD = 4_071_199_130;

    IController internal controller = IController(CONTROLLER);
    uint256 internal makerKey = 0xA11CE;
    address internal maker = vm.addr(makerKey);
    uint256 internal minterKey = 0xB0B;
    address internal minter = vm.addr(minterKey);
    uint256 internal routerSignerKey = 0xBEEF;
    address internal routerSigner = vm.addr(routerSignerKey);
    address internal hookOwner = makeAddr("hookOwner");
    address internal user = makeAddr("user");
    address internal receiver = makeAddr("receiver");

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), FORK_BLOCK);

        stdstore.target(CONTROLLER).sig("hasRole(bytes32,address)").with_key(SIGNER_MANAGER_ROLE)
            .with_key(address(this)).checked_write(true);
        IControllerRouterForkRoles(CONTROLLER).setSignerStatus(maker, true);
        stdstore.target(CONTROLLER).sig("hasRole(bytes32,address)").with_key(MINTER_ROLE).with_key(minter)
            .checked_write(true);
    }

    function testFork_RouterExecutesFullMintSelfSwap() public {
        uint256 inputAmount = TENBIN_MINT_USDC_PER_TGLD;
        uint256 outputAmount = _applySpread(1e18);
        (IBebopRouter router, address hook) = _deployRouterAndHook();
        uint256 makerNonce = 101;
        uint256 controllerNonce = 201;
        uint256 routerNonce = 301;

        IController.Order memory controllerOrder =
            _controllerOrder(IController.OrderType.Mint, controllerNonce, inputAmount, outputAmount, hook);
        (
            IBebopRouterOrder.BebopRouterOrder memory routerOrder,
            IBebopHook.Hook[] memory hooks,
            bytes memory pmmCalldata
        ) = _buildMintSwap(router, hook, controllerOrder, inputAmount, outputAmount, makerNonce, routerNonce);
        bytes memory routerSignature = _routerSignature(router, routerOrder, hooks, makerNonce);

        deal(USDC, user, inputAmount);
        vm.prank(user);
        IERC20(USDC).approve(address(router), inputAmount);
        vm.prank(maker);
        IERC20(TGLD).approve(BEBOP_SETTLEMENT, type(uint256).max);

        vm.prank(user);
        router.swap(_exactIn(inputAmount), routerOrder, bytes(""), routerSignature, pmmCalldata, hooks);

        assertEq(IERC20(USDC).balanceOf(user), 0, "user input consumed");
        assertEq(IERC20(TGLD).balanceOf(receiver), outputAmount, "receiver gets hook-minted output");
        assertEq(IERC20(TGLD).balanceOf(address(router)), 0, "router has no residual output");
        assertEq(IERC20(TGLD).balanceOf(hook), 0, "hook has no residual output");
        assertEq(IERC20(TGLD).balanceOf(maker), 0, "zero-inventory maker ends flat");
        assertTrue(!router.isNonceValid(user, routerNonce), "router nonce consumed");
        vm.expectRevert(IController.InvalidNonce.selector);
        controller.verifyNonce(hook, controllerNonce);
    }

    function testFork_RouterRevertsScaledMintAtomically() public {
        uint256 inputAmount = TENBIN_MINT_USDC_PER_TGLD;
        uint256 outputAmount = _applySpread(1e18);
        uint256 scaledInput = inputAmount * 99 / 100;
        (IBebopRouter router, address hook) = _deployRouterAndHook();
        uint256 makerNonce = 102;
        uint256 controllerNonce = 202;
        uint256 routerNonce = 302;

        IController.Order memory controllerOrder =
            _controllerOrder(IController.OrderType.Mint, controllerNonce, inputAmount, outputAmount, hook);
        (
            IBebopRouterOrder.BebopRouterOrder memory routerOrder,
            IBebopHook.Hook[] memory hooks,
            bytes memory pmmCalldata
        ) = _buildMintSwap(router, hook, controllerOrder, inputAmount, outputAmount, makerNonce, routerNonce);
        bytes memory routerSignature = _routerSignature(router, routerOrder, hooks, makerNonce);

        deal(USDC, user, scaledInput);
        vm.prank(user);
        IERC20(USDC).approve(address(router), scaledInput);
        vm.prank(maker);
        IERC20(TGLD).approve(BEBOP_SETTLEMENT, type(uint256).max);

        vm.prank(user);
        vm.expectRevert(bytes4(keccak256("HookExecutionFailed()")));
        router.swap(_exactIn(scaledInput), routerOrder, bytes(""), routerSignature, pmmCalldata, hooks);

        assertEq(IERC20(USDC).balanceOf(user), scaledInput, "input transfer rolled back");
        assertEq(IERC20(TGLD).balanceOf(receiver), 0, "receiver gets no partial output");
        assertEq(IERC20(TGLD).balanceOf(address(router)), 0, "router has no output");
        assertEq(IERC20(TGLD).balanceOf(hook), 0, "hook has no output");
        assertEq(IERC20(TGLD).balanceOf(maker), 0, "maker remains flat");
        assertTrue(router.isNonceValid(user, routerNonce), "router nonce rollback");
        _assertControllerNonceAvailable(hook, controllerNonce);
    }

    function testFork_RouterExecutesFullRedeemSelfSwap() public {
        uint256 inputAmount = 1e18;
        uint256 outputAmount = _applySpread(TENBIN_REDEEM_USDC_PER_TGLD);
        (IBebopRouter router, address hook) = _deployRouterAndHook();
        uint256 makerNonce = 103;
        uint256 controllerNonce = 203;
        uint256 routerNonce = 303;

        IController.Order memory controllerOrder =
            _controllerOrder(IController.OrderType.Redeem, controllerNonce, outputAmount, inputAmount, hook);
        (
            IBebopRouterOrder.BebopRouterOrder memory routerOrder,
            IBebopHook.Hook[] memory hooks,
            bytes memory pmmCalldata
        ) = _buildRedeemSwap(router, hook, controllerOrder, inputAmount, outputAmount, makerNonce, routerNonce);
        bytes memory routerSignature = _routerSignature(router, routerOrder, hooks, makerNonce);

        // The live manager's USDC is normally deployed into its vault. Provide test-only idle
        // collateral so this exercises the redeem route rather than the manager's withdrawal path.
        deal(USDC, COLLATERAL_MANAGER, 1_000_000e6);
        deal(TGLD, user, inputAmount);
        vm.prank(user);
        IERC20(TGLD).approve(address(router), inputAmount);
        vm.prank(maker);
        IERC20(USDC).approve(BEBOP_SETTLEMENT, type(uint256).max);

        vm.prank(user);
        router.swap(_exactIn(inputAmount), routerOrder, bytes(""), routerSignature, pmmCalldata, hooks);

        assertEq(IERC20(TGLD).balanceOf(user), 0, "user input consumed");
        assertEq(IERC20(USDC).balanceOf(receiver), outputAmount, "receiver gets hook-redeemed output");
        assertEq(IERC20(USDC).balanceOf(address(router)), 0, "router has no residual output");
        assertEq(IERC20(USDC).balanceOf(hook), 0, "hook has no residual output");
        assertEq(IERC20(USDC).balanceOf(maker), 0, "zero-inventory maker ends flat");
        assertTrue(!router.isNonceValid(user, routerNonce), "router nonce consumed");
        vm.expectRevert(IController.InvalidNonce.selector);
        controller.verifyNonce(hook, controllerNonce);
    }

    function testFork_RouterRevertsScaledRedeemAtomically() public {
        uint256 inputAmount = 1e18;
        uint256 outputAmount = _applySpread(TENBIN_REDEEM_USDC_PER_TGLD);
        uint256 scaledInput = inputAmount * 99 / 100;
        (IBebopRouter router, address hook) = _deployRouterAndHook();
        uint256 makerNonce = 104;
        uint256 controllerNonce = 204;
        uint256 routerNonce = 304;

        IController.Order memory controllerOrder =
            _controllerOrder(IController.OrderType.Redeem, controllerNonce, outputAmount, inputAmount, hook);
        (
            IBebopRouterOrder.BebopRouterOrder memory routerOrder,
            IBebopHook.Hook[] memory hooks,
            bytes memory pmmCalldata
        ) = _buildRedeemSwap(router, hook, controllerOrder, inputAmount, outputAmount, makerNonce, routerNonce);
        bytes memory routerSignature = _routerSignature(router, routerOrder, hooks, makerNonce);

        deal(TGLD, user, scaledInput);
        vm.prank(user);
        IERC20(TGLD).approve(address(router), scaledInput);
        vm.prank(maker);
        IERC20(USDC).approve(BEBOP_SETTLEMENT, type(uint256).max);

        vm.prank(user);
        vm.expectRevert(bytes4(keccak256("HookExecutionFailed()")));
        router.swap(_exactIn(scaledInput), routerOrder, bytes(""), routerSignature, pmmCalldata, hooks);

        assertEq(IERC20(TGLD).balanceOf(user), scaledInput, "input transfer rolled back");
        assertEq(IERC20(USDC).balanceOf(receiver), 0, "receiver gets no partial output");
        assertEq(IERC20(USDC).balanceOf(address(router)), 0, "router has no output");
        assertEq(IERC20(USDC).balanceOf(hook), 0, "hook has no output");
        assertEq(IERC20(USDC).balanceOf(maker), 0, "maker remains flat");
        assertTrue(router.isNonceValid(user, routerNonce), "router nonce rollback");
        _assertControllerNonceAvailable(hook, controllerNonce);
    }

    function _deployRouterAndHook() internal returns (IBebopRouter router, address hook) {
        router = IBebopRouter(BEBOP_ROUTER);
        vm.prank(router.owner());
        router.setRouterSigner(routerSigner);
        hook = vm.deployCode(
            "src/external/bebop/BebopHook.sol:BebopHook", abi.encode(address(router), maker, CONTROLLER, hookOwner)
        );
        vm.prank(maker);
        IControllerRouterForkRoles(CONTROLLER).setRecipientStatus(hook, true);
        assertTrue(IControllerRouterForkRoles(CONTROLLER).delegates(hook, maker), "hook delegate set");
        assertTrue(IControllerRouterForkRoles(CONTROLLER).recipients(maker, hook), "hook recipient set");
    }

    function _controllerOrder(
        IController.OrderType orderType,
        uint256 nonce,
        uint256 collateralAmount,
        uint256 assetAmount,
        address hook
    ) internal view returns (IController.Order memory) {
        return IController.Order({
            order_type: orderType,
            nonce: nonce,
            expiry: block.timestamp + 300,
            payer: hook,
            recipient: hook,
            collateral_token: USDC,
            collateral_amount: collateralAmount,
            order_token: TGLD,
            asset_amount: assetAmount
        });
    }

    function _buildMintSwap(
        IBebopRouter router,
        address hook,
        IController.Order memory controllerOrder,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 makerNonce,
        uint256 routerNonce
    )
        internal
        view
        returns (
            IBebopRouterOrder.BebopRouterOrder memory routerOrder,
            IBebopHook.Hook[] memory hooks,
            bytes memory pmmCalldata
        )
    {
        bytes memory hookData = _hookData(controllerOrder, inputAmount, outputAmount, USDC, TGLD);
        uint256 flags = uint256(uint160(maker)) | (1 << 161) | (1 << 162) | (1 << 163);
        hooks = new IBebopHook.Hook[](1);
        hooks[0] = IBebopHook.Hook({targetContract: hook, data: hookData, hookSignature: bytes(""), flags: flags});
        hooks[0].hookSignature = _signature(makerKey, router.hashHook(hooks[0], makerNonce));

        routerOrder = IBebopRouterOrder.BebopRouterOrder({
            fromAmount: inputAmount,
            toAmount: outputAmount,
            limitAmount: 0,
            fromToken: USDC,
            toToken: TGLD,
            pmmFromToken: TGLD,
            pmmToToken: TGLD,
            tokensOwner: user,
            receiver: receiver,
            originAddress: address(0),
            oracle: address(0),
            checker: address(0),
            info: uint256(uint64(block.timestamp + 300)) << 64,
            routerNonce: routerNonce,
            unsignedFlags: 0
        });
        pmmCalldata = _pmmCalldata(address(router), TGLD, outputAmount, makerNonce);
    }

    function _buildRedeemSwap(
        IBebopRouter router,
        address hook,
        IController.Order memory controllerOrder,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 makerNonce,
        uint256 routerNonce
    )
        internal
        view
        returns (
            IBebopRouterOrder.BebopRouterOrder memory routerOrder,
            IBebopHook.Hook[] memory hooks,
            bytes memory pmmCalldata
        )
    {
        bytes memory hookData = _hookData(controllerOrder, inputAmount, outputAmount, TGLD, USDC);
        uint256 flags = uint256(uint160(maker)) | (1 << 161) | (1 << 162) | (1 << 163);
        hooks = new IBebopHook.Hook[](1);
        hooks[0] = IBebopHook.Hook({targetContract: hook, data: hookData, hookSignature: bytes(""), flags: flags});
        hooks[0].hookSignature = _signature(makerKey, router.hashHook(hooks[0], makerNonce));

        routerOrder = IBebopRouterOrder.BebopRouterOrder({
            fromAmount: inputAmount,
            toAmount: outputAmount,
            limitAmount: 0,
            fromToken: TGLD,
            toToken: USDC,
            pmmFromToken: USDC,
            pmmToToken: USDC,
            tokensOwner: user,
            receiver: receiver,
            originAddress: address(0),
            oracle: address(0),
            checker: address(0),
            info: uint256(uint64(block.timestamp + 300)) << 64,
            routerNonce: routerNonce,
            unsignedFlags: 0
        });
        pmmCalldata = _pmmCalldata(address(router), USDC, outputAmount, makerNonce);
    }

    function _routerSignature(
        IBebopRouter router,
        IBebopRouterOrder.BebopRouterOrder memory order,
        IBebopHook.Hook[] memory hooks,
        uint256 makerNonce
    ) internal view returns (bytes memory) {
        address[] memory makers = new address[](1);
        uint256[] memory nonces = new uint256[](1);
        makers[0] = maker;
        nonces[0] = makerNonce;
        bytes32 hooksHash = router.hooksHash(hooks, makers, nonces);
        return _signature(routerSignerKey, router.hashOrder(order, bytes(""), hooksHash));
    }

    function _pmmCalldata(address router, address outputToken, uint256 outputAmount, uint256 makerNonce)
        internal
        view
        returns (bytes memory)
    {
        IBebopSettlementLike.SingleOrder memory order = IBebopSettlementLike.SingleOrder({
            expiry: block.timestamp + 300,
            taker_address: router,
            maker_address: maker,
            maker_nonce: makerNonce,
            taker_token: outputToken,
            maker_token: outputToken,
            taker_amount: outputAmount,
            maker_amount: outputAmount,
            receiver: router,
            packed_commands: 0,
            flags: 0
        });
        bytes32 structHash = keccak256(
            abi.encode(
                PMM_SINGLE_ORDER_TYPEHASH,
                uint64(0),
                order.expiry,
                order.taker_address,
                order.maker_address,
                order.maker_nonce,
                order.taker_token,
                order.maker_token,
                order.taker_amount,
                order.maker_amount,
                order.receiver,
                order.packed_commands
            )
        );
        bytes32 domainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH, keccak256("BebopSettlement"), keccak256("2"), block.chainid, BEBOP_SETTLEMENT
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        IBebopSettlementLike.MakerSignature memory makerSignature =
            IBebopSettlementLike.MakerSignature({signature: _signature(makerKey, digest), flags: 0});
        return abi.encodeWithSelector(IBebopSettlementLike.swapSingle.selector, order, makerSignature, uint256(0));
    }

    function _hookData(
        IController.Order memory order,
        uint256 inputAmount,
        uint256 outputAmount,
        address inputToken,
        address outputToken
    ) internal view returns (bytes memory) {
        bytes32 orderHash = controller.hashOrder(order);
        IController.Signature memory orderSignature = IController.Signature({
            signature_type: IController.SignatureType.EIP712, signature_bytes: _signature(makerKey, orderHash)
        });
        IController.Context memory context =
            IController.Context({order_hash: orderHash, share_price: 0, is_curated: false});
        IController.Signature memory approval = IController.Signature({
            signature_type: IController.SignatureType.EIP712,
            signature_bytes: _signature(minterKey, controller.hashContext(context))
        });
        bytes memory issuerData = abi.encode(
            IssuerData({order: order, orderSignature: orderSignature, context: context, approval: approval})
        );
        return abi.encode(
            HookData({
                action: uint8(order.order_type),
                inputToken: inputToken,
                outputToken: outputToken,
                quoteInputAmount: inputAmount,
                quoteOutputAmount: outputAmount,
                issuerData: issuerData
            })
        );
    }

    function _applySpread(uint256 amount) internal pure returns (uint256) {
        return amount * (BPS - SPREAD_BPS) / BPS;
    }

    function _exactIn(uint256 amount) internal pure returns (int256) {
        require(amount <= uint256(type(int256).max), "exact input exceeds int256");
        // forge-lint: disable-next-line(unsafe-typecast)
        return int256(amount);
    }

    function _signature(uint256 key, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function _assertControllerNonceAvailable(address hook, uint256 nonce) internal {
        try IControllerRouterForkRoles(CONTROLLER).verifyNonce(hook, nonce) {}
        catch {
            fail("failed router settlement consumed controller nonce");
        }
    }
}
