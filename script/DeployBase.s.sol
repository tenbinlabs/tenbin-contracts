// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseScript} from "./Base.s.sol";
import {console2} from "forge-std/console2.sol";
import {StdConfig} from "forge-std/StdConfig.sol";

/// @notice Base deploy script loading configuration separately for core, roles, and vault
contract DeployBase is BaseScript {
    /// @notice Roles set during deployment
    struct RolesParameters {
        address admin_role;
        address cap_adjuster_role;
        address curator_role;
        address custodian_keeper_role;
        address default_admin_role;
        address gatekeeper_role;
        address minter_role;
        address multicaller_role;
        address rebalancer_role;
        address restricter_role;
        address rewarder_role;
        address revenue_keeper_role;
        address signer_manager_role;
    }

    /// @notice Core protocol parameters loaded from the asset config file
    struct CoreParameters {
        address multisig;
        address collateral;
        address custodian;
        address one_inch_router;
        address oracle;
        address signer;
        string asset_name;
        string asset_symbol;
        string custodian_name;
        string staked_asset_name;
        string staked_asset_symbol;
        uint256 cooldown_period;
        uint256 oracle_tolerance;
        uint256 ratio;
        uint256 rebalance_cap;
        uint256 instant_unstake_cap;
        uint128 vesting_period;
        uint128 mint_limit;
        uint128 redeem_limit;
    }

    /// @notice Morpho vault parameters loaded from the vault config file
    struct VaultParameters {
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

    /// @notice Config file handle for the asset (core parameters and roles)
    StdConfig internal assetConfig;
    /// @notice Config file handle for the vault
    StdConfig internal vaultConfig;

    /// @notice Roles loaded from the asset config file
    RolesParameters internal roles;
    /// @notice Core parameters loaded from the asset config file
    CoreParameters internal coreParams;
    /// @notice Vault parameters loaded from the vault config file
    VaultParameters internal vaultParams;

    /// @notice Load core protocol parameters from the asset config toml file
    function loadCoreConfig(string memory configDir) internal {
        assetConfig = new StdConfig(configDir, false);
        vm.makePersistent(address(assetConfig));

        // load addresses
        coreParams.multisig = assetConfig.get("multisig").toAddress();
        coreParams.collateral = assetConfig.get("collateral").toAddress();
        coreParams.custodian = assetConfig.get("custodian").toAddress();
        coreParams.one_inch_router = assetConfig.get("one_inch_router").toAddress();
        coreParams.oracle = assetConfig.get("oracle").toAddress();
        if (block.chainid == 11155111 || block.chainid == 31337) {
            coreParams.signer = assetConfig.get("signer").toAddress();
        }

        // load strings
        coreParams.asset_name = assetConfig.get("asset_name").toString();
        coreParams.asset_symbol = assetConfig.get("asset_symbol").toString();
        coreParams.custodian_name = assetConfig.get("custodian_name").toString();
        coreParams.staked_asset_name = assetConfig.get("staked_asset_name").toString();
        coreParams.staked_asset_symbol = assetConfig.get("staked_asset_symbol").toString();

        // load uints
        coreParams.cooldown_period = assetConfig.get("cooldown_period").toUint256();
        coreParams.oracle_tolerance = assetConfig.get("oracle_tolerance").toUint256();
        coreParams.ratio = assetConfig.get("ratio").toUint256();
        coreParams.rebalance_cap = assetConfig.get("rebalance_cap").toUint256();
        coreParams.instant_unstake_cap = uint128(vm.parseUint(assetConfig.get("instant_unstake_cap").toString()));
        coreParams.vesting_period = assetConfig.get("vesting_period").toUint128();
        coreParams.mint_limit = uint128(vm.parseUint(assetConfig.get("mint_limit").toString()));
        coreParams.redeem_limit = uint128(vm.parseUint(assetConfig.get("redeem_limit").toString()));
    }

    /// @notice Load roles from the asset config toml file; requires loadCoreConfig first
    function loadRolesConfig() internal {
        require(address(assetConfig) != address(0), "load core config first");

        roles.admin_role = assetConfig.get("admin_role").toAddress();
        roles.cap_adjuster_role = assetConfig.get("cap_adjuster_role").toAddress();
        roles.curator_role = assetConfig.get("curator_role").toAddress();
        roles.custodian_keeper_role = assetConfig.get("custodian_keeper_role").toAddress();
        roles.default_admin_role = assetConfig.get("default_admin_role").toAddress();
        roles.gatekeeper_role = assetConfig.get("gatekeeper_role").toAddress();
        roles.minter_role = assetConfig.get("minter_role").toAddress();
        roles.multicaller_role = assetConfig.get("multicaller_role").toAddress();
        roles.rebalancer_role = assetConfig.get("rebalancer_role").toAddress();
        roles.restricter_role = assetConfig.get("restricter_role").toAddress();
        roles.rewarder_role = assetConfig.get("rewarder_role").toAddress();
        roles.revenue_keeper_role = assetConfig.get("revenue_keeper_role").toAddress();
        roles.signer_manager_role = assetConfig.get("signer_manager_role").toAddress();
    }

    /// @notice Load vault parameters from the vault config toml file
    function loadVaultConfig(string memory configDir) internal {
        vaultConfig = new StdConfig(configDir, false);
        vm.makePersistent(address(vaultConfig));

        // load addresses
        vaultParams.allocator = vaultConfig.get("allocator").toAddress();
        vaultParams.asset = vaultConfig.get("asset").toAddress();
        vaultParams.curator = vaultConfig.get("curator").toAddress();
        vaultParams.initial_vault = vaultConfig.get("initial_vault").toAddress();
        vaultParams.owner = vaultConfig.get("owner").toAddress();
        vaultParams.sentinel = vaultConfig.get("sentinel").toAddress();

        // load strings
        vaultParams.name = vaultConfig.get("name").toString();
        vaultParams.symbol = vaultConfig.get("symbol").toString();

        // load uints
        vaultParams.dead_deposit = vaultConfig.get("dead_deposit").toUint256();
        vaultParams.initial_absolute_cap = vaultConfig.get("initial_absolute_cap").toUint256();
        vaultParams.initial_relative_cap = vaultConfig.get("initial_relative_cap").toUint256();
        vaultParams.max_rate = vaultConfig.get("max_rate").toUint256();
        vaultParams.timelock_duration = vaultConfig.get("timelock_duration").toUint256();
    }

    function printAccounts() internal view {
        console2.log("\n========================= Accounts ==========================\n");
        console2.log("broadcaster address: ", broadcaster);
        console2.log("minter address: ", roles.minter_role);
        if (block.chainid == 31337 || block.chainid == 11155111) console2.log("signer address: ", coreParams.signer);
    }

    /* ------------------------------------ SERIALIZATION HELPERS ------------------------------------------ */

    function getGlobalObject() internal returns (string memory globalObj) {
        // single custodian entry from config
        string memory custodianObj = vm.serializeString("custodian_obj", "name", coreParams.custodian_name);
        custodianObj = vm.serializeAddress("custodian_obj", "collateral", coreParams.collateral);
        custodianObj = vm.serializeAddress("custodian_obj", "address", coreParams.custodian);

        // concatenated by hand: vm.serialize* escapes array-of-object strings instead of embedding them
        globalObj = string.concat(
            '{"admin_multisig":"',
            vm.toString(roles.admin_role),
            '","custodians":[',
            custodianObj,
            '],"dev_multisig":"',
            vm.toString(roles.cap_adjuster_role),
            '","owner_multisig":"',
            vm.toString(roles.default_admin_role),
            '","tenbin_multisig":"',
            vm.toString(coreParams.multisig),
            '"}'
        );
    }

    function getRolesObject(address multicall, address revenueModule) internal returns (string memory rolesObj) {
        string memory rolesKey = "asset_roles_obj";

        rolesObj = vm.serializeAddress(rolesKey, "admin_role", arr(roles.admin_role));
        rolesObj = vm.serializeAddress(rolesKey, "cap_adjuster_role", arr(roles.cap_adjuster_role));
        rolesObj = vm.serializeAddress(rolesKey, "curator_role", arr(roles.curator_role));
        rolesObj = vm.serializeAddress(rolesKey, "custodian_keeper_role", arr(roles.custodian_keeper_role));
        rolesObj = vm.serializeAddress(rolesKey, "gatekeeper_role", arr(roles.gatekeeper_role, roles.admin_role));
        rolesObj = vm.serializeAddress(rolesKey, "minter_role", arr(roles.minter_role, multicall));
        rolesObj = vm.serializeAddress(rolesKey, "multicaller_role", arr(roles.multicaller_role));
        rolesObj = vm.serializeAddress(rolesKey, "default_admin_role", arr(roles.default_admin_role));
        rolesObj = vm.serializeAddress(rolesKey, "rebalancer_role", arr(roles.rebalancer_role));
        rolesObj = vm.serializeAddress(rolesKey, "restricter_role", arr(roles.restricter_role));
        rolesObj = vm.serializeAddress(rolesKey, "revenue_keeper_role", arr(roles.revenue_keeper_role));
        rolesObj = vm.serializeAddress(rolesKey, "rewarder_role", arr(roles.rewarder_role, revenueModule));
        rolesObj = vm.serializeAddress(rolesKey, "signer_manager_role", arr(roles.signer_manager_role));
    }

    // helper function to compare 2 string values
    function stringMatches(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encode(a)) == keccak256(abi.encode(b));
    }

    // mark this as a test contract
    function test() public {}
}
