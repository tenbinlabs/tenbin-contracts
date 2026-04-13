// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BuildSafeBatch} from "../../script/BuildSafeBatch.s.sol";

contract BuildSafeBatchHarness is BuildSafeBatch {
    function exposedParseAddress(string memory a) external pure returns (address) {
        return _parseAddress(a);
    }
}
