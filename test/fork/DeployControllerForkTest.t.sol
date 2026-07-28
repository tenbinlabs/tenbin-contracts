// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Config} from "forge-std/Config.sol";
import {DeployController} from "../../script/DeployController.s.sol";
import {DeployControllerHarness} from "../harness/DeployControllerHarness.sol";
import {ForkBaseTest} from "./ForkBaseTest.sol";
import {IOracleAdapter} from "tenbin-contracts/src/interface/IOracleAdapter.sol";
import {stdToml} from "forge-std/StdToml.sol";

// test deployment script
// this requires .env is set up correctly
contract DeployControllerForkTest is ForkBaseTest, Config {
    using stdToml for string;

    address constant ASSET_TOKEN_ADDRESS = 0x8d015aFcb6F437010653352EB1E58152c4e23734;
    address constant COLLATERAL_MANAGER_ADDRESS = 0x2a21014B89F72de3Ffa6d645F89b8Ca5A6eFfe75;
    address constant CUSTODIAN_MODULE_ADDRESS = 0x22503f510C87040C6a16F9880dd3dAacB742e192;
    address constant MULTICALL_ADDRESS = 0x80A5c0A4c09F76E67CB6397858A5a1890a4ec5a9;
    address constant MULTISIG_ADDRESS = 0x9cC553d9F9e9690C0bc97bC2E1d10696d3862aC8;
    address constant STAKED_ASSET_ADDRESS = 0x8BDf6A2DFda084bD242Cd285CF75E80de3eB00ba;
    address constant ORACLE_ADAPTER_ADDRESS = 0xb5c72C24794bbcc2cab1773b7fE05C77194F7273;

    DeployController.CoreParameters params;
    DeployController.RolesParameters roles;
    DeployController.DeploymentResult deployment;
    string constant CONFIG_DIR = "./config/mainnet/tmxn/tmxn.toml";

    function setUp() public override {
        // set a fork block where collateral vault exists
        forkBlock = 25446916;
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
        params.oracle = vm.parseTomlAddress(toml, ".mainnet.address.oracle");

        // uint parameters
        params.cooldown_period = vm.parseTomlUint(toml, ".mainnet.uint.cooldown_period");
        params.oracle_tolerance = vm.parseTomlUint(toml, ".mainnet.uint.oracle_tolerance");
        params.ratio = vm.parseTomlUint(toml, ".mainnet.uint.ratio");
        params.rebalance_cap = vm.parseTomlUint(toml, ".mainnet.uint.rebalance_cap");
        params.vesting_period = uint128(vm.parseTomlUint(toml, ".mainnet.uint.vesting_period"));
        params.mint_limit = uint128(vm.parseUint(vm.parseTomlString(toml, ".mainnet.string.mint_limit")));
        params.redeem_limit = uint128(vm.parseUint(vm.parseTomlString(toml, ".mainnet.string.redeem_limit")));
        params.instant_unstake_cap =
            uint128(vm.parseUint(vm.parseTomlString(toml, ".mainnet.string.instant_unstake_cap")));

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
        assertEq(deployment.controller.stakedAsset(), address(STAKED_ASSET_ADDRESS));
        (address adapter, uint96 tolerance) = deployment.controller.oracle();
        assertEq(IOracleAdapter(adapter).oracle(), params.oracle);
        assertEq(tolerance, params.oracle_tolerance);
        assertEq(deployment.controller.blockMintLimit(), vm.parseUint(config.get("mint_limit").toString()));
        assertEq(deployment.controller.blockRedeemLimit(), vm.parseUint(config.get("redeem_limit").toString()));

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

    function test_fork_Revert_DeployController() public {
        DeployControllerHarness deployer = new DeployControllerHarness();

        vm.expectRevert(bytes("incorrect controller version"));
        deployer.run(CONFIG_DIR);
    }
}
