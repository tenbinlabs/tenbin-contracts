// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {StakedAsset} from "src/StakedAsset.sol";

contract StakedAssetHarness is StakedAsset {
    function exposedPendingRewards() external view returns (uint256) {
        return _pendingRewards();
    }
}
