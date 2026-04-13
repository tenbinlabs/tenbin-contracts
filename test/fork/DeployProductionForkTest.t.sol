// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Config} from "forge-std/Config.sol";
import {DeployProduction} from "../../script/DeployProduction.s.sol";
import {ForkBaseTest} from "./ForkBaseTest.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {stdToml} from "forge-std/StdToml.sol";

// test deployment script
// this requires .env is set up correctly
contract DeployProductionForkTest is ForkBaseTest, Config {
    using SafeERC20 for IERC20;
    using stdToml for string;

    DeployProduction.DeploymentResult deployment;
    DeployProduction.DeploymentParameters params;
    DeployProduction.RolesParameters roles;
    string constant CONFIG_DIR = "./config/mainnet/tgld/tgld.toml";

    function setUp() public override {
        // set a fork block where collateral vault exists
        forkBlock = 24399000;
        super.setUp();
    }

    function test_fork_Deploy() public {
        DeployProduction deployer = new DeployProduction();
        deployment = deployer.run(CONFIG_DIR);
        sanityChecks();
    }

    function test_fork_Default_Deploy() public {
        DeployProduction deployer = new DeployProduction();
        deployment = deployer.run("");
        sanityChecks();
    }

    function sanityChecks() internal {
        _loadConfig(CONFIG_DIR, false);
        // forge-lint: disable-next-line(unsafe-cheatcode)
        string memory toml = vm.readFile(CONFIG_DIR);

        // roles
        roles.admin_role = vm.parseTomlAddress(toml, ".mainnet.address.admin_role");
        roles.cap_adjuster_role = vm.parseTomlAddress(toml, ".mainnet.address.cap_adjuster_role");
        roles.curator_role = vm.parseTomlAddress(toml, ".mainnet.address.curator_role");
        roles.custodian_keeper_role = vm.parseTomlAddress(toml, ".mainnet.address.custodian_keeper_role");
        roles.default_admin_role = vm.parseTomlAddress(toml, ".mainnet.address.default_admin_role");
        roles.gatekeeper_role = vm.parseTomlAddress(toml, ".mainnet.address.gatekeeper_role");
        roles.minter_role = vm.parseTomlAddress(toml, ".mainnet.address.minter_role");
        roles.multicaller_role = vm.parseTomlAddress(toml, ".mainnet.address.multicaller_role");
        roles.rebalancer_role = vm.parseTomlAddress(toml, ".mainnet.address.rebalancer_role");
        roles.restricter_role = vm.parseTomlAddress(toml, ".mainnet.address.restricter_role");
        roles.rewarder_role = vm.parseTomlAddress(toml, ".mainnet.address.rewarder_role");
        roles.revenue_keeper_role = vm.parseTomlAddress(toml, ".mainnet.address.revenue_keeper_role");
        roles.signer_manager_role = vm.parseTomlAddress(toml, ".mainnet.address.signer_manager_role");

        // address parameters
        params.collateral = vm.parseTomlAddress(toml, ".mainnet.address.collateral");
        params.custodian = vm.parseTomlAddress(toml, ".mainnet.address.custodian");
        params.multisig = vm.parseTomlAddress(toml, ".mainnet.address.multisig");
        params.vault = vm.parseTomlAddress(toml, ".mainnet.address.vault");

        // uint parameters
        params.cooldown_period = vm.parseTomlUint(toml, ".mainnet.uint.cooldown_period");
        params.min_swap_price = vm.parseTomlUint(toml, ".mainnet.uint.min_swap_price");
        params.oracle_tolerance = vm.parseTomlUint(toml, ".mainnet.uint.oracle_tolerance");
        params.ratio = vm.parseTomlUint(toml, ".mainnet.uint.ratio");
        params.rebalance_cap = vm.parseTomlUint(toml, ".mainnet.uint.rebalance_cap");
        params.swap_cap = vm.parseTomlUint(toml, ".mainnet.uint.swap_cap");
        params.vesting_period = vm.parseTomlUint(toml, ".mainnet.uint.vesting_period");

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
        assertEq(deployment.revenue_module.multisig(), address(params.multisig));

        // ensure roles are renounced by deployer
        assertEq(deployment.asset.pendingOwner(), roles.default_admin_role);
        assertFalse(deployment.controller.hasRole(DEFAULT_ADMIN_ROLE, deployment.broadcaster));
        assertFalse(deployment.manager.hasRole(DEFAULT_ADMIN_ROLE, deployment.broadcaster));
        assertFalse(deployment.multicall.hasRole(DEFAULT_ADMIN_ROLE, deployment.broadcaster));
        assertFalse(deployment.staking.hasRole(DEFAULT_ADMIN_ROLE, deployment.broadcaster));
        assertFalse(deployment.revenue_module.hasRole(DEFAULT_ADMIN_ROLE, deployment.broadcaster));
        assertFalse(deployment.manager.hasRole(ADMIN_ROLE, deployment.broadcaster));
        assertFalse(deployment.manager.hasRole(CURATOR_ROLE, deployment.broadcaster));
        assertFalse(deployment.manager.hasRole(REBALANCER_ROLE, deployment.broadcaster));
        assertFalse(deployment.manager.hasRole(GATEKEEPER_ROLE, deployment.broadcaster));
        assertFalse(deployment.manager.hasRole(CAP_ADJUSTER_ROLE, deployment.broadcaster));
        assertFalse(deployment.staking.hasRole(REWARDER_ROLE, deployment.broadcaster));
        assertFalse(deployment.staking.hasRole(ADMIN_ROLE, deployment.broadcaster));
        assertFalse(deployment.multicall.hasRole(MULTICALLER_ROLE, deployment.broadcaster));
        assertFalse(deployment.revenue_module.hasRole(REVENUE_KEEPER_ROLE, deployment.broadcaster));
        assertFalse(deployment.custodian_module.hasRole(DEFAULT_ADMIN_ROLE, deployment.broadcaster));
        assertFalse(deployment.custodian_module.hasRole(CUSTODIAN_KEEPER_ROLE, deployment.broadcaster));
    }
}
