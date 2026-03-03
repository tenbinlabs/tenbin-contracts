// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IAdapter} from "vault-v2/src/interfaces/IAdapter.sol";
import {ICollateralManager} from "../../src/CollateralManager.sol";
import {IController} from "../../src/interface/IController.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IMorphoVaultV1AdapterFactory} from "vault-v2/src/adapters/interfaces/IMorphoVaultV1AdapterFactory.sol";
import {IVaultV2} from "vault-v2/src/interfaces/IVaultV2.sol";
import {IVaultV2Factory} from "vault-v2/src/interfaces/IVaultV2Factory.sol";
import {ForkBaseTest} from "../fork/ForkBaseTest.sol";
import {Gate} from "../../src/external/morpho/Gate.sol";

contract MorphoForkTest2 is ForkBaseTest {
    // accounts
    address internal depositor;
    address internal morphoAllocator;

    // contracts
    IAdapter internal adapter;
    IVaultV2 internal morpho;
    Gate internal gate;

    // max rate (from morpho constants)
    uint256 constant MAX_MAX_RATE = 200e16 / uint256(365 days); // 200% APR

    // salt for vault deployment
    bytes32 constant SALT = bytes32(abi.encodePacked("salt"));

    function setUp() public virtual override {
        setUpFork();
        setUpMockVaults();
        depositor = vm.addr(0xC000);
        morphoAllocator = vm.addr(0xC001);
        setUpAccounts();
        setUpDeployments();
        // set up factories
        IVaultV2Factory vaultFactory = IVaultV2Factory(VAULT_V2_FACTORY_ADDRESS);
        IMorphoVaultV1AdapterFactory adapterFactory = IMorphoVaultV1AdapterFactory(VAULT_V1_ADAPTER_FACTORY_ADDRESS);
        // set vault as morpho vault
        morpho = IVaultV2(vaultFactory.createVaultV2(address(this), address(collateral), SALT));
        vault = IERC4626(address(vault));
        adapter = IAdapter(adapterFactory.createMorphoVaultV1Adapter(address(morpho), address(vault)));
        gate = new Gate(owner);
        setUpController();
        setUpManager();
        setUpConfiguration();
        morpho.setCurator(curator);
        vm.startPrank(curator);
        morpho.submit(abi.encodeCall(IVaultV2.setIsAllocator, (morphoAllocator, true)));
        morpho.setIsAllocator(morphoAllocator, true);
        vm.stopPrank();
        label(depositor, "depositor");
        label(address(morphoAllocator), "morphoAllocator");
        label(address(adapter), "adapter");
        label(address(morpho), "morpho");
        label(address(vault), "vault");
        label(address(adapter), "adapter");
    }

    function setUpPayerCollateral(uint256 collateralAmount) public {
        collateral.mint(payer, collateralAmount);
        vm.prank(payer);
        collateral.approve(address(controller), collateralAmount);
        vm.prank(signerManager);
        controller.setSignerStatus(payer, true);
    }

    function setUpPayerAsset(uint256 assetAmount) public {
        vm.prank(address(controller));
        asset.mint(payer, assetAmount);
        vm.prank(payer);
        asset.approve(address(controller), assetAmount);
        vm.prank(signerManager);
        controller.setSignerStatus(payer, true);
        vm.prank(payer);
        controller.setRecipientStatus(recipient, true);
    }

    function setUpMockVaultWithCollateral(uint256 collateralAmount) public {
        collateral.mint(address(manager), collateralAmount);
        vm.prank(curator);
        manager.deposit(address(collateral), collateralAmount, 0);
    }

    function test_SetUpTenbinIntegrationTest() public view {
        require(manager.hasRole(CURATOR_ROLE, curator));
        require(controller.hasRole(MINTER_ROLE, address(multicall)));
        require(multicall.hasRole(MULTICALLER_ROLE, multicaller));
    }

    function test_Revert_Morpho() public {
        //assign vault gate
        vm.startPrank(curator);
        morpho.submit(abi.encodeCall(IVaultV2.setReceiveSharesGate, (address(gate))));
        morpho.setReceiveSharesGate(address(gate));
        vm.stopPrank();

        // mint funds for depositor and approve
        collateral.mint(depositor, 1000e6);
        vm.prank(depositor);
        collateral.approve(address(morpho), type(uint256).max);

        // add adapter
        vm.startPrank(curator);
        morpho.submit(abi.encodeCall(IVaultV2.addAdapter, address(adapter)));
        morpho.addAdapter(address(adapter));

        // set caps
        bytes memory adapterId = abi.encode("this", address(adapter));
        morpho.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (adapterId, 100000000e6)));
        morpho.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (adapterId, 1e18)));
        morpho.increaseAbsoluteCap(adapterId, 100000000e6);
        morpho.increaseRelativeCap(adapterId, 1e18);
        vm.stopPrank();

        // deposit funds into morpho vault fails because not whitelisted
        resetPrank(depositor);
        vm.expectRevert();
        morpho.deposit(1000e6, depositor);
        vm.stopPrank();

        // whitelist the depositor inside the gate
        vm.prank(owner);
        gate.setManager(depositor);

        // Now deposit works
        vm.prank(depositor);
        morpho.deposit(1000e6, depositor);
    }

    function test_Morpho() public {
        // mint funds for depositor and approve
        collateral.mint(depositor, 1000e6);
        vm.prank(depositor);
        collateral.approve(address(morpho), type(uint256).max);

        // add adapter
        vm.startPrank(curator);
        morpho.submit(abi.encodeCall(IVaultV2.addAdapter, address(adapter)));
        morpho.addAdapter(address(adapter));

        // set caps
        bytes memory adapterId = abi.encode("this", address(adapter));
        morpho.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (adapterId, 100000000e6)));
        morpho.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (adapterId, 1e18)));
        morpho.increaseAbsoluteCap(adapterId, 100000000e6);
        morpho.increaseRelativeCap(adapterId, 1e18);

        // deposit funds into morpho vault
        resetPrank(depositor);
        morpho.deposit(1000e6, depositor);

        // set max rate with no cap
        resetPrank(morphoAllocator);
        morpho.setMaxRate(MAX_MAX_RATE);

        // allocate to adapter
        morpho.allocate(address(adapter), new bytes(0), 1000e6);
        assertEq(morpho.totalAssets(), 1000e6);
        vm.stopPrank();

        // mock earning interest by sending tokens to vault
        collateral.mint(address(vault), 1000e6);

        // simulate 1 year of time passing
        vm.warp(block.timestamp + ONE_YEAR_SECONDS);
        vm.roll(block.number + ONE_YEAR_BLOCKS);

        assertApproxEqAbs(morpho.totalAssets(), 2000e6, VAULT_TOLERANCE);

        // deallocate
        vm.startPrank(morphoAllocator);
        morpho.deallocate(address(adapter), new bytes(0), 1900e6);
        assertApproxEqAbs(morpho.totalAssets(), 2000e6, VAULT_TOLERANCE);

        // withdraw
        resetPrank(depositor);
        morpho.withdraw(1900e6, depositor, depositor);
        assertEq(collateral.balanceOf(depositor), 1900e6);
        assertApproxEqAbs(morpho.totalAssets(), 100e6, VAULT_TOLERANCE);
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
        setUpMockVaultWithCollateral(100000e6);
        IController.Order memory order = getRedeemOrder(collateral, 10000e6, 3e18, 0);
        bytes32 orderHash = controller.hashOrder(order);
        IController.Signature memory signature = signOrder(payerKey, orderHash);
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
}
