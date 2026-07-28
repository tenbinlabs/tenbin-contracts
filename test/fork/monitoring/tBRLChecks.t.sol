// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {MonitorBase} from "./MonitorBase.sol";
import {RolesChecksBase} from "./RolesChecksBase.t.sol";
import {SanityCheckBase} from "./SanityCheckBase.sol";
import {VaultChecksBase} from "./VaultChecksBase.sol";

contract tBRLChecks is RolesChecksBase, SanityCheckBase, VaultChecksBase {
    function setUp() public override(MonitorBase, VaultChecksBase) {
        assetName = "tBRL";
        super.setUp();
    }
}
