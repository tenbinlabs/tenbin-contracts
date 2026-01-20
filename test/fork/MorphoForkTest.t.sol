// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {MorphoVaultV1Adapter} from "test/external/morpho/adapters/MorphoVaultV1Adapter.sol";
import {ForkBaseTest} from "test/fork/ForkBaseTest.sol";
import {IAdapter} from "test/external/morpho/interfaces/IAdapter.sol";
import {ICollateralManager} from "src/interface/ICollateralManager.sol";
import {IController} from "src/interface/IController.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IVaultV2} from "test/external/morpho/interfaces/IVaultV2.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {VaultV2} from "test/external/morpho/VaultV2.sol";

contract MorphoForkTest is ForkBaseTest {
    using SafeERC20 for IERC20;

    // max rate (from morpho constants)
    uint256 internal constant MAX_MAX_RATE = 200e16 / uint256(365 days); // 200% APR

    // accounts
    address internal depositor;
    address internal morphoAllocator;

    // contracts
    IAdapter internal adapter;
    IAdapter internal usdcAdapter;
    IAdapter internal usdtAdapter;
    IVaultV2 internal morpho;
    IVaultV2 internal usdcMorpho;
    IVaultV2 internal usdtMorpho;

    function setUp() public virtual override {
        // setup
        setUpFork();
        depositor = vm.addr(0xC000);
        morphoAllocator = vm.addr(0xC001);
        setUpAccounts();
        setUpDeployments();
        vault = IERC4626(address(vault));
        morpho = new VaultV2(address(this), address(collateral));
        usdcMorpho = new VaultV2(address(this), address(usdc));
        usdtMorpho = new VaultV2(address(this), address(usdt));
        adapter = new MorphoVaultV1Adapter(address(morpho), address(vault));
        usdcAdapter = new MorphoVaultV1Adapter(address(usdcMorpho), address(usdcVault));
        usdtAdapter = new MorphoVaultV1Adapter(address(usdtMorpho), address(usdtVault));
        setUpMorhpoVault(morpho, adapter);
        setUpMorhpoVault(usdcMorpho, usdcAdapter);
        setUpMorhpoVault(usdtMorpho, usdtAdapter);
        setUpLabels();
        setUpMorphoLabels();
        setUpController();
        setUpManager();
        setUpMorphoConfiguration();
    }

    function setUpMorphoLabels() internal {
        label(address(usdcMorpho), "usdcMorpho");
        label(address(usdtMorpho), "usdtMorpho");
        label(address(morpho), "morpho");
        label(address(adapter), "adapter");
        label(address(usdcAdapter), "usdcAdapter");
        label(address(usdtAdapter), "usdtAdapter");
        label(depositor, "depositor");
        label(morphoAllocator, "morphoAllocator");
    }

    function setUpMorphoConfiguration() internal {
        vm.startPrank(owner);
        multicall.grantRole(MULTICALLER_ROLE, minter);
        manager.addCollateral(address(collateral), address(morpho));
        manager.addCollateral(address(usdc), address(usdcMorpho));
        manager.addCollateral(address(usdt), address(usdtMorpho));
        controller.setIsCollateral(address(collateral), true);
        controller.setIsCollateral(address(usdc), true);
        controller.setIsCollateral(address(usdt), true);
        controller.setManager(address(manager));
        vm.stopPrank();
    }

    function setUpMorhpoVault(IVaultV2 morphoVault, IAdapter morphoAdapter) public {
        // set curator
        morphoVault.setCurator(curator);

        // set allocator
        vm.startPrank(curator);
        morphoVault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (morphoAllocator, true)));
        morphoVault.setIsAllocator(morphoAllocator, true);

        // add adapter
        morphoVault.submit(abi.encodeCall(IVaultV2.addAdapter, address(morphoAdapter)));
        morphoVault.addAdapter(address(morphoAdapter));

        // set caps
        bytes memory adapterId = abi.encode("this", address(morphoAdapter));
        morphoVault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (adapterId, 100000000e6)));
        morphoVault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (adapterId, 1e18)));
        morphoVault.increaseAbsoluteCap(adapterId, 100000000e6);
        morphoVault.increaseRelativeCap(adapterId, 1e18);

        // set max rate with no cap
        resetPrank(morphoAllocator);
        morphoVault.setMaxRate(MAX_MAX_RATE);
        vm.stopPrank();
    }

    function testFork_Morpho_Mint_Redeem_MultiCollateral() public {
        // setup
        allowSigner(payer);
        dealTo(usdc, payer, 10000e6);
        dealTo(usdt, payer, 10000e6);
        vm.startPrank(payer);
        usdc.approve(address(controller), type(uint256).max);
        usdt.safeIncreaseAllowance(address(controller), type(uint256).max);
        asset.approve(address(controller), type(uint256).max);
        controller.setRecipientStatus(recipient, true);
        vm.stopPrank();

        // mint order with usdc
        IController.Order memory order = getMintOrder(usdc, 3600e6, 1e18, 0);
        IController.Signature memory signature = signOrder(payerKey, hashOrder(order));

        vm.prank(minter);
        controller.mint(order, signature);
        assertEq(usdc.balanceOf(address(manager)), 3240e6);
        assertEq(usdc.balanceOf(custodian), 360e6);
        assertEq(asset.balanceOf(recipient), 1e18);

        // mint order with usdt
        order = getMintOrder(usdt, 3600e6, 1e18, 1);
        signature = signOrder(payerKey, hashOrder(order));

        vm.prank(minter);
        controller.mint(order, signature);
        assertEq(usdt.balanceOf(address(manager)), 3240e6);
        assertEq(usdt.balanceOf(custodian), 360e6);
        assertEq(asset.balanceOf(recipient), 2e18);

        // deposit collateral in vaults
        resetPrank(curator);
        manager.deposit(address(usdc), 3240e6, 0);
        manager.deposit(address(usdt), 3240e6, 0);

        assertEq(manager.getRevenue(address(usdc)), 0);
        assertEq(manager.getRevenue(address(usdt)), 0);

        // allocate to adapters
        resetPrank(morphoAllocator);
        usdcMorpho.allocate(address(usdcAdapter), new bytes(0), 3240e6);
        usdtMorpho.allocate(address(usdtAdapter), new bytes(0), 3240e6);
        assertApproxEqRel(usdcMorpho.totalAssets(), 3240e6, VAULT_TOLERANCE);
        assertApproxEqRel(usdcMorpho.totalAssets(), 3240e6, VAULT_TOLERANCE);
        assertApproxEqRel(usdcAdapter.realAssets(), 3240e6, VAULT_TOLERANCE);
        assertApproxEqRel(usdtAdapter.realAssets(), 3240e6, VAULT_TOLERANCE);
        vm.stopPrank();

        // simulate vault earning interest
        dealTo(usdc, address(usdcVault), 1000e6);
        dealTo(usdt, address(usdtVault), 1000e6);
        assertApproxEqAbs(usdc.balanceOf(address(usdcVault)), 4240e6, VAULT_TOLERANCE);
        assertApproxEqAbs(usdt.balanceOf(address(usdtVault)), 4240e6, VAULT_TOLERANCE);

        // roll block number & timestamp forward
        vm.warp(block.timestamp + ONE_YEAR_SECONDS);
        vm.roll(block.number + ONE_YEAR_BLOCKS);

        // assert interest is earned accordingly
        assertApproxEqAbs(usdcMorpho.totalAssets(), 4240e6, VAULT_TOLERANCE);
        assertApproxEqAbs(usdtMorpho.totalAssets(), 4240e6, VAULT_TOLERANCE);
        assertApproxEqAbs(usdcAdapter.realAssets(), 4240e6, VAULT_TOLERANCE);
        assertApproxEqAbs(usdtAdapter.realAssets(), 4240e6, VAULT_TOLERANCE);
        assertApproxEqAbs(manager.getRevenue(address(usdc)), 1000e6, VAULT_TOLERANCE);
        assertApproxEqAbs(manager.getRevenue(address(usdt)), 1000e6, VAULT_TOLERANCE);

        // deallocate from morpho in anticipation of withdrawal
        vm.startPrank(morphoAllocator);
        usdcMorpho.deallocate(address(usdcAdapter), new bytes(0), 3600e6);
        usdtMorpho.deallocate(address(usdtAdapter), new bytes(0), 3600e6);
        assertApproxEqAbs(usdcMorpho.totalAssets(), 4240e6, VAULT_TOLERANCE);
        assertApproxEqAbs(usdtMorpho.totalAssets(), 4240e6, VAULT_TOLERANCE);
        vm.stopPrank();

        // create redemption orders
        IController.Order memory order1 = getRedeemOrder(usdc, 3600e6, 1e18, 2);
        bytes32 orderHash1 = controller.hashOrder(order1);
        IController.Signature memory signature1 = signOrder(payerKey, orderHash1);
        IController.Order memory order2 = getRedeemOrder(usdt, 3600e6, 1e18, 3);
        bytes32 orderHash2 = controller.hashOrder(order2);
        IController.Signature memory signature2 = signOrder(payerKey, orderHash2);

        // create batch
        address[] memory targets = new address[](4);
        bytes[] memory batch = new bytes[](4);
        targets[0] = address(manager);
        targets[1] = address(manager);
        targets[2] = address(controller);
        targets[3] = address(controller);
        batch[0] = abi.encodeWithSelector(ICollateralManager.withdraw.selector, address(usdc), 3600e6, UINT256_MAX);
        batch[1] = abi.encodeWithSelector(ICollateralManager.withdraw.selector, address(usdt), 3600e6, UINT256_MAX);
        batch[2] = abi.encodeWithSelector(IController.redeem.selector, order1, signature1);
        batch[3] = abi.encodeWithSelector(IController.redeem.selector, order2, signature2);

        // transfer tokens to payer for redemption
        resetPrank(recipient);
        IERC20(asset).safeTransfer(payer, 2e18);

        // call batched order and check values
        resetPrank(minter);
        multicall.multicall(targets, batch);
        vm.stopPrank();
        assertEq(asset.balanceOf(payer), 0);

        assertEq(usdc.balanceOf(recipient), 3600e6); //THIS CHECK IS FIALING

        assertEq(usdt.balanceOf(recipient), 3600e6);

        assertApproxEqAbs(usdcMorpho.totalAssets(), 640e6, VAULT_TOLERANCE);

        assertApproxEqAbs(usdtMorpho.totalAssets(), 640e6, VAULT_TOLERANCE);

        assertEq(usdc.balanceOf(address(manager)), 0);

        assertEq(usdt.balanceOf(address(manager)), 0);
    }
}
