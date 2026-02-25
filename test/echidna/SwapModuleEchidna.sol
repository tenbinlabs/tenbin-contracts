// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {EchidnaBase} from "./EchidnaBase.sol";
import {IAggregationRouterV6} from "src/external/1inch/IAggregationRouterV6.sol";
import {ISwapModule} from "src/interface/ISwapModule.sol";
import {SwapModule} from "src/SwapModule.sol";

// echidna test/echidna/SwapModuleEchidna.sol  --contract SwapModuleEchidna --config echidna.yaml
contract SwapModuleEchidna is EchidnaBase {
    SwapModule swapModule;
    address router;
    address manager;
    address executor;

    constructor() {
        manager = address(0x4); // Not used by echidna as function caller
        executor = address(0x5);
        router = address(0x6);
        swapModule = new SwapModule(manager, router, address(this));
    }

    // Manager is constant
    function echidna_manager_never_changes() public view returns (bool) {
        return swapModule.manager() == manager;
    }

    // Router is constant
    function echidna_router_never_changes() public view returns (bool) {
        return swapModule.router() == address(router);
    }

    // Swaps always revert for unauthorized callers
    function echidna_swap_always_fails_unauthorized_caller() public returns (bool) {
        // create input data
        ISwapModule.SwapParameters memory params = ISwapModule.SwapParameters({
            swapType: 0,
            router: address(router),
            srcToken: address(collateral),
            dstToken: address(collateral2),
            amount: 1000e18,
            minReturnAmount: 1000e18
        });
        IAggregationRouterV6.SwapDescription memory desc = IAggregationRouterV6.SwapDescription({
            srcToken: collateral,
            dstToken: collateral2,
            srcReceiver: payable(address(executor)),
            dstReceiver: payable(address(manager)),
            amount: 1000e18,
            minReturnAmount: 1000e18,
            flags: uint256(0)
        });
        bytes memory parameters = abi.encode(params);
        bytes memory data = new bytes(0);
        bytes memory swapData = abi.encode(executor, desc, data);

        try swapModule.swap(parameters, swapData) {
            return false;
        } catch {
            return true;
        }
    }

    // Swaps can only use 1inch swap type
    function echidna_swap_1inch_only() public returns (bool) {
        // create input data
        ISwapModule.SwapParameters memory params = ISwapModule.SwapParameters({
            swapType: 1, //wrong type
            router: address(router),
            srcToken: address(collateral),
            dstToken: address(collateral2),
            amount: 1000e18,
            minReturnAmount: 1000e18
        });
        IAggregationRouterV6.SwapDescription memory desc = IAggregationRouterV6.SwapDescription({
            srcToken: collateral,
            dstToken: collateral2,
            srcReceiver: payable(address(executor)),
            dstReceiver: payable(address(manager)),
            amount: 1000e18,
            minReturnAmount: 1000e18,
            flags: uint256(0)
        });
        bytes memory parameters = abi.encode(params);
        bytes memory data = new bytes(0);
        bytes memory swapData = abi.encode(executor, desc, data);

        try swapModule.swap(parameters, swapData) {
            return false;
        } catch {
            return true;
        }
    }
}
