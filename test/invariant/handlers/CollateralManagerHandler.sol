// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {CollateralManager} from "../../../src/CollateralManager.sol";
import {IAggregationRouterV6} from "../../../src/external/1inch/IAggregationRouterV6.sol";
import {ISwapModule} from "../../../src/interface/ISwapModule.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockERC4626} from "../../mocks/MockERC4626.sol";
import {SwapModule} from "../../../src/SwapModule.sol";
import {Test} from "forge-std/test.sol";

/// @dev Handler to interact with the collateral manager and save snapshots for invariant testing
contract CollateralManagerHandler is Test {
    CollateralManager manager;
    MockERC20 collateral;
    SwapModule swapModule;
    IAggregationRouterV6 router;
    address admin;
    address owner;
    address curator;
    address capAdjuster;
    address rebalancer;
    address[] public addedCollaterals = new address[](50);
    address[] public addedVaults = new address[](50);
    uint256 public counter;
    uint256 public totalCollateral;
    uint256 public totalWithdraw;

    constructor(
        CollateralManager _manager,
        MockERC20 _collateral,
        SwapModule _swapModule,
        IAggregationRouterV6 _router,
        address _admin,
        address _curator,
        address _capAdjuster,
        address _rebalancer,
        address _owner
    ) {
        manager = _manager;
        swapModule = _swapModule;
        router = _router;
        admin = _admin;
        curator = _curator;
        capAdjuster = _capAdjuster;
        collateral = _collateral;
        rebalancer = _rebalancer;
        owner = _owner;
    }

    // addCollateral
    function addCollateral(uint256 amount) public {
        amount = bound(amount, 0, 1e40);
        MockERC20 newCollateral = new MockERC20("Mock Collateral", "MCLT", 18);
        MockERC4626 newVault = new MockERC4626("Mock Vault", "MVLT", newCollateral);
        newCollateral.mint(address(newVault), amount);
        vm.prank(owner);
        manager.addCollateral(address(newCollateral), address(newVault));

        totalCollateral += amount;

        addedCollaterals[counter] = address(newCollateral);
        addedVaults[counter] = address(newVault);
        counter++;
    }

    // deposit
    function deposit(uint256 amount) public {
        amount = bound(amount, 0, 1e40);

        collateral.mint(address(manager), amount);

        // perform deposit
        vm.prank(curator);
        manager.deposit(address(collateral), amount, 0);

        totalCollateral += amount;
    }

    // rebalance
    function rebalance(uint256 amount) public {
        amount = bound(amount, 0, 1e40);
        collateral.mint(address(manager), amount);

        uint256 capAmount = amount * 1e17 / 1e18; // 10% of amount

        uint256 rebalanceAmount = capAmount / 2; // Ensure is less than cap

        vm.prank(capAdjuster);
        manager.setRebalanceCap(address(collateral), rebalanceAmount);

        vm.prank(rebalancer);
        manager.rebalance(address(collateral), rebalanceAmount);
    }

    // rescueEther
    function rescueEther(uint256 amount) public {
        amount = bound(amount, 0, 10_000 ether);
        deal(address(manager), amount);
        vm.prank(admin);
        manager.rescueEther();
    }

    // setRebalanceCap
    function setRebalanceCap(uint256 amount) public {
        amount = bound(amount, 0, 1e40);

        vm.prank(capAdjuster);
        manager.setRebalanceCap(address(collateral), amount);
    }

    // swap
    function swap(uint256 amount) public {
        amount = bound(amount, 0, 1e40);
        // setup
        address executor = vm.addr(0x1111);
        MockERC20 collateral2 = new MockERC20("Mock Collateral", "MCLT", 18);
        MockERC4626 vault2 = new MockERC4626("Mock Vault", "MVLT", collateral2);
        vm.startPrank(capAdjuster);
        manager.setSwapCap(address(collateral), type(uint256).max);
        manager.setSwapCap(address(collateral2), type(uint256).max);
        vm.stopPrank();

        collateral2.mint(address(vault2), amount);
        vm.prank(owner);
        manager.addCollateral(address(collateral2), address(vault2));

        addedCollaterals[counter] = address(collateral2);
        addedVaults[counter] = address(vault2);
        counter++;
        totalCollateral += amount;

        // create input data
        ISwapModule.SwapParameters memory params = ISwapModule.SwapParameters({
            swapType: 0,
            router: address(router),
            srcToken: address(collateral),
            dstToken: address(collateral2),
            amount: 1000e6,
            minReturnAmount: 1000e18
        });
        IAggregationRouterV6.SwapDescription memory desc = IAggregationRouterV6.SwapDescription({
            srcToken: collateral,
            dstToken: collateral2,
            srcReceiver: payable(address(router)),
            dstReceiver: payable(address(manager)),
            amount: 1000e6,
            minReturnAmount: 1000e18,
            flags: uint256(0)
        });
        bytes memory parameters = abi.encode(params);
        bytes memory data = new bytes(0);
        bytes memory swapData = abi.encode(executor, desc, data);

        // mint tokens
        collateral.mint(address(manager), 1000e6);
        collateral2.mint(address(router), 1000e18);

        // perform swap
        vm.prank(curator);
        manager.swap(parameters, swapData);
    }

    // withdraw
    function withdraw(uint256 amount) public {
        amount = bound(amount, 0, 1e40);
        // send tokens to collateral manager
        collateral.mint(address(manager), amount);
        // deposit into underlying
        vm.prank(curator);
        manager.deposit(address(collateral), amount, 0);

        totalCollateral += amount;

        // withdraw from underlying
        vm.prank(curator);
        manager.withdraw(address(collateral), amount, UINT256_MAX);
        totalWithdraw += amount;
    }

    // withdrawRevenue
    function withdrawRevenue(uint256 amount) public {
        amount = bound(amount, 0, 1e40);

        vm.prank(curator);
        collateral.mint(address(manager), amount);
        vm.prank(curator);
        manager.deposit(address(collateral), amount, 0);
        totalCollateral += amount;

        address vault = address(manager.vaults(address(collateral)));
        vm.prank(curator);
        collateral.mint(vault, amount);
        totalCollateral += amount;

        uint256 withdrawAmount = amount / 2;

        vm.prank(curator);
        manager.withdraw(address(collateral), withdrawAmount, UINT256_MAX);

        totalWithdraw += withdrawAmount;

        vm.prank(address(manager.revenueModule()));
        manager.withdrawRevenue(address(collateral), withdrawAmount);
    }
}
