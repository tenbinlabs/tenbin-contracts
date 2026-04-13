// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {DeployDevelopmentMock} from "./DeployDevelopmentMock.s.sol";

/// @notice Deploy a current version of the protocol for mainnet testing
contract DeployDevelopment is DeployDevelopmentMock {
    function run() public override returns (DeploymentResult memory) {
        // this script should only deploy the current development on mainnet
        require(block.chainid == 1);
        return super.run();
    }
}
