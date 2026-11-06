// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {MonitorBase} from "./MonitorBase.sol";
import {RolesChecksBase} from "./RolesChecksBase.t.sol";
import {SanityCheckBase} from "./SanityCheckBase.sol";
import {AdapterChecksBase} from "./AdapterChecksBase.sol";

contract tPYRChecks is RolesChecksBase, SanityCheckBase, AdapterChecksBase {
    function setUp() public override(MonitorBase, AdapterChecksBase) {
        assetName = "tPYR";
        super.setUp();
    }
}
