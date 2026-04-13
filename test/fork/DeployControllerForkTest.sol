// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Config} from "forge-std/Config.sol";
import {DeployController} from "../../script/DeployController.s.sol";
import {ForkBaseTest} from "./ForkBaseTest.sol";
import {stdToml} from "forge-std/StdToml.sol";

// test deployment script
// this requires .env is set up correctly
contract DeployControllerForkTest is ForkBaseTest, Config {
    using stdToml for string;

    address constant ASSET_TOKEN_ADDRESS = 0x6a547b25534234bb79CE6961a23Db13DE154b6F4;
    address constant COLLATERAL_MANAGER_ADDRESS = 0x42F3F01D45E67294e20cE98AcFDC24dD7EA75dEa;
    address constant CUSTODIAN_MODULE_ADDRESS = 0x97e1C8dc9a3CcA064fAA8318f9b5C7AdB26b0e89;
    address constant MULTICALL_ADDRESS = 0xdA8B85Cd62CDB3C104c80b479f9094e07EBcF7e8;
    address constant MULTISIG_ADDRESS = 0x9cC553d9F9e9690C0bc97bC2E1d10696d3862aC8;
    address constant ORACLE_ADAPTER_ADDRESS = 0xA944664E98FF8CD1743149A62Da3F3F23297E7C1;
    address constant STAKED_ASSET_ADDRESS = 0xdE80e9EC32249d4c7dBA7997fD6D6C03fb27EBf4;

    DeployController.DeploymentParameters params;
    DeployController.RolesParameters roles;
    DeployController.DeploymentResult deployment;
    string constant CONFIG_DIR = "./config/mainnet/tgld/tgld.toml";

    function setUp() public override {
        // set a fork block where collateral vault exists
        forkBlock = 24399000;
        super.setUp();
        DeployController deployer = new DeployController();
        deployment = deployer.run(CONFIG_DIR);
    }

    function test_fork_DeployController() public {
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
        assertEq(deployment.revenue_module.hasRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role), true);

        // check controller config
        assertEq(deployment.controller.hasRole(MINTER_ROLE, roles.minter_role), true);
        assertEq(deployment.controller.hasRole(GATEKEEPER_ROLE, roles.gatekeeper_role), true);
        assertEq(deployment.controller.hasRole(ADMIN_ROLE, roles.admin_role), true);
        assertEq(deployment.controller.hasRole(SIGNER_MANAGER_ROLE, roles.signer_manager_role), true);
        assertEq(deployment.controller.hasRole(RESTRICTER_ROLE, roles.restricter_role), true);
        assertEq(deployment.controller.ratio(), params.ratio);
        assertEq(deployment.controller.custodian(), address(deployment.controller.custodian()));
        assertEq(deployment.controller.manager(), address(deployment.controller.manager()));
        (address adapter, uint96 tolerance) = deployment.controller.oracle();
        assertEq(adapter, ORACLE_ADAPTER_ADDRESS);
        assertEq(tolerance, params.oracle_tolerance);

        // check revenue module is correctly configured
        assertEq(deployment.revenue_module.manager(), COLLATERAL_MANAGER_ADDRESS);
        assertEq(deployment.revenue_module.staking(), STAKED_ASSET_ADDRESS);
        assertEq(deployment.revenue_module.asset(), ASSET_TOKEN_ADDRESS);
        assertEq(deployment.revenue_module.controller(), address(deployment.controller));
        assertEq(deployment.revenue_module.multisig(), MULTISIG_ADDRESS);

        // ensure roles are renounced by deployer
        assertFalse(deployment.controller.hasRole(DEFAULT_ADMIN_ROLE, deployment.broadcaster));
        assertFalse(deployment.controller.hasRole(ADMIN_ROLE, deployment.broadcaster));
        assertFalse(deployment.revenue_module.hasRole(DEFAULT_ADMIN_ROLE, deployment.broadcaster));
    }
}
