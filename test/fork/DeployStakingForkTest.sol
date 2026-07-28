// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Config} from "forge-std/Config.sol";
import {DeployStaking} from "../../script/DeployStaking.s.sol";
import {ForkBaseTest} from "./ForkBaseTest.sol";
import {stdToml} from "forge-std/StdToml.sol";

// test deployment script
// this requires .env is set up correctly
contract DeployStakingForkTest is ForkBaseTest, Config {
    using stdToml for string;

    address constant ASSET_TOKEN_ADDRESS = 0x6a547b25534234bb79CE6961a23Db13DE154b6F4;
    uint256 constant DEAD_DEPOSIT_AMOUNT = 0.001e18;
    DeployStaking.CoreParameters params;
    DeployStaking.RolesParameters roles;
    DeployStaking.DeploymentResult deployment;
    string constant CONFIG_DIR = "./config/mainnet/tgld/tgld.toml";

    function setUp() public override {
        super.setUp();
        // mock mint asset tokens
        deal(ASSET_TOKEN_ADDRESS, broadcaster, DEAD_DEPOSIT_AMOUNT);
        DeployStaking deployer = new DeployStaking();
        deployment = deployer.run(CONFIG_DIR);
    }

    function test_fork_DeployStaking() public {
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
        assertEq(deployment.staked_asset.hasRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role), true);

        // check staking roles
        assertEq(deployment.staked_asset.hasRole(REWARDER_ROLE, config.get("multisig").toAddress()), true);
        assertEq(deployment.staked_asset.hasRole(ADMIN_ROLE, config.get("admin_role").toAddress()), true);
        assertEq(deployment.staked_asset.hasRole(RESTRICTER_ROLE, config.get("restricter_role").toAddress()), true);
        assertEq(deployment.staked_asset.hasRole(CAP_ADJUSTER_ROLE, config.get("cap_adjuster_role").toAddress()), true);

        // check staking is correctly configured
        (
            uint128 length,
            /*uint128 time*/, /*uint256 amount*/
        ) = deployment.staked_asset.vesting();
        assertEq(length, config.get("vesting_period").toUint128());
        assertEq(deployment.staked_asset.cooldownPeriod(), config.get("cooldown_period").toUint256());
        assertEq(
            deployment.staked_asset.instantUnstakeCap(), vm.parseUint(config.get("instant_unstake_cap").toString())
        );

        // ensure roles are renounced by deployer
        assertFalse(deployment.staked_asset.hasRole(DEFAULT_ADMIN_ROLE, deployment.broadcaster));
        assertFalse(deployment.staked_asset.hasRole(CAP_ADJUSTER_ROLE, deployment.broadcaster));
        assertFalse(deployment.staked_asset.hasRole(ADMIN_ROLE, deployment.broadcaster));
    }

    function test_fork_Revert_DeployStaking() public {
        DeployStaking deployer = new DeployStaking();

        vm.expectRevert("Insufficient balance for dead deposit.");
        deployer.run(CONFIG_DIR);
    }
}
