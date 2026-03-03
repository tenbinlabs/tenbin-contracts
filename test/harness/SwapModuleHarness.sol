// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SwapModule} from "../../src/SwapModule.sol";

contract SwapModuleHarness is SwapModule {
    constructor(address manager_, address router_, address admin_) SwapModule(manager_, router_, admin_) {}

    function exposedSwap1Inch(SwapParameters memory params, bytes calldata data) external {
        swap1Inch(params, data);
    }
}
