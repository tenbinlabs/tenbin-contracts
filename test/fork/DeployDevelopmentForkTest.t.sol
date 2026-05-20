// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Config} from "forge-std/Config.sol";
import {DeployDevelopment} from "../../script/DeployDevelopment.s.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ForkBaseTest} from "./ForkBaseTest.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

// test deployment script
// this requires .env is set up correctly
contract DeployDevelopmentForkTest is ForkBaseTest, Config {
    using SafeERC20 for IERC20;

    // variables
    DeployDevelopment.DeploymentResult deployment;
    DeployDevelopment devDeployer;

    function setUp() public override {
        // set a fork block where collateral vault exists
        forkBlock = 24425410;
        super.setUp();
        devDeployer = new DeployDevelopment();
        deployment = devDeployer.run("");
    }

    function test_Revert_DeployDevelopment() public {
        vm.chainId(2);

        vm.expectRevert();
        devDeployer.run("");
    }

    function test_DeployDevelopmentFork() public {
        _loadConfig("./config/mainnet/tgld/tgld.toml", false);
        // check default admin roles
        assertEq(deployment.controller.hasRole(DEFAULT_ADMIN_ROLE, config.get("default_admin_role").toAddress()), true);
        assertEq(deployment.manager.hasRole(DEFAULT_ADMIN_ROLE, config.get("default_admin_role").toAddress()), true);
        assertEq(deployment.asset.pendingOwner(), config.get("default_admin_role").toAddress());
        assertEq(deployment.multicall.hasRole(DEFAULT_ADMIN_ROLE, config.get("default_admin_role").toAddress()), true);
        assertEq(
            deployment.staked_asset.hasRole(DEFAULT_ADMIN_ROLE, config.get("default_admin_role").toAddress()), true
        );
        assertEq(
            deployment.revenue_module.hasRole(DEFAULT_ADMIN_ROLE, config.get("default_admin_role").toAddress()), true
        );
        assertEq(
            deployment.custodian_module.hasRole(DEFAULT_ADMIN_ROLE, config.get("default_admin_role").toAddress()), true
        );

        // check controller roles
        assertEq(deployment.controller.hasRole(MINTER_ROLE, config.get("minter_role").toAddress()), true);
        assertEq(deployment.controller.hasRole(GATEKEEPER_ROLE, config.get("gatekeeper_role").toAddress()), true);
        assertEq(deployment.controller.hasRole(ADMIN_ROLE, config.get("admin_role").toAddress()), true);
        assertEq(
            deployment.controller.hasRole(SIGNER_MANAGER_ROLE, config.get("signer_manager_role").toAddress()), true
        );
        assertEq(deployment.controller.hasRole(RESTRICTER_ROLE, config.get("restricter_role").toAddress()), true);

        // check manager roles
        assertEq(deployment.manager.revenueModule(), address(deployment.revenue_module));
        assertEq(deployment.manager.hasRole(ADMIN_ROLE, config.get("admin_role").toAddress()), true);
        assertEq(deployment.manager.hasRole(CURATOR_ROLE, config.get("curator_role").toAddress()), true);
        assertEq(deployment.manager.hasRole(REBALANCER_ROLE, config.get("rebalancer_role").toAddress()), true);
        assertEq(deployment.manager.hasRole(GATEKEEPER_ROLE, config.get("gatekeeper_role").toAddress()), true);
        assertEq(deployment.manager.hasRole(CAP_ADJUSTER_ROLE, config.get("cap_adjuster_role").toAddress()), true);

        // check staking roles
        assertEq(deployment.staked_asset.hasRole(REWARDER_ROLE, config.get("rewarder_role").toAddress()), true);
        assertEq(deployment.staked_asset.hasRole(REWARDER_ROLE, address(deployment.revenue_module)), true);
        assertEq(deployment.staked_asset.hasRole(ADMIN_ROLE, config.get("admin_role").toAddress()), true);
        assertEq(deployment.staked_asset.hasRole(RESTRICTER_ROLE, config.get("restricter_role").toAddress()), true);
        assertEq(deployment.staked_asset.hasRole(INSTANT_UNSTAKER_ROLE, address(deployment.controller)), true);

        // check multicall roles
        assertEq(deployment.multicall.hasRole(MULTICALLER_ROLE, config.get("multicaller_role").toAddress()), true);

        // check revenue manager roles
        assertEq(
            deployment.revenue_module.hasRole(DEFAULT_ADMIN_ROLE, config.get("default_admin_role").toAddress()), true
        );
        assertEq(
            deployment.revenue_module.hasRole(REVENUE_KEEPER_ROLE, config.get("revenue_keeper_role").toAddress()), true
        );

        // check custodian module roles
        assertEq(
            deployment.custodian_module.hasRole(CUSTODIAN_KEEPER_ROLE, config.get("custodian_keeper_role").toAddress()),
            true
        );

        // ensure roles are renounced by deployer (except local dev)
        if (block.chainid != 31337) {
            assertNotEq(deployment.asset.owner(), config.get("default_admin_role").toAddress());
            assertFalse(deployment.controller.hasRole(DEFAULT_ADMIN_ROLE, address(devDeployer)));
            assertFalse(deployment.manager.hasRole(DEFAULT_ADMIN_ROLE, address(devDeployer)));
            assertFalse(deployment.multicall.hasRole(DEFAULT_ADMIN_ROLE, address(devDeployer)));
            assertFalse(deployment.staked_asset.hasRole(DEFAULT_ADMIN_ROLE, address(devDeployer)));
            assertFalse(deployment.manager.hasRole(ADMIN_ROLE, address(devDeployer)));
            assertFalse(deployment.manager.hasRole(CURATOR_ROLE, address(devDeployer)));
            assertFalse(deployment.manager.hasRole(REBALANCER_ROLE, address(devDeployer)));
            assertFalse(deployment.manager.hasRole(GATEKEEPER_ROLE, address(devDeployer)));
            assertFalse(deployment.manager.hasRole(CAP_ADJUSTER_ROLE, address(devDeployer)));
            assertFalse(deployment.staked_asset.hasRole(REWARDER_ROLE, address(devDeployer)));
            assertFalse(deployment.staked_asset.hasRole(ADMIN_ROLE, address(devDeployer)));
            assertFalse(deployment.multicall.hasRole(MULTICALLER_ROLE, address(devDeployer)));
            assertFalse(deployment.revenue_module.hasRole(DEFAULT_ADMIN_ROLE, address(devDeployer)));
            assertFalse(deployment.revenue_module.hasRole(REVENUE_KEEPER_ROLE, address(devDeployer)));
            assertFalse(deployment.custodian_module.hasRole(DEFAULT_ADMIN_ROLE, address(devDeployer)));
        }

        // check controller is correctly configured
        assertEq(deployment.controller.custodian(), address(deployment.custodian_module));
        assertEq(deployment.controller.manager(), address(deployment.manager));
        assertEq(deployment.controller.blockMintLimit(), vm.parseUint(config.get("mint_limit").toString()));
        assertEq(deployment.controller.blockRedeemLimit(), vm.parseUint(config.get("redeem_limit").toString()));

        // check manager is correctly configured
        assertEq(deployment.manager.controller(), address(deployment.controller));
        assertEq(deployment.manager.swapModule(), address(deployment.swap_module));

        // check swap module is correctly configured
        assertEq(deployment.swap_module.manager(), address(deployment.manager));
        assertEq(deployment.swap_module.router(), address(deployment.one_inch_router));

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

        // check revenue module is correctly configured
        assertEq(deployment.revenue_module.manager(), address(deployment.manager));
        assertEq(deployment.revenue_module.staking(), address(deployment.staked_asset));
        assertEq(deployment.revenue_module.asset(), address(deployment.asset));
        assertEq(deployment.revenue_module.controller(), address(deployment.controller));
    }
}
