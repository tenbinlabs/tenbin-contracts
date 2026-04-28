// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "../BaseTest.sol";

// echidna: echidna test/invariant/AssetTokenInvariant.t.sol --contract AssetTokenInvariantTest --config echidna.yaml
// Base invariant contract that skip unsupported cheatcodes calls
contract InvariantBase is BaseTest {
    address internal constant INVARIANT_BROADCASTER = address(0x1000);

    function getTestBroadcaster() internal pure override returns (address account) {
        return INVARIANT_BROADCASTER;
    }

    function assertApproxEqAbs(uint256 left, uint256 right, uint256 maxDelta) internal pure override {
        bool isEqual = left == right;
        uint256 realDelta = left > right ? left - right : right - left;
        require(isEqual || realDelta <= maxDelta);
    }
}
