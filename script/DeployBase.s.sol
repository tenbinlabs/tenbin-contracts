// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseScript} from "./Base.s.sol";
import {Config} from "forge-std/Config.sol";
import {console2} from "forge-std/console2.sol";

/// @notice Base deploy script from which other scripts inherit
contract DeployBase is BaseScript, Config {
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

    /// @notice Config variables set during deployment
    struct DeploymentParameters {
        address multisig;
        address collateral;
        address custodian;
        address one_inch_router;
        address oracle;
        address signer;
        address vault;
        string asset_name;
        string asset_symbol;
        string staked_asset_name;
        string staked_asset_symbol;
        uint256 cooldown_period;
        uint256 min_swap_price;
        uint256 oracle_tolerance;
        uint256 ratio;
        uint256 rebalance_cap;
        uint256 swap_cap;
        uint256 vesting_period;
    }

    /// @notice Roles loaded from config file
    RolesParameters internal roles;
    /// @notice Parameters loaded from config file
    DeploymentParameters internal params;

    function loadConfig(string memory configDir) internal virtual {
        _loadConfig(configDir, false);

        // load roles
        roles.admin_role = config.get("admin_role").toAddress();
        roles.cap_adjuster_role = config.get("cap_adjuster_role").toAddress();
        roles.curator_role = config.get("curator_role").toAddress();
        roles.custodian_keeper_role = config.get("custodian_keeper_role").toAddress();
        roles.default_admin_role = config.get("default_admin_role").toAddress();
        roles.gatekeeper_role = config.get("gatekeeper_role").toAddress();
        roles.minter_role = config.get("minter_role").toAddress();
        roles.multicaller_role = config.get("multicaller_role").toAddress();
        roles.rebalancer_role = config.get("rebalancer_role").toAddress();
        roles.restricter_role = config.get("restricter_role").toAddress();
        roles.rewarder_role = config.get("rewarder_role").toAddress();
        roles.revenue_keeper_role = config.get("revenue_keeper_role").toAddress();
        roles.signer_manager_role = config.get("signer_manager_role").toAddress();

        // load parameters
        params.custodian = config.get("custodian").toAddress();
        params.multisig = config.get("multisig").toAddress();

        // load string
        params.asset_name = config.get("asset_name").toString();
        params.asset_symbol = config.get("asset_symbol").toString();

        if (block.chainid == 31337 || block.chainid == 11155111) {
            params.staked_asset_name = string.concat("Staked ", params.asset_name);
            params.staked_asset_symbol = string.concat("s", params.asset_symbol);
            params.signer = config.get("signer").toAddress();
        } else {
            params.collateral = config.get("collateral").toAddress();
            params.vault = config.get("vault").toAddress();
            params.oracle = config.get("oracle").toAddress();

            // load string
            params.staked_asset_name = config.get("staked_asset_name").toString();
            params.staked_asset_symbol = config.get("staked_asset_symbol").toString();

            // load uint
            params.cooldown_period = config.get("cooldown_period").toUint256();
            params.min_swap_price = config.get("min_swap_price").toUint256();
            params.oracle_tolerance = config.get("oracle_tolerance").toUint256();
            params.ratio = config.get("ratio").toUint256();
            params.rebalance_cap = config.get("rebalance_cap").toUint256();
            params.swap_cap = config.get("swap_cap").toUint256();
            params.vesting_period = config.get("vesting_period").toUint256();
        }
    }

    function printAccounts() internal view {
        console2.log("\n========================= Accounts ==========================\n");
        console2.log("broadcaster address: ", broadcaster);
        console2.log("minter address: ", roles.minter_role);
        if (block.chainid == 31337 || block.chainid == 11155111) console2.log("signer address: ", params.signer);
    }

    /* ------------------------------------ SERIALIZATION HELPERS ------------------------------------------ */

    function getGlobalObject() internal returns (string memory globalObj) {
        string memory globalKey = "global";
        globalObj = "{}";

        globalObj = vm.serializeAddress(globalKey, "admin_multisig", roles.admin_role);
        globalObj = vm.serializeAddress(globalKey, "dev_multisig", roles.cap_adjuster_role);
        globalObj = vm.serializeAddress(globalKey, "owner_multisig", roles.default_admin_role);
        globalObj = vm.serializeAddress(globalKey, "tenbin_multisig", params.multisig);
    }

    function getRolesObject(address multicall, address revenueModule) internal returns (string memory rolesObj) {
        string memory rolesKey = "roles";
        rolesObj = "{}";

        rolesObj = vm.serializeAddress(rolesKey, "admin_role", arr(roles.admin_role));
        rolesObj = vm.serializeAddress(rolesKey, "cap_adjuster_role", arr(roles.cap_adjuster_role));
        rolesObj = vm.serializeAddress(rolesKey, "curator_role", arr(roles.curator_role));
        rolesObj = vm.serializeAddress(rolesKey, "custodian_keeper_role", arr(roles.custodian_keeper_role));
        rolesObj = vm.serializeAddress(rolesKey, "gatekeeper_role", arr(roles.gatekeeper_role));
        rolesObj = vm.serializeAddress(rolesKey, "minter_role", arr(roles.minter_role, multicall));
        rolesObj = vm.serializeAddress(rolesKey, "multicaller_role", arr(roles.multicaller_role));
        rolesObj = vm.serializeAddress(rolesKey, "default_admin_role", arr(roles.default_admin_role));
        rolesObj = vm.serializeAddress(rolesKey, "rebalancer_role", arr(roles.rebalancer_role));
        rolesObj = vm.serializeAddress(rolesKey, "restricter_role", arr(roles.restricter_role));
        rolesObj = vm.serializeAddress(rolesKey, "revenue_keeper_role", arr(roles.revenue_keeper_role));
        rolesObj = vm.serializeAddress(rolesKey, "rewarder_role", arr(roles.rewarder_role, revenueModule));
        rolesObj = vm.serializeAddress(rolesKey, "signer_manager_role", arr(roles.signer_manager_role));
    }

    // mark this as a test contract
    function test() public {}
}
