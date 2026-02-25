// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Config} from "forge-std/Config.sol";
import {Deploy} from "script/Deploy.s.sol";
import {ForkBaseTest} from "test/fork/ForkBaseTest.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

// test deployment script
// this requires .env is set up correctly
contract DeployForkTest is ForkBaseTest, Config {
    using SafeERC20 for IERC20;

    Deploy.DeploymentResult deployment;
    Deploy.DeploymentParameters params;
    Deploy.RolesParameters roles;

    function setUp() public override {
        // set a fork block where collateral vault exists
        forkBlock = 24399000;
        super.setUp();
        Deploy deployer = new Deploy();
        deployment = deployer.run();
    }

    function test_fork_Deploy() public {
        _loadConfig("./config/mainnet.toml", false);

        // roles
        roles.admin_role = 0xE6Eb534f33A635e8d867414Af32F766D221F30d1;
        roles.cap_adjuster_role = 0x48Fa008bD2660974d55Ee9b7A9ECA1cE61347614;
        roles.curator_role = 0xD1a89086428E2b208414201712cbE0952DabEA03;
        roles.custodian_keeper_role = 0xD1a89086428E2b208414201712cbE0952DabEA03;
        roles.default_admin_role = 0x698c6d3726846C4AD4Dc9331862b92Cd80D2fb99;
        roles.gatekeeper_role = 0x44C24D0937A829B3057be462b0e069516f1D9D45;
        roles.minter_role = 0xCa2D7CfAa96290171c98e112c73fC87c2AE2fe9B;
        roles.multicaller_role = 0xCa2D7CfAa96290171c98e112c73fC87c2AE2fe9B;
        roles.rebalancer_role = 0xD1a89086428E2b208414201712cbE0952DabEA03;
        roles.restricter_role = 0xE6Eb534f33A635e8d867414Af32F766D221F30d1;
        roles.revenue_keeper_role = 0xD1a89086428E2b208414201712cbE0952DabEA03;
        roles.rewarder_role = 0x9cC553d9F9e9690C0bc97bC2E1d10696d3862aC8;
        roles.signer_manager_role = 0x48Fa008bD2660974d55Ee9b7A9ECA1cE61347614;

        // address parameters
        params.collateral = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        params.custodian = 0x1f766513abc0DD46b26590Ea83A6b20377460a18;
        params.multisig = 0x9cC553d9F9e9690C0bc97bC2E1d10696d3862aC8;
        params.vault = 0x7290245b3e564f0Ae2dA5af0690eF4842CF13c75;

        // uint parameters
        params.cooldown_period = 604_800;
        /* params.min_swap_price = 0; */
        params.oracle_tolerance = 50_000000000000000;
        params.ratio = 170_000000000000000;
        params.rebalance_cap = 100_000_000_000000;
        params.swap_cap = 0;
        params.vesting_period = 259_200;

        // check default admin roles
        assertEq(deployment.controller.hasRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role), true);
        assertEq(deployment.manager.hasRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role), true);
        assertEq(deployment.asset.pendingOwner(), roles.default_admin_role);
        assertEq(deployment.multicall.hasRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role), true);
        assertEq(deployment.staking.hasRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role), true);
        assertEq(deployment.revenue_module.hasRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role), true);
        assertEq(deployment.custodian_module.hasRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role), true);

        // check controller config
        assertEq(deployment.controller.hasRole(MINTER_ROLE, roles.minter_role), true);
        assertEq(deployment.controller.hasRole(GATEKEEPER_ROLE, roles.gatekeeper_role), true);
        assertEq(deployment.controller.hasRole(ADMIN_ROLE, roles.admin_role), true);
        assertEq(deployment.controller.hasRole(SIGNER_MANAGER_ROLE, roles.signer_manager_role), true);
        assertEq(deployment.controller.hasRole(RESTRICTER_ROLE, roles.restricter_role), true);
        assertEq(deployment.controller.ratio(), params.ratio);
        assertEq(deployment.controller.custodian(), address(deployment.custodian_module));
        assertEq(deployment.controller.manager(), address(deployment.manager));
        (address adapter, uint96 tolerance) = deployment.controller.oracle();
        assertEq(adapter, address(deployment.oracle_adapter));
        assertEq(tolerance, params.oracle_tolerance);

        // check manager config
        assertEq(deployment.manager.revenueModule(), address(deployment.revenue_module));
        assertEq(deployment.manager.hasRole(ADMIN_ROLE, roles.admin_role), true);
        assertEq(deployment.manager.hasRole(CURATOR_ROLE, roles.curator_role), true);
        assertEq(deployment.manager.hasRole(REBALANCER_ROLE, roles.rebalancer_role), true);
        assertEq(deployment.manager.hasRole(GATEKEEPER_ROLE, roles.gatekeeper_role), true);
        assertEq(deployment.manager.hasRole(CAP_ADJUSTER_ROLE, roles.cap_adjuster_role), true);
        assertEq(deployment.manager.controller(), address(deployment.controller));
        assertEq(deployment.manager.swapModule(), address(deployment.swap_module));
        assertEq(deployment.manager.revenueModule(), address(deployment.revenue_module));
        assertEq(address(deployment.manager.vaults(params.collateral)), params.vault);
        assertEq(deployment.manager.rebalanceCap(params.collateral), params.rebalance_cap);
        assertEq(deployment.manager.swapCap(params.collateral), params.swap_cap);

        // check staking config
        assertEq(deployment.staking.hasRole(REWARDER_ROLE, roles.rewarder_role), true);
        assertEq(deployment.staking.hasRole(REWARDER_ROLE, address(deployment.revenue_module)), true);
        assertEq(deployment.staking.hasRole(ADMIN_ROLE, roles.admin_role), true);
        assertEq(deployment.staking.hasRole(RESTRICTER_ROLE, roles.restricter_role), true);

        // check multicall config
        assertEq(deployment.multicall.hasRole(MULTICALLER_ROLE, roles.multicaller_role), true);

        // check revenue module config
        assertEq(deployment.revenue_module.hasRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role), true);
        assertEq(deployment.revenue_module.hasRole(REVENUE_KEEPER_ROLE, roles.revenue_keeper_role), true);
        assertEq(deployment.revenue_module.hasRole(ADMIN_ROLE, roles.admin_role), true);
        assertEq(deployment.revenue_module.staking(), address(deployment.staking));
        assertEq(deployment.revenue_module.asset(), address(deployment.asset));
        assertEq(deployment.revenue_module.manager(), address(deployment.manager));
        assertEq(deployment.revenue_module.controller(), address(deployment.controller));
        assertEq(deployment.revenue_module.multisig(), params.multisig);

        // check custodian module config
        assertEq(deployment.custodian_module.hasRole(CUSTODIAN_KEEPER_ROLE, roles.custodian_keeper_role), true);
        assertEq(deployment.custodian_module.custodians(params.custodian), true);

        // check manager is correctly configured
        assertEq(deployment.manager.controller(), address(deployment.controller));
        assertEq(deployment.manager.swapModule(), address(deployment.swap_module));

        // check swap module is correctly configured
        assertEq(deployment.swap_module.manager(), address(deployment.manager));
        assertEq(deployment.swap_module.router(), address(deployment.one_inch_router));
        assertEq(deployment.swap_module.admin(), address(roles.admin_role));

        // check staking is correctly configured
        (uint128 length,,) = deployment.staking.vesting();
        assertEq(length, params.vesting_period);
        assertEq(deployment.staking.cooldownPeriod(), params.cooldown_period);

        // check revenue module is correctly configured
        assertEq(deployment.revenue_module.manager(), address(deployment.manager));
        assertEq(deployment.revenue_module.staking(), address(deployment.staking));
        assertEq(deployment.revenue_module.asset(), address(deployment.asset));
        assertEq(deployment.revenue_module.controller(), address(deployment.controller));

        // ensure roles are renounced by deployer
        assertEq(deployment.asset.pendingOwner(), roles.default_admin_role);
        assertFalse(deployment.controller.hasRole(DEFAULT_ADMIN_ROLE, broadcaster));
        assertFalse(deployment.manager.hasRole(DEFAULT_ADMIN_ROLE, broadcaster));
        assertFalse(deployment.multicall.hasRole(DEFAULT_ADMIN_ROLE, broadcaster));
        assertFalse(deployment.staking.hasRole(DEFAULT_ADMIN_ROLE, broadcaster));
        assertFalse(deployment.revenue_module.hasRole(DEFAULT_ADMIN_ROLE, broadcaster));
        assertFalse(deployment.manager.hasRole(ADMIN_ROLE, broadcaster));
        assertFalse(deployment.manager.hasRole(CURATOR_ROLE, broadcaster));
        assertFalse(deployment.manager.hasRole(REBALANCER_ROLE, broadcaster));
        assertFalse(deployment.manager.hasRole(GATEKEEPER_ROLE, broadcaster));
        assertFalse(deployment.manager.hasRole(CAP_ADJUSTER_ROLE, broadcaster));
        assertFalse(deployment.staking.hasRole(REWARDER_ROLE, broadcaster));
        assertFalse(deployment.staking.hasRole(ADMIN_ROLE, broadcaster));
        assertFalse(deployment.multicall.hasRole(MULTICALLER_ROLE, broadcaster));
        assertFalse(deployment.revenue_module.hasRole(REVENUE_KEEPER_ROLE, broadcaster));
        assertFalse(deployment.custodian_module.hasRole(DEFAULT_ADMIN_ROLE, broadcaster));
        assertFalse(deployment.custodian_module.hasRole(CUSTODIAN_KEEPER_ROLE, broadcaster));
    }
}
