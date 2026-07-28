// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetSilo} from "tenbin-contracts/src/AssetSilo.sol";
import {console2} from "forge-std/console2.sol";
import {DeployBase} from "./DeployBase.s.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SwapModule} from "tenbin-contracts/src/SwapModule.sol";

/// FOUNDRY_PROFILE=production forge script script/DeploySwapModule.s.sol $CONFIG_DIR --rpc-url $MAINNET_RPC_URL --private-key $BROADCASTER_KEY --verify --verifier etherscan --verifier-api-key $ETHERSCAN_API_KEY --slow
contract DeploySwapModule is DeployBase {
    // configuration
    string constant TARGET_VERSION = "1.4.3";
    address constant ASSET_TOKEN_ADDRESS = 0x067f03Be93c7Dcd21C3eB700f58203F514c2Be1A;
    address constant MANAGER_ADDRESS = 0x7d673FC54632a4cb8B31e6AD5678aA1Fd834A528;

    /// @notice Results returned when running this deployment script
    struct DeploymentResult {
        address broadcaster;
        SwapModule swap_module;
        address manager;
    }

    /// @dev The version for this deployment
    function getVersion() internal pure override returns (string memory) {
        return TARGET_VERSION;
    }

    function run(string memory configDir) public returns (DeploymentResult memory deployment) {
        loadCoreConfig(configDir);
        loadRolesConfig();
        deployment = deploy();
    }

    function deploy() internal broadcast returns (DeploymentResult memory deployment) {
        console2.log("\n========================= Accounts ==========================\n");
        console2.log("broadcaster address: ", broadcaster);

        // save broadcaster
        deployment.broadcaster = broadcaster;

        // deploy swap module
        deployment.swap_module =
            new SwapModule{salt: SALT}(MANAGER_ADDRESS, address(coreParams.one_inch_router), roles.admin_role);

        printContracts(deployment);
        printLogo();
    }

    function printContracts(DeploymentResult memory deployment) internal pure {
        console2.log("\n========================= Contracts =========================\n");
        console2.log("SwapModule: ", address(deployment.swap_module));
        console2.log("\n=============================================================\n");
    }
}
