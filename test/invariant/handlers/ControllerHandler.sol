// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetToken} from "../../../src/AssetToken.sol";
import {Controller, IController} from "../../../src/Controller.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
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
        Controller controller;
        AssetToken asset;
        MockERC20 collateral;
    }
    //deploy
    Config cfg;
    uint256 public totalMintCollateral = 0;
    uint256 public totalRedeemCollateral = 0;
    uint256 public lastCustodianBalance;
    uint256 public lastManagerBalance;
    uint256 public lastMintAmount;
    uint256 public lastAssetSupply;
    uint256 public totalAssetSupplyMint;
    uint256 public lastCollateralSupply;
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
            controller: config.controller,
            asset: config.asset,
            collateral: config.collateral
        });

        lastManagerBalance = cfg.collateral.balanceOf(cfg.controller.manager());
        lastCustodianBalance = cfg.collateral.balanceOf(cfg.controller.custodian());
        lastAssetSupply = cfg.asset.totalSupply();
        lastCollateralSupply = cfg.collateral.totalSupply();

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
    function mint(uint256 collateralAmount, uint256 assetAmount) public {
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
            asset_amount: assetAmount
        });
        IController.Signature memory signature;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(cfg.payerKey, cfg.controller.hashOrder(order));
        signature = IController.Signature({
            signature_type: IController.SignatureType.EIP712, signature_bytes: abi.encodePacked(r, s, v)
        });
        lastCustodianBalance = cfg.collateral.balanceOf(cfg.controller.custodian());
        lastManagerBalance = cfg.collateral.balanceOf(cfg.controller.manager());
        lastAssetSupply = cfg.asset.totalSupply();
        lastCollateralSupply = cfg.collateral.totalSupply();

        vm.prank(cfg.minter);
        cfg.controller.mint(order, signature);
        nonce++;
        lastMintAmount = collateralAmount;
        totalAssetSupplyMint = cfg.asset.totalSupply();
        totalMintCollateral += collateralAmount;
    }

    // redeem
    function redeem(uint256 collateralAmount, uint256 assetAmount) public {
        if (cfg.collateral.totalSupply() == 0) return; //nothing to redeem
        // set bounds
        collateralAmount = bound(collateralAmount, 1, cfg.collateral.totalSupply());
        assetAmount = bound(assetAmount, 1, cfg.asset.totalSupply());
        // requisites for successful redeem
        mint(collateralAmount, assetAmount);
        // approve controller for burn
        vm.prank(cfg.recipient);
        cfg.asset.safeTransfer(cfg.payer, assetAmount);
        uint256 balance = cfg.asset.balanceOf(cfg.payer);
        vm.prank(cfg.payer);
        cfg.asset.approve(address(cfg.controller), balance);

        IController.Order memory redeemOrder = IController.Order({
            order_type: IController.OrderType.Redeem,
            expiry: block.timestamp + 1000,
            nonce: nonce,
            payer: cfg.payer,
            recipient: cfg.recipient,
            collateral_token: address(cfg.collateral),
            collateral_amount: collateralAmount,
            asset_amount: assetAmount
        });

        // sign redeem order
        IController.Signature memory signature;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(cfg.payerKey, cfg.controller.hashOrder(redeemOrder));
        signature = IController.Signature({
            signature_type: IController.SignatureType.EIP712, signature_bytes: abi.encodePacked(r, s, v)
        });
        lastCollateralSupply = cfg.collateral.totalSupply();

        vm.prank(cfg.minter);
        cfg.controller.redeem(redeemOrder, signature);
        nonce++;

        lastAssetSupply = cfg.asset.totalSupply();
        totalRedeemCollateral += collateralAmount;
    }

    // pause
    function setPauseStatus(uint256 rawStatus) public {
        uint256 bounded = bound(rawStatus, 0, uint256(type(IController.ControllerPauseStatus).max));
        IController.ControllerPauseStatus newStatus = IController.ControllerPauseStatus(bounded);

        if (cfg.controller.pauseStatus() != newStatus) {
            lastCollateralSupply = cfg.collateral.totalSupply();
            lastAssetSupply = cfg.asset.totalSupply();
            vm.prank(cfg.gatekeeper);
            cfg.controller.setPauseStatus(newStatus);
        }
    }
}
