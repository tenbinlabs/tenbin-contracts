// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/console2.sol";
import {Controller} from "tenbin-contracts/src/Controller.sol";
import {DeployBase} from "./DeployBase.s.sol";
import {MXNOracleAdapter} from "../src/oracle/MXNOracleAdapter.sol";
import {IOracleAdapter} from "tenbin-contracts/src/interface/IOracleAdapter.sol";
import {RevenueModule} from "tenbin-contracts/src/RevenueModule.sol";

/// @notice Deploy and configure an oracle adapter using constants
/// Running this script:
/// FOUNDRY_PROFILE=production forge script script/DeployOracleAdapter.s.sol --rpc-url $MAINNET_RPC_URL --private-key $BROADCASTER_KEY --verify --verifier etherscan --verifier-api-key $ETHERSCAN_API_KEY --slow
contract DeployOracleAdapter is DeployBase {
    // configuration for the controller that is being upgraded
    string constant TARGET_VERSION = "1.4.3";
    address constant ORACLE_ADDRESS = 0xdb4881Ab0ad6b8423f76dd8C9d65542749a1dB77;

    /// @notice Results returned when running this deployment script
    struct DeploymentResult {
        address broadcaster;
        IOracleAdapter oracle_adapter;
    }

    /// @dev The version for this deployment
    function getVersion() internal pure virtual override returns (string memory) {
        return TARGET_VERSION;
    }

    function run() public returns (DeploymentResult memory deployment) {
        deployment = deploy();
    }

    function deploy() internal broadcast returns (DeploymentResult memory deployment) {
        console2.log("\n========================= Accounts ==========================\n");
        console2.log("broadcaster address: ", broadcaster);

        // save broadcaster
        deployment.broadcaster = broadcaster;
        deployment.oracle_adapter = IOracleAdapter(address(new MXNOracleAdapter()));

        printContracts(deployment);
        printLogo();
    }

    function printContracts(DeploymentResult memory deployment) internal pure {
        console2.log("\n========================= Contracts =========================\n");
        console2.log("RevenueModule: ", address(deployment.oracle_adapter));
        console2.log("\n=============================================================\n");
    }
}
