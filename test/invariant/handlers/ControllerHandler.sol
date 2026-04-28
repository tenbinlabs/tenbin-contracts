// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetToken} from "../../../src/AssetToken.sol";
import {Controller} from "../../../src/Controller.sol";
import {IController} from "../../../src/interface/IController.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {StakedAsset} from "../../../src/StakedAsset.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Handler to interact with the controller and save snapshots for invariant testing
contract ControllerHandler is Test {
    using SafeERC20 for AssetToken;

    struct Config {
        address payer;
        address recipient;
        address minter;
        address signerManager;
        address gatekeeper;
        address admin;
        uint256 payerKey;
        uint256 minterKey;
        Controller controller;
        AssetToken asset;
        MockERC20 collateral;
        StakedAsset staking;
        IERC4626 vault;
    }

    //deploy
    Config cfg;
    uint256 public totalMintCollateral;
    uint256 public totalRedeemCollateral = 0;
    uint256 public lastCustodianBalance;
    uint256 public lastAssetSupply;
    uint256 public totalAssetSupplyMint;
    uint256 public sentToManager;
    bool public didSupplyChanged;
    uint128 internal nonce = 0;

    constructor(Config memory config) {
        cfg = Config({
            payer: config.payer,
            recipient: config.recipient,
            minter: config.minter,
            signerManager: config.signerManager,
            gatekeeper: config.gatekeeper,
            admin: config.admin,
            payerKey: config.payerKey,
            minterKey: config.minterKey,
            controller: config.controller,
            asset: config.asset,
            collateral: config.collateral,
            staking: config.staking,
            vault: config.vault
        });

        lastCustodianBalance = cfg.collateral.balanceOf(cfg.controller.custodian());
        lastAssetSupply = cfg.asset.totalSupply();

        vm.prank(cfg.signerManager);
        cfg.controller.setSignerStatus(cfg.payer, true);

        vm.prank(cfg.payer);
        cfg.controller.setRecipientStatus(cfg.recipient, true);
    }

    // setRatio
    function setRatio(uint256 newRatio) public {
        newRatio = bound(newRatio, 0, 1e18 - 1);
        if (newRatio == 0 && cfg.controller.ratio() > newRatio) {
            lastCustodianBalance = cfg.collateral.balanceOf(cfg.controller.custodian());
        }
        vm.prank(cfg.admin);
        cfg.controller.setRatio(newRatio);
    }

    // mint
    function mint(uint256 collateralAmount, uint256 assetAmount, bool isUserExecutedOrder, bool isCurated) public {
        // set bounds
        collateralAmount = bound(collateralAmount, 100, 1e40); // lower bound set at 100 to avoid small amounts
        assetAmount = bound(assetAmount, 100, 1e40);
        // mint tokens
        cfg.collateral.mint(cfg.payer, collateralAmount);
        // approve controller to spend tokens
        vm.prank(cfg.payer);
        cfg.collateral.approve(address(cfg.controller), collateralAmount);
        // allow signer
        vm.prank(cfg.signerManager);
        cfg.controller.setSignerStatus(vm.addr(cfg.payerKey), true);

        // create mint order
        IController.Order memory order = IController.Order({
            order_type: IController.OrderType.Mint,
            expiry: block.timestamp + 1000,
            nonce: nonce,
            payer: cfg.payer,
            recipient: cfg.recipient,
            collateral_token: address(cfg.collateral),
            collateral_amount: collateralAmount,
            order_token: address(cfg.asset),
            asset_amount: assetAmount
        });

        bytes32 orderHash = cfg.controller.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(cfg.payerKey, orderHash);
        IController.Signature memory signature = IController.Signature({
            signature_type: IController.SignatureType.EIP712, signature_bytes: abi.encodePacked(r, s, v)
        });
        IController.Context memory context =
            IController.Context({order_hash: orderHash, share_price: isCurated ? 1 : 0, is_curated: isCurated});
        (v, r, s) = vm.sign(cfg.minterKey, cfg.controller.hashContext(context));
        IController.Signature memory approval = IController.Signature({
            signature_type: IController.SignatureType.EIP712, signature_bytes: abi.encodePacked(r, s, v)
        });

        lastCustodianBalance = cfg.collateral.balanceOf(cfg.controller.custodian());
        lastAssetSupply = cfg.asset.totalSupply();
        uint256 prevBalance = cfg.collateral.balanceOf(cfg.controller.manager());
        uint256 prevSupply = cfg.collateral.totalSupply();

        if (isUserExecutedOrder) {
            vm.prank(cfg.payer);
        } else {
            vm.prank(cfg.minter);
        }
        cfg.controller.mint(order, signature, context, approval);
        nonce++;

        didSupplyChanged = didSupplyChanged ? didSupplyChanged : cfg.collateral.totalSupply() != prevSupply;
        totalAssetSupplyMint = cfg.asset.totalSupply();
        totalMintCollateral += collateralAmount;
        sentToManager += cfg.collateral.balanceOf(cfg.controller.manager()) - prevBalance;
    }

    // redeem
    function redeem(
        uint256 collateralAmount,
        uint256 assetAmount,
        bool isStakedAsset,
        bool isUserExecutedOrder,
        bool isCurated
    ) public {
        if (cfg.collateral.totalSupply() == 0) return; //nothing to redeem
        // set bounds
        collateralAmount = bound(collateralAmount, 1, cfg.collateral.totalSupply());
        assetAmount = bound(assetAmount, 1, cfg.asset.totalSupply());
        // requisites for successful redeem
        mint(collateralAmount, assetAmount, false, isCurated);
        // ensure payer funds to pay for redeem
        vm.prank(cfg.asset.minter());
        cfg.asset.mint(cfg.payer, assetAmount);

        // approve controller for burn
        vm.prank(cfg.payer);
        cfg.asset.approve(address(cfg.controller), cfg.asset.balanceOf(cfg.recipient));

        if (isStakedAsset) {
            // stake assets
            vm.startPrank(cfg.payer);
            cfg.asset.approve(address(cfg.staking), assetAmount);
            cfg.staking.deposit(assetAmount, cfg.payer);
            cfg.staking.approve(address(cfg.controller), cfg.staking.balanceOf(cfg.payer));
            vm.stopPrank();

            // approve controller for burn
            uint256 stakedBalance = cfg.staking.balanceOf(cfg.payer);
            vm.prank(cfg.payer);
            cfg.asset.approve(address(cfg.controller), assetAmount);
            vm.prank(cfg.payer);
            cfg.staking.approve(address(cfg.controller), stakedBalance);
        }

        // Avoid redeeming more than onchain liquidity
        if (isCurated && collateralAmount > (cfg.collateral.balanceOf(address(cfg.vault)))) {
            collateralAmount = cfg.collateral.balanceOf(address(cfg.vault));
        } else if (!isCurated && collateralAmount > (cfg.collateral.balanceOf(address(cfg.controller.manager())))) {
            collateralAmount = cfg.collateral.balanceOf(address(cfg.controller.manager()));
        }

        IController.Order memory redeemOrder = IController.Order({
            order_type: IController.OrderType.Redeem,
            expiry: block.timestamp + 1000,
            nonce: nonce,
            payer: cfg.payer,
            recipient: cfg.recipient,
            collateral_token: address(cfg.collateral),
            collateral_amount: collateralAmount,
            order_token: isStakedAsset ? address(cfg.staking) : address(cfg.asset),
            asset_amount: assetAmount
        });

        // sign redeem order
        bytes32 orderHash = cfg.controller.hashOrder(redeemOrder);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(cfg.payerKey, orderHash);
        IController.Signature memory signature = IController.Signature({
            signature_type: IController.SignatureType.EIP712, signature_bytes: abi.encodePacked(r, s, v)
        });
        IController.Context memory context = IController.Context({
            order_hash: orderHash, share_price: isCurated ? type(uint256).max : 0, is_curated: isCurated
        });
        (v, r, s) = vm.sign(cfg.minterKey, cfg.controller.hashContext(context));
        IController.Signature memory approval = IController.Signature({
            signature_type: IController.SignatureType.EIP712, signature_bytes: abi.encodePacked(r, s, v)
        });
        uint256 prevSupply = cfg.collateral.totalSupply();
        uint256 prevBalance = cfg.collateral.balanceOf(cfg.controller.manager());

        if (isUserExecutedOrder) {
            vm.prank(cfg.payer);
        } else {
            vm.prank(cfg.minter);
        }
        cfg.controller.redeem(redeemOrder, signature, context, approval);
        nonce++;

        didSupplyChanged = didSupplyChanged ? didSupplyChanged : cfg.collateral.totalSupply() != prevSupply;
        lastAssetSupply = cfg.asset.totalSupply();
        sentToManager -= prevBalance - cfg.collateral.balanceOf(cfg.controller.manager());
        totalRedeemCollateral += collateralAmount;
    }

    // pause
    function setPauseStatus(uint256 rawStatus) public {
        // Reduce pausing contract most times to get the least amount of revert scenarios
        uint256 bounded =
            block.number % 3 == 0 ? bound(rawStatus, 0, uint256(type(IController.ControllerPauseStatus).max)) : 0;
        IController.ControllerPauseStatus newStatus = IController.ControllerPauseStatus(bounded);

        if (cfg.controller.pauseStatus() != newStatus) {
            lastAssetSupply = cfg.asset.totalSupply();
            vm.prank(cfg.gatekeeper);
            cfg.controller.setPauseStatus(newStatus);
        }
    }
}
