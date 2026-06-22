// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetToken} from "../../src/AssetToken.sol";
import {BaseTest} from "../BaseTest.sol";
import {Controller} from "../../src/Controller.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {IController} from "../../src/interface/IController.sol";
import {IERC20Errors} from "openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {IRestrictedRegistry} from "../../src/interface/IRestrictedRegistry.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract ControllerTest is BaseTest {
    using SafeERC20 for AssetToken;

    function setUp() public virtual override {
        super.setUp();
    }

    function test_Revert_SetUp() public {
        vm.expectRevert(IController.InvalidRatio.selector);
        new Controller(address(asset), address(staking), 1e18 + 1, custodian, owner);
    }

    function test_SetUp() public view {
        assertEq(controller.manager(), address(manager));
        assertEq(controller.custodian(), custodian);
        assertEq(true, controller.hasRole(DEFAULT_ADMIN_ROLE, owner));
        assertEq(true, controller.hasRole(ADMIN_ROLE, admin));
        assertEq(true, controller.hasRole(SIGNER_MANAGER_ROLE, signerManager));
        assertEq(true, controller.hasRole(MINTER_ROLE, minter));
        assertEq(true, controller.hasRole(GATEKEEPER_ROLE, gatekeeper));
    }

    function test_Revert_AccessControl(address account) public {
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        controller.setSignerStatus(account, true);

        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        controller.setIsCollateral(address(collateral), true);

        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        controller.setCustodian(account);

        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        controller.setManager(account);

        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        controller.setRatio(DEFAULT_RATIO);
    }

    function test_GetAsset() public view {
        assertEq(controller.asset(), address(asset));
    }

    function test_Version() public view {
        assertEq(keccak256(abi.encodePacked("1.4.3")), keccak256(abi.encodePacked(controller.version())));
    }

    function test_HashOrder() public view {
        IController.Order memory order = getMintOrder(collateral, 10000e6, 3e18, 0);
        bytes32 orderHash = hashOrder(order);

        // Manually compute EIP712 hash
        bytes32 domainSeparator = controller.getDomainSeparator();
        bytes32 structHash = keccak256(controller.encodeOrder(order));

        bytes32 expectedDigest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        assertEq(orderHash, expectedDigest, "EIP712 hash mismatch");
    }

    function test_HashContext() public view {
        IController.Order memory order = getMintOrder(collateral, 10000e6, 3e18, 0);
        bytes32 orderHash = hashOrder(order);
        IController.Context memory context = getContext(orderHash, 1e18, true);
        bytes32 contextHash = hashContext(context);

        // Manually compute EIP712 hash
        bytes32 domainSeparator = controller.getDomainSeparator();
        bytes32 structHash = keccak256(controller.encodeContext(context));

        bytes32 expectedDigest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        assertEq(contextHash, expectedDigest, "EIP712 hash mismatch");
    }

    function test_EncodeOrder() public view {
        IController.Order memory order = getMintOrder(collateral, 10000e6, 3e18, 0);
        bytes32 orderTypeHash = keccak256(
            "Order(uint8 order_type,uint256 nonce,uint256 expiry,address payer,address recipient,address collateral_token,uint256 collateral_amount,address order_token,uint256 asset_amount)"
        );
        bytes memory expected = abi.encode(
            orderTypeHash,
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

        bytes memory actual = controller.encodeOrder(order);

        assertEq(keccak256(actual), keccak256(expected), "Encoded bytes do not match expected encoding");
    }

    function test_EncodeContext() public view {
        IController.Order memory order = getMintOrder(collateral, 10000e6, 3e18, 0);
        bytes32 orderHash = hashOrder(order);
        IController.Context memory context = getContext(orderHash, 1e18, true);

        bytes32 contextTypeHash = keccak256("Context(bytes32 order_hash,uint256 share_price,bool is_curated)");
        bytes memory expected = abi.encode(contextTypeHash, context.order_hash, context.share_price, context.is_curated);

        bytes memory actual = controller.encodeContext(context);

        assertEq(keccak256(actual), keccak256(expected), "Encoded bytes do not match expected encoding");
    }

    function test_GetDomainSeparator() public {
        // current chainId
        uint256 chainId = block.chainid;
        bytes32 chain1Separator = controller.getDomainSeparator();

        // different chain id
        chainId++;
        vm.chainId(chainId);
        bytes32 chain2Separator = controller.getDomainSeparator();

        assertNotEq(chain1Separator, chain2Separator, "Different chains should result in different domain separators");
    }

    function test_VerifyOrder() public {
        // EIP712 Signer
        // set oracle to check the full function
        setOracle(address(oracleAdapter), 1e18);
        aggregator.setAnswer(1e18);
        // 18 decimals token
        MockERC20 newToken = new MockERC20("Mock Collateral", "COL", 18);
        vm.prank(owner);
        controller.setIsCollateral(address(newToken), true);

        allowSigner(payer);
        vm.prank(payer);
        controller.setRecipientStatus(recipient, true);
        IController.Order memory order = getMintOrder(newToken, 10000e6, 3e18, 0);
        bytes32 orderHash = hashOrder(order);
        IController.Signature memory signature = signOrder(payerKey, orderHash);

        (address signer, bytes32 signedHash) = controller.verifyOrder(order, signature);
        assertEq(orderHash, signedHash);
        assertEq(payer, signer);

        // ERC1271 Signer
        allowSigner(address(signerContract));
        vm.prank(address(signerContract));
        controller.setRecipientStatus(recipient, true);
        order.payer = address(signerContract);
        orderHash = hashOrder(order);
        signature = signerContract.signOrder(payerKey, orderHash);

        (signer, signedHash) = controller.verifyOrder(order, signature);
        assertEq(orderHash, signedHash);
        assertEq(address(signerContract), signer);
    }

    function test_Revert_VerifyOrder() public {
        // create an order
        IController.Order memory order = getMintOrder(collateral, 10000e6, 3e18, 0);
        IController.Signature memory signature = signOrder(payerKey, hashOrder(order));

        // restrict account
        vm.prank(restricter);
        controller.setIsRestricted(payer, true);

        // InvalidSigner
        vm.expectRevert(IController.InvalidSigner.selector);
        controller.verifyOrder(order, signature);

        // allow signer
        allowSigner(payer);
        vm.prank(payer);
        controller.setRecipientStatus(recipient, true);

        vm.startPrank(minter);
        // Invalid Payer
        order.payer = address(1);
        signature = signOrder(payerKey, hashOrder(order));
        vm.expectRevert(IController.InvalidPayer.selector);
        controller.verifyOrder(order, signature);

        // AccountRestricted
        order = getMintOrder(collateral, 10000e6, 3e18, 0);
        order.payer = payer;
        signature = signOrder(payerKey, hashOrder(order));
        vm.startPrank(minter);
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector);
        controller.verifyOrder(order, signature);

        // Invalid restricted recipient
        order.payer = payer;
        order = getMintOrder(collateral, 10000e6, 3e18, 0);
        order.recipient = payer;
        signature = signOrder(payerKey, hashOrder(order));
        vm.startPrank(minter);
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector);
        controller.verifyOrder(order, signature);

        vm.stopPrank();
        // restrict account
        vm.prank(restricter);
        controller.setIsRestricted(payer, false);
        vm.startPrank(minter);

        // InvalidRecipient address(0)
        order = getMintOrder(collateral, 10000e6, 3e18, 0);
        order.recipient = address(0);
        signature = signOrder(payerKey, hashOrder(order));
        vm.startPrank(minter);
        vm.expectRevert(IController.InvalidRecipient.selector);
        controller.verifyOrder(order, signature);

        // InvalidRecipient recipient
        vm.stopPrank();
        vm.prank(payer);
        controller.setRecipientStatus(recipient, false);
        vm.startPrank(minter);
        order = getMintOrder(collateral, 10000e6, 3e18, 0);
        order.recipient = recipient;
        signature = signOrder(payerKey, hashOrder(order));
        vm.expectRevert(IController.InvalidRecipient.selector);
        controller.verifyOrder(order, signature);

        // CollateralNotSupported
        vm.stopPrank();
        vm.prank(payer);
        controller.setRecipientStatus(recipient, true);
        vm.startPrank(minter);
        order.recipient = payer;
        order = getMintOrder(collateral, 10000e6, 3e18, 0);
        order.collateral_token = address(0);
        signature = signOrder(payerKey, hashOrder(order));
        vm.expectRevert(IController.CollateralNotSupported.selector);
        controller.verifyOrder(order, signature);

        // InvalidCollateralAmount
        order = getMintOrder(collateral, 10000e6, 3e18, 0);
        order.collateral_amount = 0;
        signature = signOrder(payerKey, hashOrder(order));
        vm.startPrank(minter);
        vm.expectRevert(IController.InvalidCollateralAmount.selector);
        controller.verifyOrder(order, signature);

        // InvalidAssetToken not asset nor staked asset
        order = getMintOrder(collateral, 10000e6, 3e18, 0);
        order.order_token = address(collateral);
        signature = signOrder(payerKey, hashOrder(order));
        vm.startPrank(minter);
        vm.expectRevert(IController.InvalidOrderToken.selector);
        controller.verifyOrder(order, signature);

        // InvalidAssetToken not asset on Mint
        order = getMintOrder(collateral, 10000e6, 3e18, 0);
        order.order_token = address(staking);
        signature = signOrder(payerKey, hashOrder(order));
        vm.startPrank(minter);
        vm.expectRevert(IController.InvalidOrderToken.selector);
        controller.verifyOrder(order, signature);

        // Invalid asset amount
        order = getMintOrder(collateral, 10000e6, 3e18, 0);
        order.asset_amount = 0;
        signature = signOrder(payerKey, hashOrder(order));
        vm.expectRevert(IController.InvalidAssetAmount.selector);
        controller.verifyOrder(order, signature);

        // OrderExpired
        order = getMintOrder(collateral, 10000e6, 3e18, 0);
        order.expiry = block.timestamp - 1;
        signature = signOrder(payerKey, hashOrder(order));
        vm.startPrank(minter);
        vm.expectRevert(IController.OrderExpired.selector);
        controller.verifyOrder(order, signature);

        // create bad EIP712 signature
        (, bytes32 r, bytes32 s) = vm.sign(payerKey, hashOrder(order));
        IController.Signature memory badSignature = IController.Signature({
            signature_type: IController.SignatureType.EIP712, signature_bytes: abi.encodePacked(r, s, uint8(0x00))
        });

        // ensure bad signature is reverted
        vm.expectRevert(ECDSA.ECDSAInvalidSignature.selector);
        controller.verifyOrder(order, badSignature);

        // bad ERC1271 payer is not a contract
        IController.Signature memory badContractSignature = IController.Signature({
            signature_type: IController.SignatureType.ERC1271, signature_bytes: abi.encodePacked(r, s, uint8(0x00))
        });

        vm.expectRevert();
        controller.verifyOrder(order, badContractSignature);

        // send not signed ERC1271 signature
        badContractSignature = IController.Signature({
            signature_type: IController.SignatureType.ERC1271, signature_bytes: abi.encodePacked(r, s, uint8(0x00))
        });
        order.payer = address(signerContract);

        vm.expectRevert(IController.InvalidERC1271Signature.selector);
        controller.verifyOrder(order, badContractSignature);

        vm.stopPrank();
    }

    function test_verifyContext() public view {
        IController.Order memory order = getMintOrder(collateral, 10000e6, 3e18, 0);
        bytes32 orderHash = hashOrder(order);
        IController.Context memory context = getContext(orderHash, 1e18, true);
        bytes32 contextHash = hashContext(context);
        IController.Signature memory signedContext = signContext(minterKey, contextHash);

        // should succeed
        controller.verifyContext(context, signedContext);
    }

    function test_Revert_VerifyContext() public {
        IController.Order memory order = getMintOrder(collateral, 10000e6, 3e18, 0);
        bytes32 orderHash = hashOrder(order);
        IController.Context memory context = getContext(orderHash, 1e18, true);
        bytes32 contextHash = hashContext(context);

        // incorrect signer
        IController.Signature memory signedContext = signContext(payerKey, contextHash);

        // create bad EIP712 signature
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(payerKey, hashContext(context));
        IController.Signature memory badSignature = IController.Signature({
            signature_type: IController.SignatureType.EIP712, signature_bytes: abi.encodePacked(r, s, uint8(0x00))
        });

        // ensure bad signature is reverted
        vm.expectRevert(ECDSA.ECDSAInvalidSignature.selector);
        controller.verifyContext(context, badSignature);

        (v, r, s) = vm.sign(minterKey, contextHash);
        IController.Signature memory badSignatureType = IController.Signature({
            signature_type: IController.SignatureType.ERC1271, signature_bytes: abi.encodePacked(r, s, v)
        });

        // fail if wrong signature type
        vm.expectRevert(IController.InvalidSignatureType.selector);
        controller.verifyContext(context, badSignatureType);

        // incorrect signer
        vm.expectRevert(IController.InvalidApproval.selector);
        controller.verifyContext(context, signedContext);

        // invalid signature length
        signedContext.signature_bytes = "0x0";
        vm.expectRevert(IController.InvalidERC712Signature.selector);
        controller.verifyContext(context, signedContext);

        // invalid share price
        order = getMintOrder(collateral, 10000e6, 3e18, 0);
        orderHash = hashOrder(order);
        context = getContext(orderHash, 0, true);
        contextHash = hashContext(context);

        // incorrect signer
        signedContext = signContext(minterKey, contextHash);
        vm.expectRevert(IController.InvalidSharePrice.selector);
        controller.verifyContext(context, signedContext);
    }

    function test_Revert_Mint_ContextOrderHashMisMatch() public {
        IController.Order memory order = getMintOrder(collateral, 10000e6, 3e18, 0);
        IController.Order memory order2 = getMintOrder(collateral, 10000e6, 1e18, 0); // different hash
        bytes32 orderHash = hashOrder(order);
        bytes32 orderHash2 = hashOrder(order2);
        IController.Context memory context = getContext(orderHash2, 1e18, true);
        bytes32 contextHash = hashContext(context);

        // whitelist payer and recipient
        allowSigner(payer);
        addRecipient(payer, recipient);

        // mint some collateral tokens and approve controller
        collateral.mint(payer, 10000e6);
        approveController(collateral, payer, 10000e6);

        // sign order and context hashes
        IController.Signature memory signedOrder = signOrder(payerKey, orderHash);
        IController.Signature memory signedContext = signContext(minterKey, contextHash);

        // revert if order hash mismatch
        vm.expectRevert(IController.ContextOrderHashMisMatch.selector);
        vm.prank(minter);
        controller.mint(order, signedOrder, context, signedContext);
    }

    function test_Revert_Redeem_ContextOrderHashMisMatch() public {
        IController.Order memory order = getRedeemOrder(collateral, 40000e6, 10e18, 0);
        IController.Order memory order2 = getRedeemOrder(collateral, 40000e6, 1e18, 0); // different hash
        bytes32 orderHash = hashOrder(order);
        bytes32 orderHash2 = hashOrder(order2);
        IController.Context memory context = getContext(orderHash2, 1e18, true); // different hash
        bytes32 contextHash = hashContext(context);

        // whitelist payer and recipient
        allowSigner(payer);
        addRecipient(payer, recipient);

        // mint some collateral tokens and approve controller
        mintAsset(payer, 10e18);
        approveController(asset, payer, 10e18);

        // sign order and context hashes
        IController.Signature memory signedOrder = signOrder(payerKey, orderHash);
        IController.Signature memory signedContext = signContext(minterKey, contextHash);

        // revert if order hash mismatch
        vm.expectRevert(IController.ContextOrderHashMisMatch.selector);
        vm.prank(minter);
        controller.redeem(order, signedOrder, context, signedContext);
    }

    function test_Revert_VerifyNonce(uint256 collateralAmount, uint256 assetAmount, uint256 ratio) public {
        // Set up scenario
        collateralAmount = bound(collateralAmount, 1, 1e40);
        assetAmount = bound(assetAmount, 1, 1e40);
        ratio = bound(ratio, 0, 1e18 - 1);

        vm.prank(admin);
        controller.setRatio(ratio);

        performPayerMint(collateralAmount, assetAmount);

        vm.expectRevert(IController.InvalidNonce.selector);
        controller.verifyNonce(payer, 0);
    }

    function test_VerifyNonce() public {
        try controller.verifyNonce(payer, 0) {}
        catch (bytes memory) {
            /*lowLevelData*/
            fail("Invalid nonce");
        }
    }

    function test_Revert_Token_Balance() public {
        IController.Order memory mintOrder = getMintOrder(collateral, 10000e6, 3e18, 0);
        IController.Order memory redeemOrder = getRedeemOrder(collateral, 10000e6, 3e18, 0);

        IController.Signature memory mintSignature = signOrder(payerKey, controller.hashOrder(mintOrder));
        IController.Signature memory redeemSignature = signOrder(payerKey, controller.hashOrder(redeemOrder));

        IController.Context memory mintContext = getContext(controller.hashOrder(mintOrder), 0, false);
        IController.Signature memory mintApproval = signContext(minterKey, controller.hashContext(mintContext));

        IController.Context memory redeemContext = getContext(controller.hashOrder(redeemOrder), 0, false);
        IController.Signature memory redeemApproval = signContext(minterKey, controller.hashContext(redeemContext));

        allowSigner(payer);
        vm.prank(payer);
        controller.setRecipientStatus(recipient, true);

        vm.prank(payer);
        collateral.approve(address(controller), 10000e6);

        vm.startPrank(minter);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        controller.mint(mintOrder, mintSignature, mintContext, mintApproval);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        controller.redeem(redeemOrder, redeemSignature, redeemContext, redeemApproval);
        vm.stopPrank();
    }

    function test_Mint(uint256 collateralAmount, uint256 assetAmount, uint256 ratio) public {
        // set bounds
        collateralAmount = bound(collateralAmount, 1, 1e40);
        assetAmount = bound(assetAmount, 1, 1e40);
        ratio = bound(ratio, 0, 1e18 - 1);

        // configure ratio
        vm.prank(admin);
        controller.setRatio(ratio);

        // mint collateral, approve controller, and allow payer to sign order
        collateral.mint(payer, collateralAmount);
        approveController(collateral, payer, collateralAmount);
        allowSigner(payer);
        vm.prank(payer);
        controller.setRecipientStatus(recipient, true);

        // create and sign mint order
        IController.Order memory order = getMintOrder(collateral, collateralAmount, assetAmount, 0);
        IController.Signature memory signature = signOrder(payerKey, hashOrder(order));

        vm.expectEmit();
        emit IController.Mint(
            minter,
            order.payer,
            order.nonce,
            order.payer,
            order.recipient,
            order.collateral_token,
            order.collateral_amount,
            order.asset_amount
        );
        mint(order, signature);

        // calculate custodian and manager amounts
        uint256 custodianAmount = Math.mulDiv(collateralAmount, controller.ratio(), 1e18);
        uint256 managerAmount = collateralAmount - custodianAmount;

        // check balances
        assertEq(collateral.balanceOf(custodian), custodianAmount, "Custodian balance incorrect after mint");
        assertEq(collateral.balanceOf(address(manager)), managerAmount, "Manager balance incorrect after mint");
        assertEq(collateral.balanceOf(payer), 0, "Payer balance incorrect after mint");
        assertEq(asset.balanceOf(recipient), assetAmount, "Asset balance incorrect after mint");
    }

    function test_Revert_Mint_Controller() public {
        // allow signer
        allowSigner(payer);

        // create valid mint order
        IController.Order memory order = getMintOrder(collateral, 10000e6, 3e18, 0);
        order.recipient = payer;
        IController.Signature memory signature = signOrder(payerKey, hashOrder(order));
        IController.Context memory context = getContext(hashOrder(order), 0, false);
        IController.Signature memory approval = signContext(minterKey, hashContext(context));

        // Revert if signer is not MINTER ROLE and has no EIP712 signature
        vm.expectRevert(IController.InvalidSignatureType.selector);
        controller.mint(
            order,
            signature,
            context,
            IController.Signature({signature_type: IController.SignatureType.ERC1271, signature_bytes: new bytes(0)})
        );

        // Revert if signer has no token approval
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientAllowance.selector);
        controller.mint(order, signature, context, approval);

        // Revert if signer is not minter role
        IController.Signature memory badApproval = signContext(payerKey, controller.hashContext(context));
        vm.prank(owner);
        controller.revokeRole(MINTER_ROLE, minter);
        vm.expectRevert(IController.InvalidApproval.selector);
        controller.mint(order, signature, context, badApproval);

        // restore role
        vm.prank(owner);
        controller.grantRole(MINTER_ROLE, minter);

        // MintRedeemPaused
        vm.prank(gatekeeper);
        controller.setPauseStatus(IController.ControllerPauseStatus.MintRedeemPause);
        vm.expectRevert(IController.MintRedeemPaused.selector);
        controller.mint(order, signature, context, approval);

        // FMLPause
        vm.prank(gatekeeper);
        controller.setPauseStatus(IController.ControllerPauseStatus.FMLPause);
        vm.expectRevert(IController.MintRedeemPaused.selector);
        controller.mint(order, signature, context, approval);

        // set pause status back to None
        vm.prank(gatekeeper);
        controller.setPauseStatus(IController.ControllerPauseStatus.None);

        // InvalidOrderType
        order.order_type = IController.OrderType.Redeem;
        signature = signOrder(payerKey, hashOrder(order));
        context = getContext(hashOrder(order), 0, false);
        approval = signContext(minterKey, hashContext(context));
        vm.expectRevert(IController.InvalidOrderType.selector);
        controller.mint(order, signature, context, approval);

        // set correct order type
        order.order_type = IController.OrderType.Mint;
        signature = signOrder(payerKey, hashOrder(order));
        context = getContext(hashOrder(order), 0, false);
        approval = signContext(minterKey, hashContext(context));

        // ERC20 Insufficient Allowance (custodian transfer)
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientAllowance.selector);
        controller.mint(order, signature, context, approval);

        // mint 10% collateral to payer and approve controller
        collateral.mint(payer, 1000e6);
        approveController(collateral, payer, 1000e6);

        // ERC20 Insufficient Balance (manager transfer)
        vm.expectRevert();
        controller.mint(order, signature, context, approval);

        // mint and approve remaining collateral
        collateral.mint(payer, 9000e6);
        approveController(collateral, payer, 10000e6);

        // OnlyMinter (controller is not minter for asset token)
        vm.prank(owner);
        asset.setMinter(address(1));
        vm.expectRevert(AssetToken.OnlyMinter.selector);
        controller.mint(order, signature, context, approval);

        // return mint permissions to controller
        vm.prank(owner);
        asset.setMinter(address(controller));

        // mint should succeed
        controller.mint(order, signature, context, approval);
    }

    function test_Mint_Approval(uint256 collateralAmount, uint256 assetAmount) public {
        // set bounds
        collateralAmount = bound(collateralAmount, 1, 1e40);
        assetAmount = bound(assetAmount, 1, 1e40);

        // configure ratio
        vm.prank(admin);
        controller.setRatio(DEFAULT_RATIO);

        // mint collateral, approve controller, and allow payer to sign order
        collateral.mint(payer, collateralAmount);
        approveController(collateral, payer, collateralAmount);
        allowSigner(payer);
        vm.prank(payer);
        controller.setRecipientStatus(recipient, true);

        // create and sign mint order
        IController.Order memory order = getMintOrder(collateral, collateralAmount, assetAmount, 0);
        IController.Signature memory signature = signOrder(payerKey, hashOrder(order));
        IController.Context memory context = getContext(hashOrder(order), 0, false);
        IController.Signature memory approval = signContext(minterKey, hashContext(context));

        vm.expectEmit();
        emit IController.Mint(
            payer,
            order.payer,
            order.nonce,
            order.payer,
            order.recipient,
            order.collateral_token,
            order.collateral_amount,
            order.asset_amount
        );
        vm.prank(payer);
        controller.mint(order, signature, context, approval);

        // calculate custodian and manager amounts
        uint256 custodianAmount = Math.mulDiv(collateralAmount, controller.ratio(), 1e18);
        uint256 managerAmount = collateralAmount - custodianAmount;

        // check balances
        assertEq(collateral.balanceOf(custodian), custodianAmount, "Custodian balance incorrect after mint");
        assertEq(collateral.balanceOf(address(manager)), managerAmount, "Manager balance incorrect after mint");
        assertEq(collateral.balanceOf(payer), 0, "Payer balance incorrect after mint");
        assertEq(asset.balanceOf(recipient), assetAmount, "Asset balance incorrect after mint");
    }

    function test_Redeem(uint256 collateralAmount, uint256 assetAmount) public {
        // set bounds
        collateralAmount = bound(collateralAmount, 1, 1e40);
        assetAmount = bound(assetAmount, 1, 1e40);

        // mint tokens with nonce = 0
        performPayerMint(collateralAmount, assetAmount);

        // approve controller for burn
        vm.prank(recipient);
        asset.safeTransfer(payer, assetAmount);
        uint256 balance = asset.balanceOf(payer);
        vm.prank(payer);
        asset.approve(address(controller), balance);
        uint256 custodianAmount = collateral.balanceOf(custodian);

        // create redeem order
        IController.Order memory redeemOrder =
            getRedeemOrder(collateral, collateralAmount - custodianAmount, assetAmount, 1);
        uint256 managerAmount = collateral.balanceOf(address(manager)) - redeemOrder.collateral_amount;

        // sign redeem order
        IController.Signature memory orderSignature = signOrder(payerKey, controller.hashOrder(redeemOrder));
        vm.expectEmit();
        emit IController.Redeem(
            minter,
            redeemOrder.payer,
            redeemOrder.nonce,
            redeemOrder.payer,
            redeemOrder.recipient,
            redeemOrder.collateral_token,
            redeemOrder.collateral_amount,
            redeemOrder.asset_amount
        );

        // redeem should succeed
        redeem(redeemOrder, orderSignature);

        // check balances
        assertEq(collateral.balanceOf(custodian), custodianAmount, "Custodian balance incorrect after redeem");
        assertEq(collateral.balanceOf(address(manager)), managerAmount, "Manager balance incorrect after redeem");
        assertEq(collateral.balanceOf(payer), 0, "Payer collateral balance incorrect after redeem");
        assertEq(asset.balanceOf(payer), 0, "Payer asset balance incorrect after redeem");
        assertEq(
            collateral.balanceOf(recipient), redeemOrder.collateral_amount, "Recipient balance incorrect after redeem"
        );
        try controller.verifyNonce(payer, 2) {}
        catch (bytes memory) {
            /*lowLevelData*/
            fail("Invalid nonce after redeem");
        }
    }

    function test_Redeem_StakedAsset(uint256 collateralAmount, uint256 assetAmount) public {
        vm.prank(capAdjuster);
        staking.setInstantUnstakeCap(type(uint256).max);

        // set bounds
        collateralAmount = bound(collateralAmount, 1, 1e25);
        assetAmount = bound(assetAmount, 1, 1e25);

        // setup
        allowSigner(payer);
        vm.prank(payer);
        controller.setRecipientStatus(recipient, true);
        mintAsset(payer, assetAmount);
        collateral.mint(address(manager), collateralAmount);

        // stake assets
        vm.startPrank(payer);
        asset.approve(address(staking), assetAmount);
        staking.deposit(assetAmount, payer);
        staking.approve(instantUnstaker, staking.balanceOf(payer));
        vm.stopPrank();

        // approve controller for burn
        uint256 stakedBalance = staking.balanceOf(payer);
        vm.prank(payer);
        asset.approve(address(controller), assetAmount);
        vm.prank(payer);
        staking.approve(address(controller), stakedBalance);

        // create redeem order
        IController.Order memory redeemOrder = IController.Order({
            order_type: IController.OrderType.Redeem,
            expiry: block.timestamp + 1000,
            nonce: 0,
            payer: payer,
            recipient: recipient,
            collateral_token: address(collateral),
            collateral_amount: collateralAmount,
            order_token: address(staking),
            asset_amount: assetAmount
        });
        uint256 managerAmount = collateral.balanceOf(address(manager)) - redeemOrder.collateral_amount;
        // sign redeem order
        IController.Signature memory orderSignature = signOrder(payerKey, controller.hashOrder(redeemOrder));
        vm.expectEmit();
        emit IController.Redeem(
            minter,
            redeemOrder.payer,
            redeemOrder.nonce,
            redeemOrder.payer,
            redeemOrder.recipient,
            redeemOrder.collateral_token,
            redeemOrder.collateral_amount,
            redeemOrder.asset_amount
        );

        // redeem should succeed
        redeem(redeemOrder, orderSignature);

        // check balances
        assertEq(collateral.balanceOf(address(manager)), managerAmount, "Manager balance incorrect after redeem");
        assertEq(collateral.balanceOf(payer), 0, "Payer collateral balance incorrect after redeem");
        assertApproxEqAbs(
            staking.balanceOf(payer), 0, VAULT_TOLERANCE, "Payer staked asset balance incorrect after redeem"
        );
        assertEq(
            collateral.balanceOf(recipient), redeemOrder.collateral_amount, "Recipient balance incorrect after redeem"
        );
        try controller.verifyNonce(payer, 2) {}
        catch (bytes memory) {
            /*lowLevelData*/
            fail("Invalid nonce after redeem");
        }
    }

    function test_Redeem_Approval(uint256 collateralAmount, uint256 assetAmount) public {
        // set bounds
        collateralAmount = bound(collateralAmount, 1, 1e40);
        assetAmount = bound(assetAmount, 1, 1e40);

        // mint tokens with nonce = 0
        performPayerMint(collateralAmount, assetAmount);

        // approve controller for burn
        vm.prank(recipient);
        asset.safeTransfer(payer, assetAmount);
        uint256 balance = asset.balanceOf(payer);
        vm.prank(payer);
        asset.approve(address(controller), balance);
        uint256 custodianAmount = collateral.balanceOf(custodian);

        // create, sign, and approve redeem order
        IController.Order memory order = getRedeemOrder(collateral, collateralAmount - custodianAmount, assetAmount, 1);
        uint256 managerAmount = collateral.balanceOf(address(manager)) - order.collateral_amount;
        IController.Signature memory signature = signOrder(payerKey, hashOrder(order));
        IController.Context memory context = getContext(hashOrder(order), 0, false);
        IController.Signature memory approval = signContext(minterKey, hashContext(context));

        vm.expectEmit();
        emit IController.Redeem(
            payer,
            order.payer,
            order.nonce,
            order.payer,
            order.recipient,
            order.collateral_token,
            order.collateral_amount,
            order.asset_amount
        );

        // redeem should succeed
        vm.prank(payer);
        controller.redeem(order, signature, context, approval);

        // check balances
        assertEq(collateral.balanceOf(custodian), custodianAmount, "Custodian balance incorrect after redeem");
        assertEq(collateral.balanceOf(address(manager)), managerAmount, "Manager balance incorrect after redeem");
        assertEq(collateral.balanceOf(payer), 0, "Payer collateral balance incorrect after redeem");
        assertEq(asset.balanceOf(payer), 0, "Payer asset balance incorrect after redeem");
        assertEq(collateral.balanceOf(recipient), order.collateral_amount, "Recipient balance incorrect after redeem");
        try controller.verifyNonce(payer, 2) {}
        catch (bytes memory) {
            /*lowLevelData*/
            fail("Invalid nonce after redeem");
        }
    }

    function test_Revert_Redeem_Controller() public {
        // mint tokens
        uint256 collateralAmount = 10000e6;
        uint256 assetAmount = 3e18;
        performPayerMint(collateralAmount, assetAmount);

        // approve controller for burn
        vm.prank(recipient);
        asset.safeTransfer(payer, 1e18);
        uint256 balance = asset.balanceOf(payer);
        vm.prank(payer);
        asset.approve(address(controller), balance);

        // create redeem order with new nonce
        IController.Order memory order = getRedeemOrder(collateral, 3000e6, 1e18, 1);
        IController.Order memory order2 = getRedeemOrder(collateral, 4000e6, 1e18, 1);
        IController.Signature memory signature = signOrder(payerKey, controller.hashOrder(order));
        IController.Context memory context = getContext(controller.hashOrder(order2), 0, false); // context hash mismatch
        IController.Signature memory approval = signContext(minterKey, controller.hashContext(context));

        // Revert if context order hash mismatch
        vm.expectRevert(IController.ContextOrderHashMisMatch.selector);
        controller.redeem(order, signature, context, approval);

        // Make context order hash match
        context = getContext(controller.hashOrder(order), 0, false); // context hash match
        approval = signContext(minterKey, controller.hashContext(context));

        // Revert if signature has incorrect type
        vm.expectRevert(IController.InvalidSignatureType.selector);
        controller.redeem(
            order,
            signature,
            context,
            IController.Signature({signature_type: IController.SignatureType.ERC1271, signature_bytes: new bytes(0)})
        );

        // create approval signed by non-minter role
        IController.Signature memory badApproval = signContext(payerKey, controller.hashContext(context));

        // Revert if approval is not signed by minter role
        vm.expectRevert(IController.InvalidApproval.selector);
        controller.redeem(order, signature, context, badApproval);

        // Revert if signer nor approver are not MINTER ROLE
        vm.prank(owner);
        controller.revokeRole(MINTER_ROLE, minter);
        vm.expectRevert(IController.InvalidApproval.selector);
        controller.redeem(order, signature, context, approval);

        // restore role
        vm.prank(owner);
        controller.grantRole(MINTER_ROLE, minter);

        // set order type to mint
        IController.Order memory badOrder = order;
        badOrder.order_type = IController.OrderType.Mint;

        // revert if invalid order type
        vm.prank(minter);
        vm.expectRevert(IController.InvalidOrderType.selector);
        controller.redeem(badOrder, signature, context, approval);

        // create new valid order and context
        order = getRedeemOrder(collateral, 3000e6, 1e18, 2);
        signature = signOrder(payerKey, controller.hashOrder(order));
        context = getContext(controller.hashOrder(order), 0, false); // context hash mismatch
        approval = signContext(minterKey, controller.hashContext(context));

        // perform valid redeem
        vm.prank(minter);
        controller.redeem(order, signature, context, approval);

        // cannot replay order and context
        vm.prank(minter);
        vm.expectRevert(IController.InvalidNonce.selector);
        controller.redeem(order, signature, context, approval);
    }

    function test_Curated_Mint_Deposit(uint256 collateralAmount, uint256 assetAmount, uint256 ratio) public {
        // set bounds
        collateralAmount = bound(collateralAmount, 1, 1e40);
        assetAmount = bound(assetAmount, 1, 1e40);
        ratio = bound(ratio, 0, 1e18 - 1);

        // configure ratio
        vm.prank(admin);
        controller.setRatio(ratio);

        // mint collateral, approve controller, and allow payer to sign order
        collateral.mint(payer, collateralAmount);
        approveController(collateral, payer, collateralAmount);
        allowSigner(payer);
        vm.prank(payer);
        controller.setRecipientStatus(recipient, true);

        // create and sign mint order
        IController.Order memory order = getMintOrder(collateral, collateralAmount, assetAmount, 0);
        IController.Signature memory signature = signOrder(payerKey, hashOrder(order));

        IController.Context memory context = getContext(hashOrder(order), 1, true);
        IController.Signature memory approval = signContext(minterKey, hashContext(context));
        vm.startPrank(minter);
        vm.expectEmit();
        emit IController.Mint(
            minter,
            order.payer,
            order.nonce,
            order.payer,
            order.recipient,
            order.collateral_token,
            order.collateral_amount,
            order.asset_amount
        );
        controller.mint(order, signature, context, approval);
        vm.stopPrank();

        // calculate custodian and manager amounts
        uint256 custodianAmount = Math.mulDiv(collateralAmount, controller.ratio(), 1e18);
        uint256 managerAmount = collateralAmount - custodianAmount;

        // check balances
        assertEq(collateral.balanceOf(custodian), custodianAmount, "Custodian balance incorrect after mint");
        assertEq(collateral.balanceOf(address(manager)), 0, "Manager balance incorrect after mint");
        assertEq(collateral.balanceOf(payer), 0, "Payer balance incorrect after mint");
        assertEq(asset.balanceOf(recipient), assetAmount, "Asset balance incorrect after mint");

        assertEq(collateral.balanceOf(address(vault)), managerAmount, "Vault balance incorrect after curated mint");
        assertEq(vault.totalAssets(), managerAmount, "Vault total assets incorrect after curated mint");
        assertEq(manager.pendingRevenue(address(collateral)), 0, "Manager pending revenue incorrect after curated mint");
        assertEq(vault.balanceOf(address(manager)), managerAmount, "Manager share balance incorrect after curated mint");
    }

    function test_Curated_Withdraw_Redeem(uint256 collateralAmount, uint256 assetAmount, uint256 ratio) public {
        // set bounds
        collateralAmount = bound(collateralAmount, 1, 1e40);
        assetAmount = bound(assetAmount, 1, 1e40);
        ratio = bound(ratio, 0, 1e18 - 1);

        test_Curated_Mint_Deposit(collateralAmount, assetAmount, ratio);

        // approve controller for burn
        vm.prank(recipient);
        asset.safeTransfer(payer, assetAmount);
        uint256 balance = asset.balanceOf(payer);
        vm.prank(payer);
        asset.approve(address(controller), balance);
        uint256 custodianAmount = collateral.balanceOf(custodian);

        // create redeem order
        IController.Order memory redeemOrder =
            getRedeemOrder(collateral, collateralAmount - custodianAmount, assetAmount, 1);

        // sign redeem order
        IController.Signature memory orderSignature = signOrder(payerKey, controller.hashOrder(redeemOrder));

        // redeem should succeed
        IController.Context memory context =
            getContext(controller.hashOrder(redeemOrder), redeemOrder.collateral_amount, true);
        IController.Signature memory approval = signContext(minterKey, controller.hashContext(context));
        vm.prank(minter);
        controller.redeem(redeemOrder, orderSignature, context, approval);

        // check balances
        assertEq(collateral.balanceOf(custodian), custodianAmount, "Custodian balance incorrect after redeem");
        assertEq(collateral.balanceOf(address(manager)), 0, "Manager balance incorrect after redeem");
        assertEq(collateral.balanceOf(payer), 0, "Payer collateral balance incorrect after redeem");
        assertEq(asset.balanceOf(payer), 0, "Payer asset balance incorrect after redeem");
        assertEq(
            collateral.balanceOf(recipient), redeemOrder.collateral_amount, "Recipient balance incorrect after redeem"
        );

        try controller.verifyNonce(payer, 2) {}
        catch (bytes memory) {
            /*lowLevelData*/
            fail("Invalid nonce after redeem");
        }

        assertEq(vault.balanceOf(address(manager)), 0, "Manager incorrect shares balance after curated redeem");
        assertEq(collateral.balanceOf(address(manager)), 0, "Manager incorrect collateral balance after curated redeem");
        assertEq(
            manager.pendingRevenue(address(collateral)), 0, "Manager incorrect pending revenue after curated redeem"
        );
    }

    function test_SetSignerStatus(address account) public {
        vm.prank(signerManager);
        vm.expectEmit();
        emit IController.SignerStatusChanged(account, true);
        controller.setSignerStatus(account, true);

        bool isAllowed = controller.signers(account);
        bool isRecipient = controller.recipients(account, account);
        assertEq(isAllowed, true);
        assertEq(isRecipient, true);
    }

    function test_SetRecipientStatus(address account) public {
        allowSigner(payer);
        vm.prank(payer);
        vm.expectEmit();
        emit IController.RecipientStatusChanged(payer, account, true);
        controller.setRecipientStatus(account, true);

        bool isRecipient = controller.recipients(payer, account);
        assertEq(isRecipient, true);
    }

    function test_Revert_SetRecipientStatus(address account) public {
        vm.prank(payer);
        vm.expectRevert(IController.InvalidSigner.selector);
        controller.setRecipientStatus(account, true);

        bool isRecipient = controller.recipients(payer, account);
        assertEq(isRecipient, false);
    }

    function test_SetDelegateStatus(address account) public {
        //Set allowed signer as delegate
        allowSigner(payer);
        vm.prank(account);
        vm.expectEmit();
        emit IController.DelegateStatusChanged(account, payer, true);
        controller.setDelegateStatus(payer, true);

        bool isDelegate = controller.delegates(account, payer);
        assertEq(isDelegate, true);

        vm.prank(account);
        vm.expectEmit();
        emit IController.DelegateStatusChanged(account, payer, false);
        controller.setDelegateStatus(payer, false);

        isDelegate = controller.delegates(account, payer);
        assertEq(isDelegate, false);

        // remove signer from allowed signers
        vm.prank(signerManager);
        controller.setSignerStatus(payer, false);

        // Allows account to revoke delegation
        vm.prank(account);
        emit IController.DelegateStatusChanged(account, payer, false);
        controller.setDelegateStatus(payer, false);
    }

    function test_Revert_SetDelegateStatus(address account) public {
        vm.prank(payer);
        vm.expectRevert(IController.InvalidSigner.selector);
        controller.setDelegateStatus(account, true);

        bool isDelegate = controller.delegates(payer, account);
        assertEq(isDelegate, false);
    }

    function test_SetBlockMintLimit(uint128 amount) public {
        vm.prank(owner);
        vm.expectEmit();
        emit IController.MintLimitUpdated(amount);
        controller.setBlockMintLimit(amount);

        assertEq(controller.blockMintLimit(), amount);
    }

    function test_Revert_SetBlockMintLimit() public {
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        controller.setBlockMintLimit(1);
    }

    function test_SetBlockRedeemLimit(uint128 amount) public {
        vm.prank(owner);
        vm.expectEmit();
        emit IController.RedeemLimitUpdated(amount);
        controller.setBlockRedeemLimit(amount);

        assertEq(controller.blockRedeemLimit(), amount);
    }

    function test_Revert_SetBlockRedeemLimit() public {
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        controller.setBlockRedeemLimit(1);
    }

    function test_SetPauseStatus() public {
        IController.Order memory order = getMintOrder(collateral, 10000e6, 3e18, 0);
        IController.Signature memory signature = signOrder(payerKey, hashOrder(order));

        // pause mint & redemption
        vm.prank(gatekeeper);
        vm.expectEmit();
        emit IController.PauseStatusChanged(IController.ControllerPauseStatus.MintRedeemPause);
        controller.setPauseStatus(IController.ControllerPauseStatus.MintRedeemPause);

        // ensure mint & redemptions revert
        vm.startPrank(minter);
        vm.expectRevert(IController.MintRedeemPaused.selector);
        controller.mint(order, signature, EMPTY_CONTEXT, EMPTY_APPROVAL);

        vm.expectRevert(IController.MintRedeemPaused.selector);
        controller.redeem(order, signature, EMPTY_CONTEXT, EMPTY_APPROVAL);
        vm.stopPrank();

        // emergency pause
        vm.prank(gatekeeper);
        vm.expectEmit();
        emit IController.PauseStatusChanged(IController.ControllerPauseStatus.FMLPause);
        controller.setPauseStatus(IController.ControllerPauseStatus.FMLPause);

        // ensure mint & redemptions revert
        vm.startPrank(minter);
        vm.expectRevert(IController.MintRedeemPaused.selector);
        controller.mint(order, signature, EMPTY_CONTEXT, EMPTY_APPROVAL);

        vm.expectRevert(IController.MintRedeemPaused.selector);
        controller.redeem(order, signature, EMPTY_CONTEXT, EMPTY_APPROVAL);
        vm.stopPrank();
    }

    function test_SetIsCollateral(uint8 decimals) public {
        decimals = uint8(bound(uint8(decimals), 6, 18));
        MockERC20 collateral3 = new MockERC20("Collateral 3", "CLT3", decimals);

        vm.prank(owner);
        vm.expectEmit();
        emit IController.CollateralStatusChanged(address(collateral3), true);
        controller.setIsCollateral(address(collateral3), true);

        assertEq(controller.isCollateral(address(collateral3)), true);
    }

    function test_Revert_SetIsCollateral() public {
        MockERC20 collateral3 = new MockERC20("Collateral 3", "CLT3", 19);
        MockERC20 collateral4 = new MockERC20("Collateral 4", "CLT4", 5);

        vm.startPrank(owner);

        vm.expectRevert(IController.NonZeroAddress.selector);
        controller.setIsCollateral(address(0), true);

        vm.expectRevert(IController.InvalidCollateralDecimals.selector);
        controller.setIsCollateral(address(collateral3), true);

        vm.expectRevert(IController.InvalidCollateralDecimals.selector);
        controller.setIsCollateral(address(collateral4), true);
    }

    function test_SetCustodian() public {
        address account = address(1);
        vm.startPrank(owner);
        vm.expectRevert(IController.NonZeroAddress.selector);
        controller.setCustodian(address(0));

        vm.expectEmit();
        emit IController.CustodianUpdated(account);
        controller.setCustodian(account);
        vm.stopPrank();

        assertEq(controller.custodian(), account);
    }

    function test_SetManager() public {
        address account = address(1);
        vm.startPrank(owner);
        vm.expectRevert(IController.NonZeroAddress.selector);
        controller.setManager(address(0));

        vm.expectEmit();
        emit IController.ManagerUpdated(account);
        controller.setManager(account);
        vm.stopPrank();
        assertEq(controller.manager(), account);
    }

    function test_SetIsRestricted(address account) public {
        vm.prank(restricter);
        controller.setIsRestricted(account, true);
        assertEq(controller.isRestricted(account), true);

        vm.prank(restricter);
        controller.setIsRestricted(account, false);
        assertEq(controller.isRestricted(account), false);
    }

    function test_SetRatio(uint256 newRatio) public {
        newRatio = bound(newRatio, 0, 1e18 - 1);
        vm.startPrank(admin);
        vm.expectRevert(IController.InvalidRatio.selector);
        controller.setRatio(1e18 + 1);
        vm.expectEmit();
        emit IController.RatioUpdated(newRatio);
        controller.setRatio(newRatio);
        vm.stopPrank();
        assertEq(controller.ratio(), newRatio);
    }

    function test_ZeroRatio() public {
        // change ratio to 0
        vm.prank(admin);
        controller.setRatio(0);
        assertEq(controller.ratio(), 0);

        // mint tokens
        uint256 collateralAmount = 10000e6;
        uint256 assetAmount = 3e18;
        performPayerMint(collateralAmount, assetAmount);

        // check all collateral goes to manager
        assertEq(collateral.balanceOf(custodian), 0);
        assertEq(collateral.balanceOf(address(manager)), collateralAmount);
    }

    function test_BlockMintLimit() public {
        vm.prank(owner);
        controller.setBlockMintLimit(2e18);

        // can mint up to limit
        collateral.mint(payer, 12000e18);
        allowSigner(payer);
        addRecipient(payer, recipient);
        approveController(collateral, payer, type(uint256).max);
        IController.Order memory order = getMintOrder(collateral, 4000e18, 1e18, 0);
        mint(order, signOrder(payerKey, hashOrder(order)));
        (uint256 blockNumber, uint256 amount) = controller.mintLimit();
        assertEq(blockNumber, block.number);
        assertEq(amount, 1e18);

        // limt resets after new block
        vm.roll(block.number + 1);
        order = getMintOrder(collateral, 4000e18, 1e18, 1);
        mint(order, signOrder(payerKey, hashOrder(order)));
        (blockNumber, amount) = controller.mintLimit();
        assertEq(blockNumber, block.number);
        assertEq(amount, 1e18);

        // all mints update blockMints
        order = getMintOrder(collateral, 4000e18, 1e18, 2);
        mint(order, signOrder(payerKey, hashOrder(order)));
        (blockNumber, amount) = controller.mintLimit();
        assertEq(blockNumber, block.number);
        assertEq(amount, 2e18);
    }

    function test_Revert_BlockMintLimit() public {
        vm.prank(owner);
        controller.setBlockMintLimit(1e18 - 1);

        // minting just above mint limit fails
        collateral.mint(payer, 12000e18);
        allowSigner(payer);
        addRecipient(payer, recipient);
        approveController(collateral, payer, 4000e18);
        IController.Order memory order = getMintOrder(collateral, 4000e18, 1e18, 0);
        IController.Context memory context = getContext(hashOrder(order), 0, false);
        IController.Signature memory signedOrder = signOrder(payerKey, hashOrder(order));
        IController.Signature memory signedContext = signContext(minterKey, hashContext(context));
        vm.expectRevert(IController.ExceedsBlockMintLimit.selector);
        controller.mint(order, signedOrder, context, signedContext);

        vm.prank(owner);
        controller.setBlockMintLimit(1e18);

        // can mint up to the limit
        // succesfull mint
        controller.mint(order, signedOrder, context, signedContext);

        // new mint surpass limit
        order = getMintOrder(collateral, 4000e18, 1e18, 1);
        context = getContext(hashOrder(order), 0, false);
        signedOrder = signOrder(payerKey, hashOrder(order));
        signedContext = signContext(minterKey, hashContext(context));
        vm.expectRevert(IController.ExceedsBlockMintLimit.selector);
        controller.mint(order, signedOrder, context, signedContext);
    }

    function test_BlockRedeemLimit() public {
        vm.prank(owner);
        controller.setBlockRedeemLimit(2e18);

        // can redeem up to limit
        mintAsset(payer, 3e18);
        collateral.mint(address(manager), 12000e18);
        allowSigner(payer);
        addRecipient(payer, recipient);
        approveController(asset, payer, 3e18);
        IController.Order memory order = getRedeemOrder(collateral, 4000e18, 1e18, 0);
        redeem(order, signOrder(payerKey, hashOrder(order)));
        (uint256 blockNumber, uint256 amount) = controller.redeemLimit();
        assertEq(blockNumber, block.number);
        assertEq(amount, 1e18);

        // limt resets after new block
        vm.roll(block.number + 1);
        order = getRedeemOrder(collateral, 4000e18, 1e18, 1);
        redeem(order, signOrder(payerKey, hashOrder(order)));
        (blockNumber, amount) = controller.redeemLimit();
        assertEq(blockNumber, block.number);
        assertEq(amount, 1e18);

        // all redeems update blockRedeems
        order = getRedeemOrder(collateral, 4000e18, 1e18, 2);
        redeem(order, signOrder(payerKey, hashOrder(order)));
        (blockNumber, amount) = controller.redeemLimit();
        assertEq(blockNumber, block.number);
        assertEq(amount, 2e18);
    }

    function test_Revert_BlockRedeemLimit() public {
        vm.prank(owner);
        controller.setBlockRedeemLimit(1e18 - 1);

        // redeeming slightly above limit fails
        mintAsset(payer, 3e18);
        collateral.mint(address(manager), 12000e18);
        allowSigner(payer);
        addRecipient(payer, recipient);
        approveController(asset, payer, 1e18);
        IController.Order memory order = getRedeemOrder(collateral, 4000e18, 1e18, 0);
        IController.Context memory context = getContext(hashOrder(order), 0, false);
        IController.Signature memory signedOrder = signOrder(payerKey, hashOrder(order));
        IController.Signature memory signedContext = signContext(minterKey, hashContext(context));
        vm.expectRevert(IController.ExceedsBlockRedeemLimit.selector);
        controller.redeem(order, signedOrder, context, signedContext);

        vm.prank(owner);
        controller.setBlockRedeemLimit(1e18);

        // can redeem up to the limit
        // succesfull redeem
        controller.redeem(order, signedOrder, context, signedContext);

        // new redeem surpass limit
        order = getRedeemOrder(collateral, 4000e18, 1e18, 1);
        context = getContext(hashOrder(order), 0, false);
        signedOrder = signOrder(payerKey, hashOrder(order));
        signedContext = signContext(minterKey, hashContext(context));
        vm.expectRevert(IController.ExceedsBlockRedeemLimit.selector);
        controller.redeem(order, signedOrder, context, signedContext);
    }

    function test_Multicall(
        uint256 collateralAmount0,
        uint256 collateralAmount1,
        uint256 assetAmount0,
        uint256 assetAmount1,
        uint256 ratio
    ) public {
        // set bounds
        collateralAmount0 = bound(collateralAmount0, 1, 1e40);
        collateralAmount1 = bound(collateralAmount1, 1, 1e40);
        assetAmount0 = bound(assetAmount0, 1, 1e40);
        assetAmount1 = bound(assetAmount1, 1, 1e40);
        ratio = bound(ratio, 0, 1e18);

        // configure ratio
        vm.prank(admin);
        controller.setRatio(ratio);

        uint256 total = collateralAmount0 + collateralAmount1;

        // mint tokens
        collateral.mint(payer, total);
        // approve controller to spend tokens
        vm.prank(payer);
        collateral.approve(address(controller), total);
        // allow signer
        allowSigner(payer);
        vm.prank(payer);
        controller.setRecipientStatus(recipient, true);

        // create mint order
        IController.OrderType orderType = IController.OrderType.Mint;
        IController.Order memory order0 = IController.Order({
            order_type: orderType,
            nonce: 0,
            expiry: block.timestamp + 1000,
            payer: payer,
            recipient: recipient,
            collateral_token: address(collateral),
            collateral_amount: collateralAmount0,
            order_token: address(asset),
            asset_amount: assetAmount0
        });
        IController.Order memory order1 = IController.Order({
            order_type: orderType,
            nonce: 1,
            expiry: block.timestamp + 1000,
            payer: payer,
            recipient: recipient,
            collateral_token: address(collateral),
            collateral_amount: collateralAmount1,
            order_token: address(asset),
            asset_amount: assetAmount1
        });

        // generate signatures
        IController.Signature memory signature0 = signOrder(payerKey, controller.hashOrder(order0));
        IController.Signature memory signature1 = signOrder(payerKey, controller.hashOrder(order1));
        IController.Signature memory approval0 =
            signContext(minterKey, controller.hashContext(getContext(controller.hashOrder(order0), 0, false)));
        IController.Signature memory approval1 =
            signContext(minterKey, controller.hashContext(getContext(controller.hashOrder(order1), 0, false)));

        // create data to batch both orders for multicall
        bytes[] memory batchOrders = new bytes[](2);
        batchOrders[0] = abi.encodeWithSelector(
            IController.mint.selector, order0, signature0, getContext(controller.hashOrder(order0), 0, false), approval0
        );
        batchOrders[1] = abi.encodeWithSelector(
            IController.mint.selector, order1, signature1, getContext(controller.hashOrder(order1), 0, false), approval1
        );
        // call mint function through multicall
        vm.prank(minter);
        vm.expectEmit();
        emit IController.Mint(
            minter,
            order0.payer,
            order0.nonce,
            order0.payer,
            order0.recipient,
            order0.collateral_token,
            order0.collateral_amount,
            order0.asset_amount
        );
        emit IController.Mint(
            minter,
            order1.payer,
            order1.nonce,
            order1.payer,
            order1.recipient,
            order1.collateral_token,
            order1.collateral_amount,
            order1.asset_amount
        );
        controller.multicall(batchOrders);

        // calculate custodian and manager amounts
        uint256 custodianAmount = Math.mulDiv(total, controller.ratio(), 1e18);

        // check balances
        assertApproxEqAbs(collateral.balanceOf(custodian), custodianAmount, 1, "Custodian balance incorrect after mint");
        assertApproxEqAbs(
            collateral.balanceOf(address(manager)), total - custodianAmount, 1, "Manager balance incorrect after mint"
        );
        assertEq(collateral.balanceOf(payer), 0, "Payer balance incorrect after mint");
        assertEq(asset.balanceOf(recipient), assetAmount0 + assetAmount1, "Asset balance incorrect after mint");
    }

    function test_Revert_Multicall() public {
        bytes[] memory badMulticall = new bytes[](2);
        badMulticall[0] = abi.encodeWithSelector(IController.mint.selector, 0x00, 0x00, 0x00);
        vm.expectRevert();
        controller.multicall(badMulticall);
    }

    function test_RescueToken() public {
        address to = address(1);
        uint256 amount = 1e18;
        assertFalse(controller.isCollateral(address(collateral2)));

        // Send non collateral token
        collateral2.mint(address(controller), amount);
        assertEq(collateral2.balanceOf(to), 0);
        assertEq(collateral2.balanceOf(address(controller)), amount);

        // Rescue tokens
        vm.prank(admin);
        controller.rescueToken(address(collateral2), to);
        assertEq(collateral2.balanceOf(to), amount);
        assertEq(collateral2.balanceOf(address(controller)), 0);
    }

    function test_Revert_RescueToken() public {
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        controller.rescueToken(address(collateral2), address(1));

        vm.expectRevert(IController.NonZeroAddress.selector);
        vm.prank(admin);
        controller.rescueToken(address(collateral2), address(0));
    }

    function test_Revert_RescueEther() public {
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        controller.rescueEther();
        vm.prank(owner);
        controller.grantRole(ADMIN_ROLE, address(etherReceiver));

        // revert when receiving ether
        vm.prank(address(etherReceiver));
        vm.expectPartialRevert(IController.RescueEtherFailed.selector);
        controller.rescueEther();
    }

    function test_RescueEther() public {
        deal(address(controller), 1e18);
        vm.prank(admin);
        controller.rescueEther();
        assertEq(address(controller).balance, 0);
        assertEq(admin.balance, 1e18);
    }

    function test_SetOracleTolerance() public {
        setOracle(address(oracleAdapter), 1e17);
        (address adapter, uint96 tolerance) = controller.oracle();
        assertEq(adapter, address(oracleAdapter));
        assertEq(tolerance, 1e17);
    }

    function test_Revert_SetOracleTolerance() public {
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        controller.setOracleTolerance(1e17);
        vm.startPrank(admin);
        controller.setOracleAdapter(address(oracleAdapter));
        vm.expectRevert(IController.NewToleranceExceedsMax.selector);
        controller.setOracleTolerance(1e18 + 1);
    }

    function test_SetOracleAdapter() public {
        setOracle(address(oracleAdapter), 0);
        (address adapter, uint96 tolerance) = controller.oracle();
        assertEq(adapter, address(oracleAdapter));
        assertEq(tolerance, 0);

        setOracle(address(0), 0);
        (adapter, tolerance) = controller.oracle();
        assertEq(adapter, address(0));
    }

    function test_Revert_SetOracleAdapter() public {
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        controller.setOracleAdapter(address(oracleAdapter));
    }

    function test_OracleAdapter() public {
        // mint collateral and allow signer
        collateral.mint(payer, 2000e6);
        approveController(collateral, payer, 2000e6);
        allowSigner(payer);
        vm.prank(payer);
        controller.setRecipientStatus(recipient, true);
        // create and sign mint order
        IController.Order memory order = getMintOrder(collateral, 1000e6, 1e18, 0);
        IController.Signature memory signature = signOrder(payerKey, hashOrder(order));

        // set adapter and tolerance
        setOracle(address(oracleAdapter), 1e17);

        // set answer below order price and perform mint
        aggregator.setAnswer(999e18);
        mint(order, signature);

        // create another mint order
        order = getMintOrder(collateral, 1000e6, 1e18, 1);
        signature = signOrder(payerKey, hashOrder(order));

        // set answer above order price and perform mint
        aggregator.setAnswer(1100e18);
        mint(order, signature);
    }

    // test adapter for tokens with different decimal amounts
    function test_OracleAdapter_Decimals(uint8 decimals) public {
        // set decimals between 6-18
        decimals = uint8(bound(uint8(decimals), 6, 18));
        // scale collateral amount based on decimals (2000 x 10^decimals)
        uint256 collateralAmount = 2000 * 10 ** decimals;

        // Add a new collateral to the controller with 6-18 decimals
        MockERC20 collateral3 = new MockERC20("Collateral 3", "CLT3", decimals);
        vm.prank(owner);
        controller.setIsCollateral(address(collateral3), true);

        // mint collateral tokens (scaled based on decimals) and allow payer
        collateral3.mint(payer, collateralAmount);
        approveController(collateral3, payer, collateralAmount);
        allowSigner(payer);
        vm.prank(payer);
        controller.setRecipientStatus(recipient, true);

        // create a mint order (scaled based on decimals) for the new collateral type
        IController.Order memory order = getMintOrder(collateral3, collateralAmount / 2, 1e18, 0);
        IController.Signature memory signature = signOrder(payerKey, hashOrder(order));

        // set adapter and tolerance
        setOracle(address(oracleAdapter), 1e17);

        // set answer below order price and perform mint
        aggregator.setAnswer(999e18);
        mint(order, signature);

        // create another mint order
        order = getMintOrder(collateral3, collateralAmount / 2, 1e18, 1);
        signature = signOrder(payerKey, hashOrder(order));

        // set answer above order price and perform mint
        aggregator.setAnswer(1100e18);
        mint(order, signature);
    }

    function test_Revert_OracleAdapter_Mint() public {
        // mint collateral and allow payer
        collateral.mint(payer, 1000e6);
        approveController(collateral, payer, 1000e6);
        allowSigner(payer);
        vm.prank(payer);
        controller.setRecipientStatus(recipient, true);

        // create and sign mint order
        IController.Order memory order = getMintOrder(collateral, 1000e6, 1e18, 0);
        IController.Signature memory signature = signOrder(payerKey, hashOrder(order));
        IController.Context memory context = getContext(hashOrder(order), 0, false);
        IController.Signature memory approval = signContext(minterKey, hashContext(context));

        // set adapter and tolerance
        setOracle(address(oracleAdapter), 1e17);

        // set answer 1 wei below tolerance and expect revert
        aggregator.setAnswer(900e18 - ADAPTER_PRECISION);
        vm.expectRevert(IController.ExceedsOracleDeltaTolerance.selector);
        controller.mint(order, signature, context, approval);

        // set answer 1 wei above tolerance and perform mint
        aggregator.setAnswer(1100e18 + ADAPTER_PRECISION);
        mint(order, signature);

        // overpriced order
        // P = 1000 (10x O)
        uint256 assetAmount = 1e18;
        uint256 collateralAmount = 1000e18; // P = 1000
        uint256 oraclePrice = 100e18; // O = 100

        // set adapter and tolerance
        setOracle(address(oracleAdapter), 1e18); // 100%
        order = getMintOrder(collateral, collateralAmount, assetAmount, 0);
        order.nonce = 1;
        signature = signOrder(payerKey, hashOrder(order));
        context = getContext(hashOrder(order), 0, false);
        approval = signContext(minterKey, hashContext(context));

        aggregator.setAnswer(oraclePrice);

        // delta = |1000-100|/100 = 900/100 = 9.0 > 1
        vm.expectRevert(IController.ExceedsOracleDeltaTolerance.selector);
        controller.mint(order, signature, context, approval);
    }

    // fuzz tolerance and collateralAmount where oracle price matches order price
    function test_fuzz_OracleAdapter_Exact(uint96 tolerance, uint256 collateralAmount) public {
        // bound fuzz inputs
        tolerance = uint96(bound(tolerance, 0, MAX_ORACLE_TOLERANCE)); // 1e10-1e18
        collateralAmount = bound(collateralAmount, 1, 1e40);

        // allow payer and mint collateral
        collateral.mint(payer, collateralAmount);
        approveController(collateral, payer, collateralAmount);
        allowSigner(payer);
        vm.prank(payer);
        controller.setRecipientStatus(recipient, true);

        // set asset amount and oracle price
        uint256 assetAmount = 1e18;
        uint256 oraclePrice = collateralAmount * 1e12;

        // create and sign mint order
        IController.Order memory order = getMintOrder(collateral, collateralAmount, assetAmount, 0);
        IController.Signature memory signature = signOrder(payerKey, hashOrder(order));

        // set adapter and tolerance
        setOracle(address(oracleAdapter), tolerance);

        // set answer and perform mint - should succeed for all tolerances
        aggregator.setAnswer(oraclePrice);
        mint(order, signature);
    }

    // fuzz tolerance and collateralAmount where oracle price deviates from order price
    function test_fuzz_OracleAdapter_Deviation(uint96 tolerance, uint256 collateralAmount) public {
        // set fuzzing bounds
        tolerance = uint96(bound(tolerance, 0, MAX_ORACLE_TOLERANCE));
        collateralAmount = bound(collateralAmount, 1, 1e40);

        // allow payer and mint collateral
        collateral.mint(payer, collateralAmount);
        approveController(collateral, payer, collateralAmount);
        allowSigner(payer);
        vm.prank(payer);
        controller.setRecipientStatus(recipient, true);

        // set asset amount and oracle price
        uint256 assetAmount = 1e18;
        uint256 oraclePrice = collateralAmount * 1e12;

        // create and sign mint order
        IController.Order memory order = getMintOrder(collateral, collateralAmount, assetAmount, 0);
        IController.Signature memory signature = signOrder(payerKey, hashOrder(order));

        // set adapter and tolerance
        setOracle(address(oracleAdapter), tolerance);

        // set new oracle price slightly below tolerance
        oraclePrice = oraclePrice + Math.mulDiv(oraclePrice, tolerance, 1e18);

        // set answer and perform mint - should succeed for all tolerances
        aggregator.setAnswer(oraclePrice);
        mint(order, signature);
    }

    // fuzz tolerance and collateralAmount where oracle price matches order price
    function test_fuzz_OracleAdapter_Redeem_Staked(uint96 tolerance, uint256 assetAmount) public {
        // bound fuzz inputs
        tolerance = uint96(bound(tolerance, 1e11, MAX_ORACLE_TOLERANCE));
        assetAmount = bound(assetAmount, 1e8, 1e22);
        uint256 collateralAmount = 1000e6; // fixed collateral amount

        // setup
        mintAsset(payer, assetAmount);
        vm.prank(payer);
        asset.approve(address(staking), assetAmount);
        vm.prank(payer);
        uint256 shares = staking.deposit(assetAmount, payer);
        approveController(staking, payer, shares);
        approveController(asset, payer, shares);
        vm.prank(capAdjuster);
        staking.setInstantUnstakeCap(type(uint256).max);

        // allow signer and recipient
        allowSigner(payer);
        vm.prank(payer);
        controller.setRecipientStatus(recipient, true);

        // simulate 50% arbitrary increase in share price
        mintAsset(address(staking), assetAmount / 2);

        // mint collateral to be available for redemptions
        collateral.mint(address(manager), collateralAmount);

        // set asset amount and oracle price
        uint256 collateralAmount18 = collateralAmount * 1e12;

        // shares required after 50% prime bump
        uint256 sharesToRedeem = staking.previewWithdraw(assetAmount);

        // create redeem order
        IController.Order memory order = getRedeemOrder(collateral, collateralAmount, sharesToRedeem, 0);
        order.order_token = address(staking);

        // set answer and perform redeem - should succeed for all tolerances
        uint256 oraclePrice = Math.mulDiv(collateralAmount18, 1e18, sharesToRedeem);
        aggregator.setAnswer(oraclePrice);

        // sign redeem order
        IController.Signature memory signature = signOrder(payerKey, hashOrder(order));

        // set adapter and tolerance
        setOracle(address(oracleAdapter), tolerance);

        redeem(order, signature);
    }

    function test_fuzz_Revert_OracleAdapter(uint96 tolerance, uint256 collateralAmount) public {
        // set fuzzing bounds
        tolerance = uint96(bound(tolerance, 0, MAX_ORACLE_TOLERANCE - ADAPTER_PRECISION));
        collateralAmount = bound(collateralAmount, 1e11, 1e40);

        // allow payer and mint tokens
        collateral.mint(payer, collateralAmount);
        approveController(collateral, payer, collateralAmount);
        allowSigner(payer);
        vm.prank(payer);
        controller.setRecipientStatus(recipient, true);

        // set asset amount and oracle price
        uint256 assetAmount = 1e18;
        uint256 oraclePrice = Math.mulDiv(collateralAmount, 1e18, assetAmount);

        // create and sign mint order
        IController.Order memory order = getMintOrder(collateral, collateralAmount, assetAmount, 0);
        IController.Signature memory signature = signOrder(payerKey, hashOrder(order));
        IController.Context memory context = getContext(hashOrder(order), 0, false);
        IController.Signature memory approval = signContext(minterKey, hashContext(context));

        // set adapter and tolerance
        setOracle(address(oracleAdapter), tolerance);

        // set new oracle price slightly above tolerance
        uint256 oracleHighBoundary = Math.mulDiv(oraclePrice, 1e18, 1e18 - tolerance);
        aggregator.setAnswer(oracleHighBoundary + 1);

        // should revert given tolerance is higher than price delta
        vm.expectRevert(IController.ExceedsOracleDeltaTolerance.selector);
        controller.mint(order, signature, context, approval);

        // set new oracle price slightly below tolerance
        uint256 oracleLowBoundary = Math.mulDiv(oraclePrice, 1e18, 1e18 + tolerance);
        aggregator.setAnswer(oracleLowBoundary - 1);

        // should revert given tolerance is lower than price delta
        vm.expectRevert(IController.ExceedsOracleDeltaTolerance.selector);
        controller.mint(order, signature, context, approval);
    }

    function test_fuzz_OracleAdapter_Decimals(uint96 tolerance, uint256 collateralAmount, uint8 decimals) public {
        decimals = uint8(bound(uint8(decimals), 6, 18));
        tolerance = uint96(bound(tolerance, 0, MAX_ORACLE_TOLERANCE));
        collateralAmount = bound(collateralAmount, ADAPTER_PRECISION, 1e40);

        // create new collateral and add it to the controller
        MockERC20 collateral3 = new MockERC20("Collateral 3", "CLT3", decimals);
        vm.prank(owner);
        controller.setIsCollateral(address(collateral3), true);

        // mint collateral tokens and allow payer
        collateral3.mint(payer, collateralAmount);
        approveController(collateral3, payer, collateralAmount);
        allowSigner(payer);
        vm.prank(payer);
        controller.setRecipientStatus(recipient, true);

        // normalize collateral amount to be compatible with oracle adapter precision
        // forge-lint: disable-next-line(divide-before-multiply)
        collateralAmount = (collateralAmount / ADAPTER_PRECISION) * ADAPTER_PRECISION;
        uint256 assetAmount = 1e18;

        // set oracle price based on decimals
        uint256 oraclePrice;
        if (decimals == 1e18) oraclePrice = collateralAmount;
        else oraclePrice = collateralAmount * 10 ** (18 - decimals);

        // create and sign mint order
        IController.Order memory order = getMintOrder(collateral3, collateralAmount, assetAmount, 0);
        IController.Signature memory signature = signOrder(payerKey, hashOrder(order));
        IController.Context memory context = getContext(hashOrder(order), 0, false);
        IController.Signature memory approval = signContext(minterKey, hashContext(context));

        // set adapter and tolerance
        setOracle(address(oracleAdapter), tolerance);

        // set new oracle price based on tolerance
        uint256 newOraclePrice = oraclePrice + Math.mulDiv(oraclePrice, tolerance, 1e18);

        // set answer and perform mint
        // should succeed for all tolerances
        aggregator.setAnswer(newOraclePrice);
        vm.prank(minter);
        controller.mint(order, signature, context, approval);
    }

    function test_Oracle_MintSmallAmount() public {
        // set data
        // Assume an oracle price of $2,000 per asset token.
        setOracle(address(oracleAdapter), 0.99e18);
        aggregator.setAnswer(2000 * (10 ** 18));
        //Assume USDC collateral (6 decimals)
        uint256 collateralAmount = 2 * (10 ** 6); // 2 USDC 6 decimals
        uint256 assetAmount = 1000 * (10 ** 18); // 1k Tenbin tokens

        // configure ratio
        vm.prank(admin);
        controller.setRatio(0);

        // mint tokens, approve controller, and allow signer
        collateral.mint(payer, collateralAmount);
        approveController(collateral, payer, collateralAmount);
        allowSigner(payer);
        vm.prank(payer);
        controller.setRecipientStatus(recipient, true);

        // create and sign mint order
        IController.Order memory order = getMintOrder(collateral, collateralAmount, assetAmount, 0);
        IController.Signature memory signature = signOrder(payerKey, controller.hashOrder(order));

        vm.prank(minter);
        vm.expectRevert(IController.ExceedsOracleDeltaTolerance.selector);
        controller.mint(order, signature, EMPTY_CONTEXT, EMPTY_APPROVAL);
    }

    function test_Oracle_RedeemSmallAmount() public {
        // set up
        uint256 collateralAmount = 1000e6; // 1k USDC 6 decimals
        uint256 assetAmount = 1000e18; // 1k Tenbin tokens
        performPayerMint(collateralAmount, assetAmount);

        // Assume an oracle price of $2,000 per asset token.
        setOracle(address(oracleAdapter), 1e17);
        aggregator.setAnswer(2000 * (10 ** 18));

        assetAmount = 0.001 * (10 ** 6);
        collateralAmount = 2_000_000 * (10 ** 18);

        IController.Order memory redeemOrder = getRedeemOrder(collateral, collateralAmount, assetAmount, 1);

        // sign redeem order
        IController.Signature memory orderSignature = signOrder(payerKey, controller.hashOrder(redeemOrder));
        vm.prank(minter);
        vm.expectRevert(IController.ExceedsOracleDeltaTolerance.selector);
        controller.redeem(redeemOrder, orderSignature, EMPTY_CONTEXT, EMPTY_APPROVAL);
    }

    function test_ExposedVerifyNonce() public {
        try controller.exposedVerifyNonce(payer, 0) {}
        catch (bytes memory) {
            /*lowLevelData*/
            fail("Invalid nonce");
        }
    }

    function test_Revert_ExposedVerifyNonce() public {
        uint256 collateralAmount = 10000e6;
        uint256 assetAmount = 3e18;
        performPayerMint(collateralAmount, assetAmount);

        vm.expectRevert(IController.InvalidNonce.selector);
        controller.exposedVerifyNonce(payer, 0);
    }

    function test_Revert_Multi_Signers_Delegates(uint256 collateralAmount, uint256 assetAmount) public {
        uint256 signer2Key = 0xC000;
        address signer2Address = vm.addr(signer2Key);
        // Set up scenario
        collateralAmount = bound(collateralAmount, 1, 1e40);
        assetAmount = bound(assetAmount, 1, 1e40);

        // Have a second delegate signer
        allowSigner(payer);
        allowSigner(signer2Address);
        vm.prank(signer2Address);
        controller.setDelegateStatus(payer, true);

        // signer 1 can submit an order
        IController.Order memory order = performPayerMint(collateralAmount, assetAmount);
        IController.Signature memory signature = signOrder(signer2Key, hashOrder(order));
        IController.Context memory context = getContext(hashOrder(order), 0, false);
        IController.Signature memory approval = signContext(minterKey, hashContext(context));

        // signer 2 can't replay the same order
        vm.expectRevert(IController.InvalidNonce.selector);
        controller.mint(order, signature, context, approval);

        // can't replay redeem order
        // approve controller for burn
        vm.prank(recipient);
        asset.safeTransfer(payer, assetAmount);
        uint256 balance = asset.balanceOf(payer);
        vm.prank(payer);
        asset.approve(address(controller), balance);
        uint256 custodianAmount = collateral.balanceOf(custodian);

        // create redeem order
        IController.Order memory redeemOrder =
            getRedeemOrder(collateral, collateralAmount - custodianAmount, assetAmount, 1);

        // sign redeem order
        IController.Signature memory orderSignature = signOrder(payerKey, controller.hashOrder(redeemOrder));

        // redeem should succeed
        redeem(redeemOrder, orderSignature);

        // sign same redeem order
        IController.Signature memory orderSignature2 = signOrder(signer2Key, controller.hashOrder(redeemOrder));
        IController.Context memory context2 = getContext(hashOrder(redeemOrder), 0, false);
        IController.Signature memory approval2 = signContext(minterKey, hashContext(context2));

        // redeem should succeed
        vm.expectRevert(IController.InvalidNonce.selector);
        controller.redeem(redeemOrder, orderSignature2, context2, approval2);
    }

    function test_invalidateNonce() public {
        vm.prank(payer);
        controller.invalidateNonce(1);

        vm.expectRevert(IController.InvalidNonce.selector);
        controller.verifyNonce(payer, 1);
    }

    // helper function to mint assets for the payer account
    function performPayerMint(uint256 collateralAmount, uint256 assetAmount)
        internal
        returns (IController.Order memory)
    {
        // mint collateral, approve controller, and allow payer to sign order
        collateral.mint(payer, collateralAmount);
        approveController(collateral, payer, collateralAmount);
        allowSigner(payer);
        vm.prank(payer);
        controller.setRecipientStatus(recipient, true);

        // create and sign mint order
        IController.Order memory order = getMintOrder(collateral, collateralAmount, assetAmount, 0);
        IController.Signature memory signature = signOrder(payerKey, hashOrder(order));

        vm.expectEmit();
        emit IController.Mint(
            minter,
            order.payer,
            order.nonce,
            order.payer,
            order.recipient,
            order.collateral_token,
            order.collateral_amount,
            order.asset_amount
        );
        mint(order, signature);

        return order;
    }
}
