// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IAggregationRouterV6} from "src/external/1inch/IAggregationRouterV6.sol";
import {IERC20Errors} from "lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {ISwapModule} from "src/interface/ISwapModule.sol";
import {Mock1InchRouter, Mock1InchRouterWithInsufficientReturnAmount} from "test/mocks/Mock1InchRouter.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {SwapModuleHarness} from "test/harness/SwapModuleHarness.sol";
import {Test} from "forge-std/Test.sol";

contract SwapModuleTest is Test {
    // constants
    bytes32 internal constant CURATOR_ROLE = keccak256("CURATOR_ROLE");

    // accounts
    address internal curator;
    address internal manager;
    address internal executor;

    // contracts
    IAggregationRouterV6 router;
    MockERC20 internal token0;
    MockERC20 internal token1;
    SwapModuleHarness internal swapModule;

    function setUp() public {
        curator = vm.addr(0xA000);
        manager = vm.addr(0xA001);
        executor = vm.addr(0xA002);
        router = new Mock1InchRouter();
        swapModule = new SwapModuleHarness(manager, address(router));
        token0 = new MockERC20("Token 0", "TK0", 18);
        token1 = new MockERC20("Token 1", "TK1", 18);
        vm.label({account: curator, newLabel: "curator"});
        vm.label({account: manager, newLabel: "manager"});
        vm.label({account: executor, newLabel: "executor"});
        vm.label({account: address(router), newLabel: "router"});
        vm.label({account: address(token0), newLabel: "token0"});
        vm.label({account: address(token1), newLabel: "token1"});
        vm.label({account: address(swapModule), newLabel: "swapModule"});
    }

    function test_Swap1Inch() public {
        // create input data
        ISwapModule.SwapParameters memory params = ISwapModule.SwapParameters({
            swapType: 0,
            router: address(router),
            srcToken: address(token0),
            dstToken: address(token1),
            amount: 1000e18,
            minReturnAmount: 1000e18
        });
        IAggregationRouterV6.SwapDescription memory desc = IAggregationRouterV6.SwapDescription({
            srcToken: token0,
            dstToken: token1,
            srcReceiver: payable(address(router)),
            dstReceiver: payable(address(manager)),
            amount: 1000e18,
            minReturnAmount: 1000e18,
            flags: uint256(0)
        });
        bytes memory parameters = abi.encode(params);
        bytes memory data = new bytes(0);
        bytes memory swapData = abi.encode(executor, desc, data);

        // mint tokens
        token0.mint(address(swapModule), 1000e18);
        token1.mint(address(router), 1000e18);

        // perform swap
        vm.prank(manager);
        swapModule.swap(parameters, swapData);

        // check balances
        assertEq(token0.balanceOf(address(swapModule)), 0);
        assertEq(token1.balanceOf(address(manager)), 1000e18);
    }

    function test_Revert_Swap1Inch() public {
        // create bad input data
        ISwapModule.SwapParameters memory params = ISwapModule.SwapParameters({
            swapType: 99,
            router: address(0),
            srcToken: address(0),
            dstToken: address(0),
            amount: 1,
            minReturnAmount: 2000e18
        });
        IAggregationRouterV6.SwapDescription memory desc = IAggregationRouterV6.SwapDescription({
            srcToken: token0,
            dstToken: token1,
            srcReceiver: payable(address(router)),
            dstReceiver: payable(address(0)),
            amount: 1000e18,
            minReturnAmount: 1000e18,
            flags: uint256(0)
        });
        bytes memory parameters = abi.encode(params);
        bytes memory data = new bytes(0);
        bytes memory swapData = abi.encode(executor, desc, data);

        // revert when non-manager account calls swap function
        vm.expectRevert(ISwapModule.OnlyManager.selector);
        swapModule.swap(new bytes(0), new bytes(0));

        vm.startPrank(manager);

        // revert when incorrect encoding for params
        vm.expectRevert();
        swapModule.swap(new bytes(0), swapData);

        // revert when swap type not supported
        vm.expectRevert(ISwapModule.SwapTypeNotSupported.selector);
        swapModule.swap(parameters, swapData);
        params.swapType = 0;

        // revert on bad 1inch data decodes
        vm.expectRevert();
        swapModule.swap(abi.encode(params), new bytes(0));

        // revert on invalid router
        vm.expectRevert(ISwapModule.InvalidRouter.selector);
        swapModule.swap(abi.encode(params), abi.encode(executor, desc, data));
        params.router = address(router);

        // revert on src token mismatch
        vm.expectRevert(ISwapModule.InvalidSrcToken.selector);
        swapModule.swap(abi.encode(params), abi.encode(executor, desc, data));
        params.srcToken = address(token0);

        // revert on dst token mismatch
        vm.expectRevert(ISwapModule.InvalidDstToken.selector);
        swapModule.swap(abi.encode(params), abi.encode(executor, desc, data));
        params.dstToken = address(token1);

        // revert on amount mismatch
        vm.expectRevert(ISwapModule.InvalidAmount.selector);
        swapModule.swap(abi.encode(params), abi.encode(executor, desc, data));
        params.amount = 1000e18;

        // revert on return amount mismatch
        vm.expectRevert(ISwapModule.InvalidMinReturnAmount.selector);
        swapModule.swap(abi.encode(params), abi.encode(executor, desc, data));
        params.minReturnAmount = 1000e18;

        // revert on invalid receiver
        // if (swapData.dstReceiver != manager) revert InvalidReceiver();
        vm.expectRevert(ISwapModule.InvalidReceiver.selector);
        swapModule.swap(abi.encode(params), abi.encode(executor, desc, data));
        desc.dstReceiver = payable(manager);

        // revert on insufficient module balance
        vm.startPrank(manager);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        swapModule.swap(abi.encode(params), abi.encode(executor, desc, data));
        token0.mint(address(swapModule), 1000e18);

        // revert on insufficient router balance
        vm.startPrank(manager);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        swapModule.swap(abi.encode(params), abi.encode(executor, desc, data));
        token1.mint(address(router), 1000e18);
        vm.stopPrank();

        // revert on insufficient tokens received
        vm.etch(address(router), address(new Mock1InchRouterWithInsufficientReturnAmount()).code);
        vm.startPrank(manager);
        vm.expectRevert(ISwapModule.InsufficientReturnAmount.selector);
        swapModule.swap(abi.encode(params), abi.encode(executor, desc, data));
    }

    function test_fuzz_Swap1Inch(uint256 amount) public {
        amount = bound(amount, 100, 1e40);
        // create input data
        ISwapModule.SwapParameters memory params = ISwapModule.SwapParameters({
            swapType: 0,
            router: address(router),
            srcToken: address(token0),
            dstToken: address(token1),
            amount: amount,
            minReturnAmount: amount
        });
        IAggregationRouterV6.SwapDescription memory desc = IAggregationRouterV6.SwapDescription({
            srcToken: token0,
            dstToken: token1,
            srcReceiver: payable(address(router)),
            dstReceiver: payable(address(manager)),
            amount: amount,
            minReturnAmount: amount,
            flags: uint256(0)
        });
        bytes memory parameters = abi.encode(params);
        bytes memory data = new bytes(0);
        bytes memory swapData = abi.encode(executor, desc, data);

        // mint tokens
        token0.mint(address(swapModule), amount);
        token1.mint(address(router), amount);

        // perform swap
        vm.prank(manager);
        swapModule.swap(parameters, swapData);

        // check balances
        assertEq(token0.balanceOf(address(swapModule)), 0);
        assertEq(token1.balanceOf(address(manager)), amount);
    }

    function test_ExposedSwap1Inch() public {
        // create input data
        ISwapModule.SwapParameters memory params = ISwapModule.SwapParameters({
            swapType: 0,
            router: address(router),
            srcToken: address(token0),
            dstToken: address(token1),
            amount: 1000e18,
            minReturnAmount: 1000e18
        });
        IAggregationRouterV6.SwapDescription memory desc = IAggregationRouterV6.SwapDescription({
            srcToken: token0,
            dstToken: token1,
            srcReceiver: payable(address(router)),
            dstReceiver: payable(address(manager)),
            amount: 1000e18,
            minReturnAmount: 1000e18,
            flags: uint256(0)
        });
        //bytes memory parameters = abi.encode(params);
        bytes memory data = new bytes(0);
        bytes memory swapData = abi.encode(executor, desc, data);

        // mint tokens
        token0.mint(address(swapModule), 1000e18);
        token1.mint(address(router), 1000e18);

        // perform swap
        vm.prank(manager);
        swapModule.exposedSwap1Inch(params, swapData);

        // check balances
        assertEq(token0.balanceOf(address(swapModule)), 0);
        assertEq(token1.balanceOf(address(manager)), 1000e18);
    }
}
