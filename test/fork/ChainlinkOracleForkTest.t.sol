// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetToken} from "../../src/AssetToken.sol";
import {AggregatorV3Interface} from "chainlink-local/src/data-feeds/interfaces/AggregatorV3Interface.sol";
import {IController} from "../../src/interface/IController.sol";
import {IOracleAdapter} from "../../src/interface/IOracleAdapter.sol";
import {GoldOracleAdapter} from "../../src/oracle/GoldOracleAdapter.sol";
import {ForkBaseTest} from "../fork/ForkBaseTest.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract ChainlinkOracleForkTest is ForkBaseTest {
    using SafeCast for int256;
    using SafeERC20 for AssetToken;
    // constants
    uint256 public constant PRICE_STALENESS_THRESHOLD = 1 days;

    // mainnet contracts
    address internal aggregatorContract = 0x214eD9Da11D2fbe465a6fc601a91E62EbEc1a0D6;

    function setUp() public override {
        // fork mainnet
        super.setUp();
        oracleAdapter = new GoldOracleAdapter(aggregatorContract);
        // set adapter and tolerance
        setOracle(address(oracleAdapter), 1e17);
    }

    function testFork_SetUp() public view {
        assertEq(address(oracleAdapter.oracle()), aggregatorContract);
    }

    function testFork_Revert_GetPrice() public {
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(IOracleAdapter.OraclePriceStale.selector);
        oracleAdapter.getPrice();
    }

    function testFork_GetPrice() public view {
        assertGt(oracleAdapter.getPrice(), 0);
    }

    function testFork_LatestRoundData() public view {
        (uint80 roundID, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            AggregatorV3Interface(aggregatorContract).latestRoundData();

        assertGt(roundID, 0);
        assertGt(answer, 0);
        assertGt(startedAt, 0);
        assertGt(updatedAt, 0);
        assertGt(answeredInRound, 0);

        // revert conditions not present
        assertEq(answeredInRound, roundID);
        assertLe(block.timestamp - updatedAt, PRICE_STALENESS_THRESHOLD);
    }

    function testFork_Oracle_Mint() public {
        uint256 answer = oracleAdapter.getPrice();

        uint256 collateralAmount = 100e6;
        uint256 collateralAmount18 = collateralAmount * 10 ** (18 - collateral.decimals());
        uint256 assetAmount = (collateralAmount18 * 1e18) / answer;
        // mint collateral and allow signer
        collateral.mint(payer, collateralAmount);
        approveController(collateral, payer, collateralAmount);
        allowSigner(payer);
        vm.prank(payer);
        controller.setRecipientStatus(recipient, true);
        // create and sign mint order
        IController.Order memory order = getMintOrder(collateral, collateralAmount, assetAmount, 0);
        IController.Signature memory signature = signOrder(payerKey, hashOrder(order));

        // execute a mint using concrete amount inside the threshold
        vm.prank(minter);
        controller.mint(order, signature);

        // check balances
        assertEq(collateral.balanceOf(payer), 0);
        assertEq(asset.balanceOf(recipient), assetAmount);
    }

    function testFork_Oracle_Redeem() public {
        testFork_Oracle_Mint();
        uint256 collateralAmount = 100e6;
        uint256 assetAmount = asset.balanceOf(recipient);
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

        // Execute a redemption using concrete amounts
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

    function testFork_Revert_Oracle_Mint() public {
        uint256 answer = oracleAdapter.getPrice();

        uint256 collateralAmount = 100e6;
        uint256 collateralAmount18 = collateralAmount * 10 ** (18 - collateral.decimals());
        uint256 assetAmount = (collateralAmount18 * 1e18) / answer;
        // mint collateral and allow signer
        collateral.mint(payer, collateralAmount);
        approveController(collateral, payer, collateralAmount);
        allowSigner(payer);
        vm.prank(payer);
        controller.setRecipientStatus(recipient, true);
        // create and sign mint order
        IController.Order memory order = getMintOrder(collateral, collateralAmount, assetAmount * 2, 0);
        IController.Signature memory signature = signOrder(payerKey, hashOrder(order));

        // execute a failed mint using concrete amount inside the threshold
        vm.prank(minter);
        vm.expectRevert(IController.ExceedsOracleDeltaTolerance.selector);
        controller.mint(order, signature);
    }

    function testFork_Revert_Oracle_Redeem() public {
        testFork_Oracle_Mint();
        uint256 collateralAmount = 100e6 * 2;
        uint256 assetAmount = asset.balanceOf(recipient);
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

        // Execute a failed redemption using concrete amounts
        vm.expectRevert(IController.ExceedsOracleDeltaTolerance.selector);
        redeem(redeemOrder, orderSignature);
    }
}
