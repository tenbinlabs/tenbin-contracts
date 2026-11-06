// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {PyriteFixtures} from "../helpers/PyriteFixtures.sol";
import {NewAssetDeployer} from "../helpers/NewAssetDeployer.sol";
import {Deploy} from "../../script/Deploy.s.sol";
import {IMorphoChainlinkOracleV2} from "../external/morpho/IMorphoChainlinkOracleV2.sol";

/// forge-config: default.isolate = false
contract DeployNewAssetPricingTest is PyriteFixtures {
    function test_NewSymbolsUseConfiguredPricesAndSeparateArtifacts() public {
        vm.chainId(31337);
        string memory directory = string.concat("cache/test/new-asset-pricing/", vm.toString(bytes32(msg.sig)), "/");
        (string memory asset, string memory config) = writePyriteFixtures("sepolia", directory, "31337");
        NewAssetDeployer deployer = new NewAssetDeployer(vm.addr(0x3456), "");
        vm.writeToml('"Tenbin Test Asset"', asset, ".31337.string.asset_name");
        vm.writeToml('"tNEW"', asset, ".31337.string.asset_symbol");
        vm.writeToml('"stNEW"', asset, ".31337.string.staked_asset_symbol");
        vm.writeToml("2500000000000000000", asset, ".31337.uint.mock_oracle_price");
        (Deploy.CoreDeploymentResult memory core, Deploy.VaultDeploymentResult memory vault) =
            deployer.run(asset, config, true);
        assertEq(core.asset.symbol(), "tNEW");
        assertEq(core.staked_asset.symbol(), "stNEW");
        assertEq(core.oracle_adapter.getPrice(), 2.5e18);
        assertEq(IMorphoChainlinkOracleV2(vault.markets[0].params.oracle).price(), 2.5e24);
        string memory firstDirectory = deployer.artifactDirectory();
        assertEq(
            firstDirectory,
            string.concat("broadcast/DeployNewAsset.s.sol/31337/", vm.toString(address(core.asset)), "/artifacts")
        );
        string memory firstContracts = vm.readFile(string.concat(firstDirectory, "/contracts.json"));
        string memory firstOnboarding = vm.readFile(string.concat(firstDirectory, "/onboarding.json"));
        assertEq(vm.parseJsonAddress(firstContracts, ".localhost.tNEW.contracts.asset_token"), address(core.asset));
        assertEq(vm.parseJsonAddress(firstOnboarding, ".asset_token"), address(core.asset));
        assertEq(vm.parseJsonAddress(firstOnboarding, ".controller"), address(core.controller));

        vm.writeToml('"tNEXT"', asset, ".31337.string.asset_symbol");
        vm.writeToml('"stNEXT"', asset, ".31337.string.staked_asset_symbol");
        vm.writeToml('"tNEXTv-USDC"', config, ".31337.string.symbol");
        vm.writeToml("7500000000000000000", asset, ".31337.uint.mock_oracle_price");
        deployer = new NewAssetDeployer(vm.addr(0x3456), "");
        (core, vault) = deployer.run(asset, config, true);
        assertEq(core.oracle_adapter.getPrice(), 7.5e18);
        assertEq(IMorphoChainlinkOracleV2(vault.markets[0].params.oracle).price(), 7.5e24);
        string memory secondDirectory = deployer.artifactDirectory();
        assertTrue(keccak256(bytes(secondDirectory)) != keccak256(bytes(firstDirectory)));
        string memory secondContracts = vm.readFile(string.concat(secondDirectory, "/contracts.json"));
        assertEq(vm.parseJsonAddress(secondContracts, ".localhost.tNEXT.contracts.asset_token"), address(core.asset));
        assertEq(vm.readFile(string.concat(firstDirectory, "/contracts.json")), firstContracts);
        assertEq(vm.readFile(string.concat(firstDirectory, "/onboarding.json")), firstOnboarding);
    }
}
