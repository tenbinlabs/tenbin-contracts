// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Deploy} from "../../script/Deploy.s.sol";

contract DeployDevelopmentHarness is Deploy {
    function getVersion() internal pure override returns (string memory) {
        return "0.4.0";
    }
}
