// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseScript} from "./Base.s.sol";
import {Config} from "forge-std/Config.sol";
import {console2} from "forge-std/console2.sol";
import {Gate} from "../src/external/morpho/Gate.sol";
import {IAdapter} from "vault-v2/src/interfaces/IAdapter.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IMorphoVaultV1AdapterFactory} from "vault-v2/src/adapters/interfaces/IMorphoVaultV1AdapterFactory.sol";
import {IVaultV2} from "vault-v2/src/interfaces/IVaultV2.sol";
import {IVaultV2Factory} from "vault-v2/src/interfaces/IVaultV2Factory.sol";

/// @notice Deploy and configure a morpho v2 vault using config/vault.toml
contract DeployVault is BaseScript, Config {
    /// @notice Morpho Vault V2 Factory
    address constant VAULT_V2_FACTORY_ADDRESS = 0xA1D94F746dEfa1928926b84fB2596c06926C0405;
    /// @notice Morpho VaultV1Adapter Factory
    address constant VAULT_V1_ADAPTER_FACTORY_ADDRESS = 0xD1B8E2dee25c2b89DCD2f98448a7ce87d6F63394;

    /// @notice Parameters loaded from config/vault.toml
    VaultParams params;

    /// @notice Morpho vault parameters
    struct VaultParams {
        address adapter_registry;
        address allocator;
        address asset;
        address curator;
        address initial_vault;
        address owner;
        address sentinel;
        string name;
        string symbol;
        uint256 dead_deposit;
        uint256 initial_absolute_cap;
        uint256 initial_relative_cap;
        uint256 max_rate;
        uint256 timelock_duration;
    }

    /// @notice Contracts deployed by this script
    struct DeploymentResult {
        Gate gate;
        IVaultV2 vault;
        IAdapter adapter;
    }

    function loadConfig() internal {
        _loadConfig("./config/vault.toml", false);

        // load addresses
        params.adapter_registry = config.get("adapter_registry").toAddress();
        params.allocator = config.get("allocator").toAddress();
        params.asset = config.get("asset").toAddress();
        params.curator = config.get("curator").toAddress();
        params.owner = config.get("owner").toAddress();
        params.initial_vault = config.get("initial_vault").toAddress();
        params.sentinel = config.get("sentinel").toAddress();

        // load string
        params.name = config.get("name").toString();
        params.symbol = config.get("symbol").toString();

        // load uint
        params.dead_deposit = config.get("dead_deposit").toUint256();
        params.initial_absolute_cap = config.get("initial_absolute_cap").toUint256();
        params.initial_relative_cap = config.get("initial_relative_cap").toUint256();
        params.max_rate = config.get("max_rate").toUint256();
        params.timelock_duration = config.get("timelock_duration").toUint256();
    }

    function run() public returns (DeploymentResult memory deployment) {
        loadConfig();
        deployment = deploy();
    }

    function deploy() internal broadcast returns (DeploymentResult memory deployment) {
        // load factory addresses
        IVaultV2Factory vaultFactory = IVaultV2Factory(VAULT_V2_FACTORY_ADDRESS);
        IMorphoVaultV1AdapterFactory adapterFactory = IMorphoVaultV1AdapterFactory(VAULT_V1_ADAPTER_FACTORY_ADDRESS);

        // deploy new vault with broadcaster as initial owner
        deployment.vault = IVaultV2(vaultFactory.createVaultV2(broadcaster, params.asset, SALT));

        // deploy adapter
        deployment.adapter =
            IAdapter(adapterFactory.createMorphoVaultV1Adapter(address(deployment.vault), params.initial_vault));

        // deploy gate
        deployment.gate = new Gate(params.curator);

        // set name and symbol
        deployment.vault.setName(params.name);
        deployment.vault.setSymbol(params.symbol);

        // transfer curator permissions to broadcaster
        deployment.vault.setCurator(broadcaster);

        // add adapter
        deployment.vault.submit(abi.encodeCall(IVaultV2.addAdapter, address(deployment.adapter)));
        deployment.vault.addAdapter(address(deployment.adapter));

        // set broadcaster as allocator
        deployment.vault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (broadcaster, true)));
        deployment.vault.setIsAllocator(broadcaster, true);

        // set caps
        bytes memory adapterId = abi.encode("this", deployment.adapter);
        deployment.vault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (adapterId, params.initial_absolute_cap)));
        deployment.vault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (adapterId, params.initial_relative_cap)));
        deployment.vault.increaseAbsoluteCap(adapterId, params.initial_absolute_cap);
        deployment.vault.increaseRelativeCap(adapterId, params.initial_relative_cap);

        // set max rate
        deployment.vault.submit(abi.encodeCall(IVaultV2.setMaxRate, (params.max_rate)));
        deployment.vault.setMaxRate(params.max_rate);

        // enable liquidity adapter
        deployment.vault.setLiquidityAdapterAndData(address(deployment.adapter), new bytes(0));

        // perform dead deposit
        IERC20(deployment.vault.asset()).approve(address(deployment.vault), params.dead_deposit);
        deployment.vault.deposit(params.dead_deposit, address(0xdead)); // Dead address for burned shares

        // set sentinel and allocator
        deployment.vault.submit(abi.encodeCall(IVaultV2.setIsSentinel, (params.sentinel, true)));
        deployment.vault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (params.allocator, true)));
        deployment.vault.setIsSentinel(params.sentinel, true);
        deployment.vault.setIsAllocator(params.allocator, true);

        // set gate
        deployment.vault.submit(abi.encodeCall(IVaultV2.setSendAssetsGate, (address(deployment.gate))));
        deployment.vault.submit(abi.encodeCall(IVaultV2.setReceiveAssetsGate, (address(deployment.gate))));
        deployment.vault.submit(abi.encodeCall(IVaultV2.setSendSharesGate, (address(deployment.gate))));
        deployment.vault.submit(abi.encodeCall(IVaultV2.setReceiveSharesGate, (address(deployment.gate))));
        deployment.vault.setSendAssetsGate(address(deployment.gate));
        deployment.vault.setReceiveAssetsGate(address(deployment.gate));
        deployment.vault.setSendSharesGate(address(deployment.gate));
        deployment.vault.setReceiveSharesGate(address(deployment.gate));

        // SET FINAL ROLES
        deployment.vault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (broadcaster, false)));
        deployment.vault.setIsAllocator(broadcaster, false);

        // set timelock
        configureTimelock(deployment.vault, params.timelock_duration);

        deployment.vault.setCurator(params.curator);
        deployment.vault.setOwner(params.owner);

        // Serialize json and print contracts
        serialize(deployment);
        printContracts(deployment);
        printLogo();
    }

    /// @notice Configure timelock settings for critical functions
    function configureTimelock(IVaultV2 vault, uint256 timelock_duration) internal {
        // Define function selectors that should be timelocked
        bytes4[] memory timelockedSelectors = new bytes4[](10);
        timelockedSelectors[0] = IVaultV2.setReceiveSharesGate.selector;
        timelockedSelectors[1] = IVaultV2.setSendSharesGate.selector;
        timelockedSelectors[2] = IVaultV2.setReceiveAssetsGate.selector;
        timelockedSelectors[3] = IVaultV2.addAdapter.selector;
        timelockedSelectors[4] = IVaultV2.increaseAbsoluteCap.selector;
        timelockedSelectors[5] = IVaultV2.increaseRelativeCap.selector;
        timelockedSelectors[6] = IVaultV2.setForceDeallocatePenalty.selector;
        timelockedSelectors[7] = IVaultV2.abdicate.selector;
        timelockedSelectors[8] = IVaultV2.removeAdapter.selector;
        timelockedSelectors[9] = IVaultV2.increaseTimelock.selector;

        // Submit timelock increases for all selectors
        for (uint256 i = 0; i < timelockedSelectors.length; i++) {
            vault.submit(abi.encodeCall(vault.increaseTimelock, (timelockedSelectors[i], timelock_duration)));
        }
        console2.log("Timelock increases submitted for", timelockedSelectors.length, "functions");

        // Execute timelock increases for all selectors
        for (uint256 i = 0; i < timelockedSelectors.length; i++) {
            vault.increaseTimelock(timelockedSelectors[i], timelock_duration);
        }
        console2.log("Timelock increases executed for", timelockedSelectors.length, "functions");
    }

    // Given a deployment result, serialize the JSON
    function serialize(DeploymentResult memory deployment) internal returns (string memory obj) {
        console2.log("\nSerializing json...\n");
        // objects
        obj = "{}";
        string memory rolesObj = "{}";
        string memory contractsObj = "{}";
        string memory configObj = "{}";

        // keys
        string memory key = "vault";
        string memory rolesKey = "roles";
        string memory contractsKey = "contracts";
        string memory configKey = "config";

        // serialize config
        configObj = vm.serializeString(configKey, "asset", "usdc");
        configObj = vm.serializeUint(configKey, "deployment_block", block.number);

        // serialize contracts
        contractsObj = vm.serializeAddress(contractsKey, "vault", address(deployment.vault));
        contractsObj = vm.serializeAddress(contractsKey, "adapter", address(deployment.adapter));
        contractsObj = vm.serializeAddress(contractsKey, "gate", address(deployment.gate));

        // serialize accounts
        rolesObj = vm.serializeAddress(rolesKey, "curator", params.curator);
        rolesObj = vm.serializeAddress(rolesKey, "allocator", params.allocator);
        rolesObj = vm.serializeAddress(rolesKey, "sentinel", params.sentinel);
        rolesObj = vm.serializeAddress(rolesKey, "owner", params.owner);

        // serialize json file from objects
        obj = vm.serializeString(key, configKey, configObj);
        obj = vm.serializeString(key, contractsKey, contractsObj);
        obj = vm.serializeString(key, rolesKey, rolesObj);

        // save to file
        string memory path = string.concat("broadcast/DeployVault.s.sol/", vm.toString(block.chainid));
        vm.createDir(path, true);
        vm.writeJson(obj, string.concat(path, "/vault.json"));
    }

    function printContracts(DeploymentResult memory deployment) internal pure {
        console2.log("\n========================= Contracts =========================\n");
        console2.log("Vault: ", address(deployment.vault));
        console2.log("Adapter: ", address(deployment.adapter));
        console2.log("Gate: ", address(deployment.gate));
        console2.log("\n=============================================================\n");
    }

    // mark this as a test contract
    function test() public {}
}
