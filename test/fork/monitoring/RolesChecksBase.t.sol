// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {MonitorBase} from "./MonitorBase.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";

contract RolesChecksBase is MonitorBase {
    function test_AssetTokenOwner() public view {
        assertEq(Ownable(contracts.asset_token).owner(), global.owner_multisig);
    }

    function test_ManagerRoles() public view {
        assertTrue(_hasRole(contracts.collateral_manager, DEFAULT_ADMIN_ROLE, roles.default_admin_role));
        assertTrue(_hasRole(contracts.collateral_manager, ADMIN_ROLE, roles.admin_role));
        assertTrue(_hasRole(contracts.collateral_manager, CURATOR_ROLE, roles.curator_role));
        assertTrue(_hasRole(contracts.collateral_manager, REBALANCER_ROLE, roles.rebalancer_role));
        assertTrue(_hasRole(contracts.collateral_manager, GATEKEEPER_ROLE, roles.gatekeeper_role));
        assertTrue(_hasRole(contracts.collateral_manager, CAP_ADJUSTER_ROLE, roles.cap_adjuster_role));
    }

    function test_ControllerRoles() public view {
        assertTrue(_hasRole(contracts.controller, DEFAULT_ADMIN_ROLE, roles.default_admin_role));
        assertTrue(_hasRole(contracts.controller, MINTER_ROLE, roles.minter_role));
        assertTrue(_hasRole(contracts.controller, GATEKEEPER_ROLE, roles.gatekeeper_role));
        assertTrue(_hasRole(contracts.controller, ADMIN_ROLE, roles.admin_role));
        assertTrue(_hasRole(contracts.controller, SIGNER_MANAGER_ROLE, roles.signer_manager_role));
        assertTrue(_hasRole(contracts.controller, RESTRICTER_ROLE, roles.restricter_role));
    }

    function test_CustodianRoles() public view {
        assertTrue(_hasRole(contracts.custodian_module, DEFAULT_ADMIN_ROLE, roles.default_admin_role));
        assertTrue(_hasRole(contracts.custodian_module, CUSTODIAN_KEEPER_ROLE, roles.custodian_keeper_role));
    }

    function test_MulticallRoles() public view {
        assertTrue(_hasRole(contracts.multicall, DEFAULT_ADMIN_ROLE, roles.default_admin_role));
        assertTrue(_hasRole(contracts.multicall, MULTICALLER_ROLE, roles.multicaller_role));
    }

    function test_revenue_moduleRoles() public view {
        assertTrue(_hasRole(contracts.revenue_module, DEFAULT_ADMIN_ROLE, roles.default_admin_role));
        assertTrue(_hasRole(contracts.revenue_module, ADMIN_ROLE, roles.admin_role));
        assertTrue(_hasRole(contracts.revenue_module, REVENUE_KEEPER_ROLE, roles.revenue_keeper_role));
    }

    function test_StakedAssetRoles() public view {
        assertTrue(_hasRole(contracts.staked_asset, DEFAULT_ADMIN_ROLE, roles.default_admin_role));
        assertTrue(_hasRole(contracts.staked_asset, REWARDER_ROLE, roles.rewarder_role));
        assertTrue(AccessControl(contracts.staked_asset).hasRole(REWARDER_ROLE, contracts.revenue_module));
        assertTrue(_hasRole(contracts.staked_asset, ADMIN_ROLE, roles.admin_role));
        assertTrue(_hasRole(contracts.staked_asset, RESTRICTER_ROLE, roles.restricter_role));
        assertTrue(AccessControl(contracts.staked_asset).hasRole(INSTANT_UNSTAKER_ROLE, contracts.controller));
        assertTrue(_hasRole(contracts.staked_asset, CAP_ADJUSTER_ROLE, roles.cap_adjuster_role));
    }
}
