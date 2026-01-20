// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Config} from "forge-std/Config.sol";
import {DeployTestnet} from "script/DeployTestnet.s.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Test} from "forge-std/Test.sol";

// test deployment script
// this requires .env is set up correctly
contract DeploymentTest is Test, Config {
    using SafeERC20 for IERC20;

    // default values
    uint256 public constant DEFAULT_RATIO = 1e17;
    uint128 public constant DEFAULT_COOLDOWN_PERIOD = 180 seconds;
    uint128 public constant DEFAULT_VESTING_PERIOD = 1200 seconds;

    // roles
    bytes32 internal constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 internal constant CAP_ADJUSTER_ROLE = keccak256("CAP_ADJUSTER_ROLE");
    bytes32 internal constant CURATOR_ROLE = keccak256("CURATOR_ROLE");
    bytes32 internal constant CUSTODIAN_KEEPER_ROLE = keccak256("CUSTODIAN_KEEPER_ROLE");
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant GATEKEEPER_ROLE = keccak256("GATEKEEPER_ROLE");
    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 internal constant MULTICALLER_ROLE = keccak256("MULTICALLER_ROLE");
    bytes32 internal constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");
    bytes32 internal constant RESTRICTER_ROLE = keccak256("RESTRICTER_ROLE");
    bytes32 internal constant REVENUE_KEEPER_ROLE = keccak256("REVENUE_KEEPER_ROLE");
    bytes32 internal constant REWARDER_ROLE = keccak256("REWARDER_ROLE");
    bytes32 internal constant SIGNER_MANAGER_ROLE = keccak256("SIGNER_MANAGER_ROLE");

    // variables
    DeployTestnet.DeploymentResult deployment;

    function setUp() public {
        DeployTestnet deployer = new DeployTestnet();
        deployment = deployer.run();
    }

    function test_Deployment() public {
        _loadConfig("./config.toml", false);
        // check default admin roles
        assertEq(deployment.controller.hasRole(DEFAULT_ADMIN_ROLE, config.get("owner").toAddress()), true);
        assertEq(deployment.manager.hasRole(DEFAULT_ADMIN_ROLE, config.get("owner").toAddress()), true);
        assertEq(deployment.asset.pendingOwner(), config.get("owner").toAddress());
        assertEq(deployment.multicall.hasRole(DEFAULT_ADMIN_ROLE, config.get("owner").toAddress()), true);
        assertEq(deployment.staking.hasRole(DEFAULT_ADMIN_ROLE, config.get("owner").toAddress()), true);
        assertEq(deployment.revenueModule.hasRole(DEFAULT_ADMIN_ROLE, config.get("owner").toAddress()), true);
        assertEq(deployment.custodianModule.hasRole(DEFAULT_ADMIN_ROLE, config.get("owner").toAddress()), true);

        // check controller roles
        assertEq(deployment.controller.hasRole(MINTER_ROLE, config.get("minter").toAddress()), true);
        assertEq(deployment.controller.hasRole(GATEKEEPER_ROLE, config.get("gatekeeper").toAddress()), true);
        assertEq(deployment.controller.hasRole(ADMIN_ROLE, config.get("admin").toAddress()), true);
        assertEq(deployment.controller.hasRole(SIGNER_MANAGER_ROLE, config.get("signer_manager").toAddress()), true);
        assertEq(deployment.controller.hasRole(RESTRICTER_ROLE, config.get("restricter").toAddress()), true);

        // check manager roles
        assertEq(deployment.manager.revenueModule(), address(deployment.revenueModule));
        assertEq(deployment.manager.hasRole(ADMIN_ROLE, config.get("admin").toAddress()), true);
        assertEq(deployment.manager.hasRole(CURATOR_ROLE, config.get("curator").toAddress()), true);
        assertEq(deployment.manager.hasRole(REBALANCER_ROLE, config.get("custodian").toAddress()), true);
        assertEq(deployment.manager.hasRole(GATEKEEPER_ROLE, config.get("gatekeeper").toAddress()), true);
        assertEq(deployment.manager.hasRole(CAP_ADJUSTER_ROLE, config.get("cap_adjuster").toAddress()), true);

        // check staking roles
        assertEq(deployment.staking.hasRole(REWARDER_ROLE, config.get("rewarder").toAddress()), true);
        assertEq(deployment.staking.hasRole(REWARDER_ROLE, address(deployment.revenueModule)), true);
        assertEq(deployment.staking.hasRole(ADMIN_ROLE, config.get("admin").toAddress()), true);
        assertEq(deployment.staking.hasRole(RESTRICTER_ROLE, config.get("restricter").toAddress()), true);

        // check multicall roles
        assertEq(deployment.multicall.hasRole(MULTICALLER_ROLE, config.get("multicaller").toAddress()), true);

        // check revenue manager roles
        assertEq(deployment.revenueModule.hasRole(DEFAULT_ADMIN_ROLE, config.get("owner").toAddress()), true);
        assertEq(deployment.revenueModule.hasRole(REVENUE_KEEPER_ROLE, config.get("revenue_keeper").toAddress()), true);

        // check custodian module roles
        assertEq(
            deployment.custodianModule.hasRole(CUSTODIAN_KEEPER_ROLE, config.get("custodian_keeper").toAddress()), true
        );

        // ensure roles are renounced by deployer (except local dev)
        if (block.chainid != 31337) {
            assertFalse(deployment.controller.hasRole(DEFAULT_ADMIN_ROLE, config.get("deployer").toAddress()));
            assertFalse(deployment.manager.hasRole(DEFAULT_ADMIN_ROLE, config.get("deployer").toAddress()));
            assertFalse(deployment.multicall.hasRole(DEFAULT_ADMIN_ROLE, config.get("deployer").toAddress()));
            assertFalse(deployment.staking.hasRole(DEFAULT_ADMIN_ROLE, config.get("deployer").toAddress()));
            assertFalse(deployment.manager.hasRole(ADMIN_ROLE, config.get("deployer").toAddress()));
            assertFalse(deployment.manager.hasRole(CURATOR_ROLE, config.get("deployer").toAddress()));
            assertFalse(deployment.manager.hasRole(REBALANCER_ROLE, config.get("deployer").toAddress()));
            assertFalse(deployment.manager.hasRole(GATEKEEPER_ROLE, config.get("deployer").toAddress()));
            assertFalse(deployment.manager.hasRole(CAP_ADJUSTER_ROLE, config.get("deployer").toAddress()));
            assertFalse(deployment.staking.hasRole(REWARDER_ROLE, config.get("deployer").toAddress()));
            assertFalse(deployment.staking.hasRole(ADMIN_ROLE, config.get("deployer").toAddress()));
            assertFalse(deployment.multicall.hasRole(MULTICALLER_ROLE, config.get("deployer").toAddress()));
            assertFalse(deployment.revenueModule.hasRole(DEFAULT_ADMIN_ROLE, config.get("deployer").toAddress()));
            assertFalse(deployment.revenueModule.hasRole(REVENUE_KEEPER_ROLE, config.get("deployer").toAddress()));
            assertFalse(deployment.custodianModule.hasRole(DEFAULT_ADMIN_ROLE, config.get("deployer").toAddress()));
        }

        // check controller is correctly configured
        assertEq(deployment.controller.ratio(), DEFAULT_RATIO);
        assertEq(deployment.controller.custodian(), address(deployment.custodianModule));
        assertEq(deployment.controller.manager(), address(deployment.manager));

        // check manager is correctly configured
        assertEq(deployment.manager.controller(), address(deployment.controller));
        assertEq(deployment.manager.swapModule(), address(deployment.swapModule));

        // check swap module is correctly configured
        assertEq(deployment.swapModule.manager(), address(deployment.manager));
        assertEq(deployment.swapModule.router(), address(deployment.router));

        // check staking is correctly configured
        (
            uint128 length,
            /*uint128 time*/, /*uint256 amount*/
        ) = deployment.staking.vesting();
        assertEq(length, DEFAULT_VESTING_PERIOD);
        assertEq(deployment.staking.cooldownPeriod(), DEFAULT_COOLDOWN_PERIOD);

        // check revenue module is correctly configured
        assertEq(deployment.revenueModule.manager(), address(deployment.manager));
        assertEq(deployment.revenueModule.staking(), address(deployment.staking));
        assertEq(deployment.revenueModule.asset(), address(deployment.asset));
        assertEq(deployment.revenueModule.controller(), address(deployment.controller));
    }
}
