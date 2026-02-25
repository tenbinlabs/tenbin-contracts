// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {CollateralManager} from "src/CollateralManager.sol";
import {CollateralManagerHarness} from "test/harness/CollateralManagerHarness.sol";
import {ForkBaseTest} from "test/fork/ForkBaseTest.sol";
import {IAggregationRouterV6} from "src/external/1inch/IAggregationRouterV6.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ISwapModule} from "src/interface/ISwapModule.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {SwapModuleHarness} from "test/harness/SwapModuleHarness.sol";

contract OneInchForkTest is ForkBaseTest {
    using SafeERC20 for IERC20;

    uint256 internal constant SWAP_TOLERANCE_USDC = 2000000;
    uint256 internal constant SWAP_TOLERANCE_USDT = 2000000;

    address internal managerFork = 0x92277F9C58074f2FcE619338bC2AAf4b9625e798;
    IAggregationRouterV6 router1Inch = IAggregationRouterV6(0x111111125421cA6dc452d289314280a0f8842A65);

    function setUp() public override {
        super.setUp();
        setUpMockVaults();

        // deploy code to mainnet account which has real USDC and USDT balance
        address managerImplementation = address(new CollateralManager());
        bytes memory data = abi.encodeWithSelector(CollateralManager.initialize.selector, address(controller), owner);
        deployCodeTo("ERC1967Proxy.sol", abi.encode(managerImplementation, data), managerFork);

        // create swap module using new manager and 1inch mainnet router
        manager = CollateralManagerHarness(managerFork);
        router = router1Inch;
        swapModule = new SwapModuleHarness(address(manager), address(router), address(this));

        // set up manager again using the new manager contract
        setUpManager();

        // add usdc and usdt as collateral in manager
        vm.startPrank(owner);
        manager.addCollateral(address(usdc), address(usdcVault));
        manager.addCollateral(address(usdt), address(usdtVault));
        vm.stopPrank();
        vm.startPrank(capAdjuster);
        manager.setMinSwapPrice(address(usdc), address(usdt), 0.98e6); // 2%
        manager.setMinSwapPrice(address(usdt), address(usdc), 0.98e6); // 2%
        vm.stopPrank();

        vm.startPrank(capAdjuster);
        manager.setSwapCap(address(usdc), type(uint256).max);
        manager.setSwapCap(address(usdt), type(uint256).max);
        vm.stopPrank();
    }

    // mock 1inch data with a real 1inch API response at this block
    function getMock1InchData() internal pure returns (bytes memory mockData) {
        mockData =
            hex"07ed23790000000000000000000000005141b82f5ffda4c6fe1e372978f1c5427640a190000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec70000000000000000000000005141b82f5ffda4c6fe1e372978f1c5427640a19000000000000000000000000092277f9c58074f2fce619338bc2aaf4b9625e7980000000000000000000000000000000000000000000000000000000002625a0000000000000000000000000000000000000000000000000000000000025b4da700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000120000000000000000000000000000000000000000000000000000000000000021c0000000000000000000000000000000000000000000000000001fe00004e00a0744c8c09a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4890cbe4bdd538d6e9b379bff5fe72c3d67a521de50000000000000000000000000000000000000000000000000000000000009c405120bbcb91440523216e2b87052a99f69c604a7b6e00a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800847fc9d4ad000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000025b4da7000000000000000000000000111111125421ca6dc452d289314280a0f8842a650000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000bd1ac499";
    }

    // helper function to strip selector and parse swap description from 1inch data
    function parse1InchData(bytes memory data)
        internal
        pure
        returns (
            bytes4 selector,
            address executor,
            IAggregationRouterV6.SwapDescription memory desc,
            bytes memory swapData
        )
    {
        // read selector from first 4 bytes
        assembly {
            let word := mload(add(data, 32))
            selector := shr(224, word) // shift right 28 bytes
        }

        // slice off selector
        bytes memory args;
        assembly {
            // args will start 4 bytes further into `data`
            args := add(data, 4)

            // overwrite length slot
            let len := mload(data)
            mstore(args, sub(len, 4))
        }

        // decode remaining arguments
        (executor, desc, swapData) = abi.decode(args, (address, IAggregationRouterV6.SwapDescription, bytes));
    }

    // ensure fork address has sufficient usdc and usdt
    function testFork_1Inch_Setup() public view {
        assertGt(usdc.balanceOf(managerFork), 40e6);
        assertGt(usdt.balanceOf(managerFork), 40e6);
    }

    function testFork_1Inch_Swap() public {
        // save balances before swap
        uint256 usdcBalanceBefore = usdc.balanceOf(managerFork);
        uint256 usdtBalanceBefore = usdt.balanceOf(managerFork);

        // parse data
        (/* bytes4 selector */, address executor, IAggregationRouterV6.SwapDescription memory desc, bytes memory data) =
            parse1InchData(getMock1InchData());

        // create input data
        ISwapModule.SwapParameters memory params = ISwapModule.SwapParameters({
            swapType: 0,
            router: address(router),
            srcToken: address(usdc),
            dstToken: address(usdt),
            amount: 40e6,
            minReturnAmount: desc.minReturnAmount
        });
        bytes memory parameters = abi.encode(params);
        bytes memory swapData = abi.encode(executor, desc, data);

        // perform swap
        vm.prank(curator);
        manager.swap(parameters, swapData);

        // check balances
        assertApproxEqAbs(usdc.balanceOf(address(manager)), usdcBalanceBefore - 40e6, SWAP_TOLERANCE_USDC);
        assertGt(usdt.balanceOf(address(manager)), usdtBalanceBefore + 40e6 - SWAP_TOLERANCE_USDT);
    }
}
