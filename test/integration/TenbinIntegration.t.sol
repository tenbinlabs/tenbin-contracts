// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {ICollateralManager} from "src/interface/ICollateralManager.sol";
import {IController} from "src/interface/IController.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract TenbinIntegrationTest is BaseTest {
    function setUp() public virtual override {
        super.setUp();
    }

    function setUpPayerCollateral(uint256 collateralAmount) public {
        collateral.mint(payer, collateralAmount);
        vm.prank(payer);
        collateral.approve(address(controller), collateralAmount);
        vm.prank(signerManager);
        controller.setSignerStatus(payer, true);
        vm.prank(payer);
        controller.setRecipientStatus(recipient, true);
    }

    function setUpPayerAsset(uint256 assetAmount) public {
        vm.prank(address(controller));
        asset.mint(payer, assetAmount);
        vm.prank(payer);
        asset.approve(address(controller), assetAmount);
        vm.prank(signerManager);
        controller.setSignerStatus(payer, true);
    }

    function setUpMockVaultWithCollateral(MockERC20 token, uint256 amount) public {
        token.mint(address(manager), amount);
        vm.prank(curator);
        manager.deposit(address(token), amount, 0);
    }

    function test_SetUpTenbinIntegrationTest() public view {
        require(manager.hasRole(CURATOR_ROLE, curator));
        require(controller.hasRole(MINTER_ROLE, address(multicall)));
        require(multicall.hasRole(MULTICALLER_ROLE, multicaller));
    }

    function test_Mint_Deposit() public {
        setUpPayerCollateral(100000e6);
        IController.Order memory order = getMintOrder(collateral, 10000e6, 3e18, 0);
        bytes32 orderHash = controller.hashOrder(order);
        IController.Signature memory signature = signOrder(payerKey, orderHash);
        vm.prank(payer);
        controller.setRecipientStatus(recipient, true);
        address[] memory batchTargets = new address[](2);
        batchTargets[0] = address(controller);
        batchTargets[1] = address(manager);
        bytes[] memory batchOrders = new bytes[](2);
        batchOrders[0] = abi.encodeWithSelector(IController.mint.selector, order, signature);
        batchOrders[1] = abi.encodeWithSelector(ICollateralManager.deposit.selector, address(collateral), 9000e6, 0);
        vm.prank(multicaller);
        multicall.multicall(batchTargets, batchOrders);
        assertEq(collateral.balanceOf(custodian), 1000e6);
        assertEq(collateral.balanceOf(address(vault)), 9000e6);
        assertEq(collateral.balanceOf(payer), 90000e6);
        assertEq(asset.balanceOf(recipient), 3e18);
    }

    function test_Withdraw_Redeem() public {
        setUpPayerAsset(10e18);
        setUpMockVaultWithCollateral(collateral, 100000e6);
        IController.Order memory order = getRedeemOrder(collateral, 10000e6, 3e18, 0);
        bytes32 orderHash = controller.hashOrder(order);
        IController.Signature memory signature = signOrder(payerKey, orderHash);
        vm.prank(payer);
        controller.setRecipientStatus(recipient, true);
        address[] memory batchTargets = new address[](2);
        batchTargets[0] = address(manager);
        batchTargets[1] = address(controller);
        bytes[] memory batchOrders = new bytes[](2);
        batchOrders[0] =
            abi.encodeWithSelector(ICollateralManager.withdraw.selector, address(collateral), 10000e6, UINT256_MAX);
        batchOrders[1] = abi.encodeWithSelector(IController.redeem.selector, order, signature);
        vm.prank(multicaller);
        multicall.multicall(batchTargets, batchOrders);
        assertEq(collateral.balanceOf(address(vault)), 90000e6);
        assertEq(asset.balanceOf(payer), 7e18);
        assertEq(collateral.balanceOf(recipient), 10000e6);
    }

    function test_Mint_Swap_Deposit() public {
        // setup
        setUpPayerCollateral(10000e6);
        address executor = vm.addr(0x1111);
        vm.prank(owner);
        manager.addCollateral(address(collateral2), address(vault2));
        vm.prank(capAdjuster);
        manager.setMinSwapPrice(address(collateral), address(collateral2), 1e18);
        collateral2.mint(address(router), 9000e18);
        vm.prank(signerManager);

        // create mint order
        IController.Order memory order = getMintOrder(collateral, 10000e6, 3e18, 0);
        bytes32 orderHash = controller.hashOrder(order);
        IController.Signature memory signature = signOrder(payerKey, orderHash);

        // create swap data
        (bytes memory parameters, bytes memory swapData,,) = makeSwapData(
            SwapContext({
                token1: collateral,
                token2: collateral2,
                srcToken: address(collateral),
                dstToken: address(collateral2),
                dec1: 6,
                dec2: 18,
                minPrice: 0.99e6, // 1%
                amount: 9000e6,
                minReturnAmount: 9000e18,
                executor: executor
            })
        );

        // batch orders
        address[] memory batchTargets = new address[](3);
        batchTargets[0] = address(controller);
        batchTargets[1] = address(manager);
        batchTargets[2] = address(manager);
        bytes[] memory batchOrders = new bytes[](3);
        batchOrders[0] = abi.encodeWithSelector(IController.mint.selector, order, signature);
        batchOrders[1] = abi.encodeWithSelector(ICollateralManager.swap.selector, parameters, swapData);
        batchOrders[2] = abi.encodeWithSelector(ICollateralManager.deposit.selector, address(collateral2), 9000e18, 0);

        // multicall and catch events
        vm.prank(multicaller);
        vm.expectEmit();
        emit ICollateralManager.Swap(address(collateral), address(collateral2), 9000e6, 9000e18);
        emit ICollateralManager.Deposit(address(collateral2), 9000e18);
        multicall.multicall(batchTargets, batchOrders);

        // make assertions
        assertEq(collateral.balanceOf(custodian), 1000e6);
        assertEq(collateral2.balanceOf(address(vault2)), 9000e18);
        assertEq(collateral.balanceOf(address(manager)), 0);
        assertEq(collateral2.balanceOf(address(manager)), 0);
        assertEq(collateral.balanceOf(payer), 0);
        assertEq(asset.balanceOf(recipient), 3e18);
        assertEq(vault2.totalAssets(), 9000e18);
    }

    function test_Withdraw_Swap_Redeem() public {
        // setup
        vm.prank(owner);
        manager.addCollateral(address(collateral2), address(vault2));
        setUpMockVaultWithCollateral(collateral2, 32400e18);
        setUpPayerAsset(10e18);
        vm.prank(payer);
        controller.setRecipientStatus(recipient, true);
        address executor = vm.addr(0x1111);
        collateral.mint(address(router), 32400e6);

        // create redeem order
        IController.Order memory order = getRedeemOrder(collateral, 18000e6, 5e18, 0);
        bytes32 orderHash = controller.hashOrder(order);
        IController.Signature memory signature = signOrder(payerKey, orderHash);

        // create swap data
        (bytes memory parameters, bytes memory swapData,,) = makeSwapData(
            SwapContext({
                token1: collateral2,
                token2: collateral,
                srcToken: address(collateral2),
                dstToken: address(collateral),
                dec1: 18,
                dec2: 6,
                minPrice: 0.99e6, // 1%
                amount: 18000e18,
                minReturnAmount: 18000e6,
                executor: executor
            })
        );

        // batch orders
        address[] memory batchTargets = new address[](3);
        batchTargets[0] = address(manager);
        batchTargets[1] = address(manager);
        batchTargets[2] = address(controller);
        bytes[] memory batchOrders = new bytes[](3);
        batchOrders[0] =
            abi.encodeWithSelector(ICollateralManager.withdraw.selector, address(collateral2), 18000e18, UINT256_MAX);
        batchOrders[1] = abi.encodeWithSelector(ICollateralManager.swap.selector, parameters, swapData);
        batchOrders[2] = abi.encodeWithSelector(IController.redeem.selector, order, signature);

        // multicall and catch events
        vm.prank(multicaller);
        vm.expectEmit();
        emit ICollateralManager.Withdraw(address(collateral2), 18000e18);
        emit ICollateralManager.Swap(address(collateral2), address(collateral), 18000e18, 18000e6);
        multicall.multicall(batchTargets, batchOrders);

        // make assertions
        assertEq(collateral2.balanceOf(address(vault2)), 14400e18);
        assertEq(collateral.balanceOf(address(manager)), 0);
        assertEq(collateral2.balanceOf(address(manager)), 0);
        assertEq(asset.balanceOf(payer), 5e18);
        assertEq(collateral.balanceOf(recipient), 18000e6);
        assertEq(vault2.totalAssets(), 14400e18);
    }

    function test_Reward_Staking() public {
        // allow signer and recipient
        allowSigner(payer);
        vm.prank(payer);
        controller.setRecipientStatus(address(revenueModule), true);

        // simulate revenue and collect funds to RevenueModule
        collateral.mint(address(manager), 10000e6);
        vm.startPrank(curator);
        manager.deposit(address(collateral), 10000e6, 0);
        collateral.mint(address(vault), 11000e6);
        manager.withdraw(address(collateral), 11000e6, UINT256_MAX);
        vm.stopPrank();

        // collect revenue from manager
        uint256 revenueAmount = manager.getRevenue(address(collateral));
        vm.prank(revenueKeeper);
        revenueModule.collect(address(collateral), revenueAmount);

        // external process to make mint order on behalf of revenue module
        // approve controller to spend tokens
        vm.prank(revenueKeeper);
        revenueModule.setControllerApproval(address(collateral), 10000e6);

        // create mint order for 2.5 asset tokens
        uint256 assetAmount = 2.5e18;
        IController.Order memory order = getMintOrder(collateral, 10000e6, assetAmount, 0);
        order.payer = address(revenueModule);
        order.recipient = address(revenueModule);
        IController.Signature memory signature = signOrder(payerKey, controller.hashOrder(order));

        // save balance before
        uint256 balanceBefore = collateral.balanceOf(address(revenueModule));

        // execute mint
        vm.prank(admin);
        revenueModule.delegateSigner(payer, true);
        mint(order, signature);

        // ensure mint occurred with correct amounts
        assertEq(collateral.balanceOf(address(revenueModule)), balanceBefore - 10000e6);
        assertEq(asset.balanceOf(address(revenueModule)), assetAmount);

        // calling reward from the revenue module
        vm.prank(revenueKeeper);
        revenueModule.reward(assetAmount);

        // ensure correct balances after
        assertEq(asset.balanceOf(address(staking)), assetAmount);
        assertEq(asset.balanceOf(address(revenueModule)), 0);
    }
}
