// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {DeployController} from "../../script/DeployController.s.sol";

contract DeployControllerHarness is DeployController {
    function getVersion() internal pure override returns (string memory) {
        return "0.4.0";
    }
}
