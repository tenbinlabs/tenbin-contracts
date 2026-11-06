// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {DeployNewAsset} from "../../script/DeployNewAsset.s.sol";

contract NewAssetDeployer is DeployNewAsset {
    string internal testOutputDirectory;

    constructor(address testBroadcaster, string memory directory) {
        broadcaster = testBroadcaster;
        testOutputDirectory = directory;
    }

    function constructCreate2Salt() public view override returns (bytes32) {
        return keccak256(abi.encode("New asset deployment tests", block.chainid, getVersion()));
    }

    function outputDirectory() internal view override returns (string memory) {
        if (bytes(testOutputDirectory).length == 0) return super.outputDirectory();
        return testOutputDirectory;
    }

    function artifactDirectory() external view returns (string memory) {
        return outputDirectory();
    }
}
