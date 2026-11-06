// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

contract TgldCcipConfigTest is Test {
    function test_AllRecordedTgldTestnetLanesMatchDeploymentRecords() public view {
        string memory json = vm.readFile("cross-chain-deployments.json");
        string[4] memory networks = ["eth-sepolia", "base-sepolia", "binance-testchain", "polygon-amoy"];
        string[4] memory chains = ["11155111", "84532", "97", "80002"];
        string[3] memory spokes = ["tgld_base", "tgld_binance", "tgld_polygon"];
        string[3] memory hubs = ["tgld_ethereum", "tgld_ethereum_binance", "tgld_ethereum_polygon"];
        for (uint256 i; i < spokes.length; i++) {
            checkLane(json, spokes[i], chains[i + 1], networks[i + 1], networks[0]);
            checkLane(json, hubs[i], chains[0], networks[0], networks[i + 1]);
        }
    }

    function test_SepoliaTgldTokensMatchCoreDeployment() public view {
        string memory crossChain = vm.readFile("cross-chain-deployments.json");
        string memory core = vm.readFile("deployments.json");
        assertEq(
            vm.parseJsonAddress(crossChain, ".testnet.eth-sepolia.tGLD.contracts.asset_token"),
            vm.parseJsonAddress(core, ".sepolia.tGLD.contracts.asset_token")
        );
        assertEq(
            vm.parseJsonAddress(crossChain, ".testnet.eth-sepolia.tGLD.contracts.staked_asset_token"),
            vm.parseJsonAddress(core, ".sepolia.tGLD.contracts.staked_asset")
        );
    }

    function checkLane(
        string memory json,
        string memory file,
        string memory chain,
        string memory local,
        string memory remote
    ) internal view {
        string memory toml = vm.readFile(string.concat("config/sepolia/tgld/ccip/", file, ".toml"));
        string memory section = string.concat(".", chain);
        string memory localPath = string.concat(".testnet.", local);
        string memory remotePath = string.concat(".testnet.", remote);
        assertEq(
            vm.parseTomlString(toml, string.concat(section, ".string.ccip_chain_selector")),
            vm.parseJsonString(json, string.concat(localPath, ".global.chain_selector"))
        );
        assertEq(
            vm.parseTomlString(toml, string.concat(section, ".string.remote_chain_selector")),
            vm.parseJsonString(json, string.concat(remotePath, ".global.chain_selector"))
        );
        string[4] memory fields = ["asset_token", "staked_asset_token", "asset_pool", "staked_asset_pool"];
        for (uint256 i; i < fields.length; i++) {
            checkAddress(
                toml,
                string.concat(section, ".address.", fields[i]),
                json,
                string.concat(localPath, ".tGLD.contracts.", fields[i])
            );
            checkAddress(
                toml,
                string.concat(section, ".address.remote_", fields[i]),
                json,
                string.concat(remotePath, ".tGLD.contracts.", fields[i])
            );
        }
        string[4] memory infrastructure = ["router", "rmn_proxy", "token_admin_registry", "registry_module_owner"];
        for (uint256 i; i < infrastructure.length; i++) {
            checkAddress(
                toml,
                string.concat(section, ".address.ccip_", infrastructure[i]),
                json,
                string.concat(localPath, ".global.", infrastructure[i])
            );
        }
        assertFalse(vm.parseTomlBool(toml, string.concat(section, ".bool.inbound_rate_limit_enabled")));
        assertFalse(vm.parseTomlBool(toml, string.concat(section, ".bool.outbound_rate_limit_enabled")));
        string[4] memory limits = ["inbound_capacity", "outbound_capacity", "inbound_rate", "outbound_rate"];
        for (uint256 i; i < limits.length; i++) {
            assertEq(vm.parseUint(vm.parseTomlString(toml, string.concat(section, ".string.", limits[i]))), 0);
        }
    }

    function checkAddress(string memory toml, string memory key, string memory json, string memory path) internal pure {
        address expected = vm.parseJsonAddress(json, path);
        assertNotEq(expected, address(0), path);
        assertEq(vm.parseTomlAddress(toml, key), expected, key);
    }
}
