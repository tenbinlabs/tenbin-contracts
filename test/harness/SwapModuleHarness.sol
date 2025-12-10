// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SwapModule} from "src/SwapModule.sol";

contract SwapModuleHarness is SwapModule {
    constructor(address manager_, address router_) SwapModule(manager_, router_) {}

    function exposedSwap1Inch(SwapParameters memory params, bytes calldata data) external {
        swap1Inch(params, data);
    }
}
