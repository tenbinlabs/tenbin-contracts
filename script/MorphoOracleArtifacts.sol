// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {MorphoChainlinkOracleV2} from "morpho-blue-oracles/src/morpho-chainlink/MorphoChainlinkOracleV2.sol";

// Compile the pinned oracle separately from the 0.8.30 deployment script.
contract MorphoOracleArtifacts {
    MorphoChainlinkOracleV2 internal oracle;
}
