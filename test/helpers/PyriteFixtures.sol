// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

abstract contract PyriteFixtures is Test {
    function writePyriteFixtures(string memory network, string memory destination, string memory section)
        internal
        returns (string memory asset, string memory vault)
    {
        // safe: this synthetic key is used only by isolated deployment tests.
        // forge-lint: disable-next-line(unsafe-cheatcode)
        vm.rememberKey(0x3456);
        bool mocks = keccak256(bytes(network)) == keccak256("sepolia");
        string memory source = string.concat("config/", network, "/tpyr/");
        vm.createDir(string.concat(destination, "vaults"), true);
        vm.createDir(string.concat(destination, "adapters"), true);
        vm.createDir(string.concat(destination, "markets"), true);
        {
            string memory stem = mocks ? "tpyr_sepolia" : "tpyr";
            string memory assetName = string.concat(stem, ".toml");
            string memory vaultName = string.concat("vaults/", stem, mocks ? "_vault.toml" : "_usdc_vault.toml");
            asset = copyPyriteConfig(source, destination, assetName, network, section);
            vault = copyPyriteConfig(source, destination, vaultName, network, section);
        }
        resetPyriteAddress(asset, section, "vault");
        resetPyriteAddress(vault, section, "manager");
        string memory vaultConfig = vm.readFile(vault);
        string[] memory adapters = vm.parseTomlStringArray(vaultConfig, string.concat(".", section, ".string.adapters"));
        for (uint256 i; i < adapters.length; i++) {
            string memory path = copyPyriteConfig(
                source, destination, string.concat("adapters/", adapters[i], ".toml"), network, section
            );
            resetPyriteAddress(path, section, "parent");
            if (mocks) resetPyriteAddress(path, section, "vault");
        }
        string[] memory markets = vm.parseTomlStringArray(vaultConfig, string.concat(".", section, ".string.markets"));
        for (uint256 i; i < markets.length; i++) {
            string memory path =
                copyPyriteConfig(source, destination, string.concat("markets/", markets[i], ".toml"), network, section);
            resetPyriteAddress(path, section, "collateral_token");
            resetPyriteAddress(path, section, "oracle");
            if (mocks) {
                resetPyriteAddress(path, section, "base_feed");
                resetPyriteAddress(path, section, "quote_feed");
            }
        }
    }

    function copyPyriteConfig(
        string memory source,
        string memory destination,
        string memory name,
        string memory network,
        string memory section
    ) internal returns (string memory path) {
        string memory contents = vm.readFile(string.concat(source, name));
        contents = vm.replace(contents, string.concat("[", network), string.concat("[", section));
        if (keccak256(bytes(section)) == keccak256("31337")) {
            contents = vm.replace(contents, "${SEPOLIA_RPC_URL}", "http://localhost:8545");
        }
        path = string.concat(destination, name);
        vm.writeFile(path, contents);
    }

    function resetPyriteAddress(string memory path, string memory section, string memory key) internal {
        vm.writeToml(
            '"0x0000000000000000000000000000000000000000"', path, string.concat(".", section, ".address.", key)
        );
    }
}
