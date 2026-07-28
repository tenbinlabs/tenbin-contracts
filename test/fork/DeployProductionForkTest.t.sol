// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Config} from "forge-std/Config.sol";
import {Deploy} from "../../script/Deploy.s.sol";
import {DeployBase} from "../../script/DeployBase.s.sol";
import {DeployHarness} from "../harness/DeployHarness.sol";
import {ForkBaseTest} from "./ForkBaseTest.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IVaultV2} from "vault-v2/src/interfaces/IVaultV2.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {StdConfig} from "forge-std/StdConfig.sol";

// test deployment script
// this requires .env is set up correctly
contract DeployProductionForkTest is ForkBaseTest, Config {
    using SafeERC20 for IERC20;

    Deploy.CoreDeploymentResult core;
    Deploy.VaultDeploymentResult vaultResult;
    DeployBase.CoreParameters params;
    DeployBase.RolesParameters roles;
    DeployBase.VaultParameters vaultParams;

    string constant CONFIG_DIR = "./config/mainnet/tgld/tgld.toml";
    string constant VAULT_CONFIG_DIR = "./config/mainnet/tgld/vaults/tgld_usdc_vault.toml";

    function setUp() public override {
        // set a fork block where collateral vault exists
        forkBlock = 25383000;
        super.setUp();

        // the deploy script now deploys the morpho vault and performs a dead deposit from the
        // broadcaster (derived from TEST_MNEMONIC by BaseTest), so fund it with enough
        // collateral (usdc) to cover the deposit
        deal(address(usdc), broadcaster, 1_000_000e6);
    }

    function test_fork_Deploy_Prod() public {
        Deploy deployer = new Deploy();
        (core, vaultResult) = deployer.run(CONFIG_DIR, VAULT_CONFIG_DIR, false);
        sanityChecks(CONFIG_DIR, VAULT_CONFIG_DIR);
    }

    function test_fork_Default_Deploy() public {
        Deploy deployer = new Deploy();
        (core, vaultResult) = deployer.run("", "", false);
        sanityChecks(CONFIG_DIR, VAULT_CONFIG_DIR);
    }

    function test_fork_tBRL_Deploy() public {
        string memory dir = "./config/mainnet/tbrl/tbrl.toml";
        string memory vaultDir = "./config/mainnet/tbrl/vaults/tbrl_usdc_vault.toml";
        Deploy deployer = new Deploy();
        (core, vaultResult) = deployer.run(dir, vaultDir, false);
        sanityChecks(dir, vaultDir);
    }

    function test_fork_tMXN_Deploy() public {
        string memory dir = "./config/mainnet/tmxn/tmxn.toml";
        string memory vaultDir = "./config/mainnet/tmxn/vaults/tmxn_usdc_vault.toml";
        Deploy deployer = new Deploy();
        (core, vaultResult) = deployer.run(dir, vaultDir, false);
        sanityChecks(dir, vaultDir);
    }

    function sanityChecks(string memory configDir, string memory vaultConfigDir) internal {
        _loadConfig(configDir, false);
        StdConfig vaultConfig = new StdConfig(vaultConfigDir, false);
        vm.makePersistent(address(vaultConfig));
        assertEq(core.broadcaster, broadcaster);

        // roles
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

        // address parameters
        params.collateral = config.get("collateral").toAddress();
        params.custodian = config.get("custodian").toAddress();
        params.multisig = config.get("multisig").toAddress();

        // uint parameters
        params.cooldown_period = config.get("cooldown_period").toUint256();
        params.oracle_tolerance = config.get("oracle_tolerance").toUint256();
        params.ratio = config.get("ratio").toUint256();
        params.rebalance_cap = config.get("rebalance_cap").toUint256();
        params.vesting_period = config.get("vesting_period").toUint128();
        params.mint_limit = uint128(vm.parseUint(config.get("mint_limit").toString()));
        params.redeem_limit = uint128(vm.parseUint(config.get("redeem_limit").toString()));
        params.instant_unstake_cap = uint128(vm.parseUint(config.get("instant_unstake_cap").toString()));

        // vault parameters
        vaultParams.allocator = vaultConfig.get("allocator").toAddress();
        vaultParams.curator = vaultConfig.get("curator").toAddress();
        vaultParams.owner = vaultConfig.get("owner").toAddress();
        vaultParams.sentinel = vaultConfig.get("sentinel").toAddress();

        // check default admin roles
        assertEq(core.controller.hasRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role), true);
        assertEq(core.manager.hasRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role), true);
        assertEq(core.asset.pendingOwner(), roles.default_admin_role);
        assertEq(core.multicall.hasRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role), true);
        assertEq(core.staked_asset.hasRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role), true);
        assertEq(core.revenue_module.hasRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role), true);
        assertEq(core.custodian_module.hasRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role), true);

        // check controller config
        assertEq(core.controller.hasRole(MINTER_ROLE, roles.minter_role), true);
        assertEq(core.controller.hasRole(GATEKEEPER_ROLE, roles.gatekeeper_role), true);
        assertEq(core.controller.hasRole(GATEKEEPER_ROLE, roles.admin_role), true);
        assertEq(core.controller.hasRole(ADMIN_ROLE, roles.admin_role), true);
        assertEq(core.controller.hasRole(SIGNER_MANAGER_ROLE, roles.signer_manager_role), true);
        assertEq(core.controller.hasRole(RESTRICTER_ROLE, roles.restricter_role), true);
        assertEq(core.controller.ratio(), params.ratio);
        assertEq(core.controller.custodian(), address(core.custodian_module));
        assertEq(core.controller.manager(), address(core.manager));
        assertEq(core.controller.stakedAsset(), address(core.staked_asset));
        (address adapter, uint96 tolerance) = core.controller.oracle();
        assertEq(adapter, address(core.oracle_adapter));
        assertEq(tolerance, params.oracle_tolerance);
        assertEq(core.controller.blockMintLimit(), vm.parseUint(config.get("mint_limit").toString()));
        assertEq(core.controller.blockRedeemLimit(), vm.parseUint(config.get("redeem_limit").toString()));

        // check manager config
        assertEq(core.manager.revenueModule(), address(core.revenue_module));
        assertEq(core.manager.hasRole(ADMIN_ROLE, roles.admin_role), true);
        assertEq(core.manager.hasRole(CURATOR_ROLE, roles.curator_role), true);
        assertEq(core.manager.hasRole(REBALANCER_ROLE, roles.rebalancer_role), true);
        assertEq(core.manager.hasRole(GATEKEEPER_ROLE, roles.gatekeeper_role), true);
        assertEq(core.manager.hasRole(GATEKEEPER_ROLE, roles.admin_role), true);
        assertEq(core.manager.hasRole(CAP_ADJUSTER_ROLE, roles.cap_adjuster_role), true);
        assertEq(core.manager.controller(), address(core.controller));
        assertEq(core.manager.swapModule(), address(core.swap_module));
        assertEq(core.manager.revenueModule(), address(core.revenue_module));
        // the manager is wired to the vault deployed by this run
        assertEq(address(core.manager.vaults(params.collateral)), address(vaultResult.vault));
        assertEq(core.manager.rebalanceCap(params.collateral), params.rebalance_cap);
        // swap cap is no longer sourced from config, so it must default to 0
        assertEq(core.manager.swapCap(params.collateral), 0);

        // check staking config
        assertEq(core.staked_asset.hasRole(REWARDER_ROLE, roles.rewarder_role), true);
        assertEq(core.staked_asset.hasRole(REWARDER_ROLE, address(core.revenue_module)), true);
        assertEq(core.staked_asset.hasRole(ADMIN_ROLE, roles.admin_role), true);
        assertEq(core.staked_asset.hasRole(RESTRICTER_ROLE, roles.restricter_role), true);
        assertEq(core.staked_asset.hasRole(CAP_ADJUSTER_ROLE, roles.cap_adjuster_role), true);
        assertEq(core.staked_asset.hasRole(INSTANT_UNSTAKER_ROLE, address(core.controller)), true);

        // check multicall config
        assertEq(core.multicall.hasRole(MULTICALLER_ROLE, roles.multicaller_role), true);

        // check revenue module config
        assertEq(core.revenue_module.hasRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role), true);
        assertEq(core.revenue_module.hasRole(REVENUE_KEEPER_ROLE, roles.revenue_keeper_role), true);
        assertEq(core.revenue_module.hasRole(ADMIN_ROLE, roles.admin_role), true);
        assertEq(core.revenue_module.staking(), address(core.staked_asset));
        assertEq(core.revenue_module.asset(), address(core.asset));
        assertEq(core.revenue_module.manager(), address(core.manager));
        assertEq(core.revenue_module.controller(), address(core.controller));
        assertEq(core.revenue_module.multisig(), params.multisig);

        // check custodian module config
        assertEq(core.custodian_module.hasRole(CUSTODIAN_KEEPER_ROLE, roles.custodian_keeper_role), true);
        assertEq(core.custodian_module.custodians(params.custodian), true);

        // check manager is correctly configured
        assertEq(core.manager.controller(), address(core.controller));
        assertEq(core.manager.swapModule(), address(core.swap_module));

        // check swap module is correctly configured
        assertEq(core.swap_module.manager(), address(core.manager));
        assertEq(core.swap_module.router(), address(core.one_inch_router));
        assertEq(core.swap_module.admin(), address(roles.admin_role));

        // check staking is correctly configured
        (
            uint128 length,
            /*uint128 time*/, /*uint256 amount*/
        ) = core.staked_asset.vesting();
        assertEq(length, config.get("vesting_period").toUint128());
        assertEq(core.staked_asset.cooldownPeriod(), config.get("cooldown_period").toUint256());
        assertEq(core.staked_asset.instantUnstakeCap(), vm.parseUint(config.get("instant_unstake_cap").toString()));

        // check revenue module is correctly configured
        assertEq(core.revenue_module.manager(), address(core.manager));
        assertEq(core.revenue_module.staking(), address(core.staked_asset));
        assertEq(core.revenue_module.asset(), address(core.asset));
        assertEq(core.revenue_module.controller(), address(core.controller));
        assertEq(core.revenue_module.multisig(), address(params.multisig));

        // check the morpho vault deployed by this run is handed over to its final roles
        IVaultV2 vault = vaultResult.vault;
        assertEq(vault.owner(), vaultParams.owner);
        assertEq(vault.curator(), vaultParams.curator);
        assertEq(vault.isSentinel(vaultParams.sentinel), true);
        assertEq(vault.isAllocator(vaultParams.allocator), true);
        assertEq(vault.isAllocator(broadcaster), false);
        // the gate is owned by the curator after being wired to the collateral manager
        assertEq(vaultResult.gate.owner(), vaultParams.curator);

        // ensure roles are renounced by deployer
        assertEq(core.asset.pendingOwner(), roles.default_admin_role);
        assertFalse(core.controller.hasRole(DEFAULT_ADMIN_ROLE, broadcaster));
        assertFalse(core.manager.hasRole(DEFAULT_ADMIN_ROLE, broadcaster));
        assertFalse(core.multicall.hasRole(DEFAULT_ADMIN_ROLE, broadcaster));
        assertFalse(core.staked_asset.hasRole(DEFAULT_ADMIN_ROLE, broadcaster));
        assertFalse(core.revenue_module.hasRole(DEFAULT_ADMIN_ROLE, broadcaster));
        assertFalse(core.manager.hasRole(ADMIN_ROLE, broadcaster));
        assertFalse(core.manager.hasRole(CURATOR_ROLE, broadcaster));
        assertFalse(core.manager.hasRole(REBALANCER_ROLE, broadcaster));
        assertFalse(core.manager.hasRole(GATEKEEPER_ROLE, broadcaster));
        assertFalse(core.manager.hasRole(CAP_ADJUSTER_ROLE, broadcaster));
        assertFalse(core.staked_asset.hasRole(REWARDER_ROLE, broadcaster));
        assertFalse(core.staked_asset.hasRole(ADMIN_ROLE, broadcaster));
        assertFalse(core.staked_asset.hasRole(CAP_ADJUSTER_ROLE, broadcaster));
        assertFalse(core.multicall.hasRole(MULTICALLER_ROLE, broadcaster));
        assertFalse(core.revenue_module.hasRole(REVENUE_KEEPER_ROLE, broadcaster));
        assertFalse(core.custodian_module.hasRole(DEFAULT_ADMIN_ROLE, broadcaster));
        assertFalse(core.custodian_module.hasRole(CUSTODIAN_KEEPER_ROLE, broadcaster));
    }

    function test_fork_Revert_Controller_DeployProduction() public {
        DeployHarness deployer = new DeployHarness();

        vm.expectRevert(bytes("controller version mismatch"));
        deployer.run(CONFIG_DIR, VAULT_CONFIG_DIR, false);
    }

    function test_fork_Revert_Router_DeployProduction() public {
        Deploy deployer = new Deploy();

        vm.expectRevert(bytes("Invalid router"));
        deployer.run("./config/test/invalid_router.toml", VAULT_CONFIG_DIR, false);
    }

    function test_fork_Revert_Oracle_DeployProduction() public {
        Deploy deployer = new Deploy();

        // tGLD
        vm.expectRevert(bytes("oracle mismatch"));
        deployer.run("./config/test/tgld_invalid_oracle.toml", VAULT_CONFIG_DIR, false);
        vm.stopBroadcast();

        // tBRL
        vm.expectRevert(bytes("oracle mismatch"));
        deployer.run(
            "./config/test/tbrl_invalid_oracle.toml", "./config/mainnet/tbrl/vaults/tbrl_usdc_vault.toml", false
        );
        vm.stopBroadcast();

        // tMXN
        vm.expectRevert(bytes("oracle mismatch"));
        deployer.run(
            "./config/test/tmxn_invalid_oracle.toml", "./config/mainnet/tmxn/vaults/tmxn_usdc_vault.toml", false
        );
    }
}
