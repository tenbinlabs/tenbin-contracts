// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Deploy} from "../../script/Deploy.s.sol";

/// @notice Deploy script with a mismatched version to exercise the controller version check
contract DeployHarness is Deploy {
    function getVersion() internal pure override returns (string memory) {
        return "0.4.0";
    }
}
