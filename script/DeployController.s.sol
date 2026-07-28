// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/console2.sol";
import {Controller} from "tenbin-contracts/src/Controller.sol";
import {DeployBase} from "./DeployBase.s.sol";
import {GoldOracleAdapter} from "tenbin-contracts/src/oracle/GoldOracleAdapter.sol";
import {IOracleAdapter} from "tenbin-contracts/src/interface/IOracleAdapter.sol";
import {RevenueModule} from "tenbin-contracts/src/RevenueModule.sol";

/// @notice Deploy and configure new controller and new revenue module using config/*.toml
/// @dev To upgrade a set of core contracts to a new controller, the following steps need to be performed after running this script:
/// 1. Ensure addresses and version are correctly set in `scripts/DeployController.s.sol`
/// 2. Deploy a new version of the controller and revenue module by running: `scripts/DeployController.s.sol`
/// 3. Call `setMinter` on asset token
/// 4. Call `updateController` on collateral manager
/// 5. Call ``grantRole` on collateral manager to assign the CURATOR_ROLE to the new controller
/// 6. Call `setRevenueModule` from owner multisig
/// 7. Update `deployments.json` with new controller address
/// 8. Update signers and notify signers they need to update delegations and approved signers
// **Note: all previous signers and signer configurations will be lost upon upgrading the controller.
/// Signers will need to update their approved payers and recipients after the upgrade**
///
/// Running this script:
/// FOUNDRY_PROFILE=production forge script script/DeployController.s.sol $CONFIG_DIR --rpc-url $MAINNET_RPC_URL --private-key $BROADCASTER_KEY --verify --verifier etherscan --verifier-api-key $ETHERSCAN_API_KEY --slow
contract DeployController is DeployBase {
    // configuration for the controller that is being upgraded
    string constant TARGET_VERSION = "1.4.3";
    address constant ASSET_TOKEN_ADDRESS = 0x8d015aFcb6F437010653352EB1E58152c4e23734;
    address constant COLLATERAL_MANAGER_ADDRESS = 0x2a21014B89F72de3Ffa6d645F89b8Ca5A6eFfe75;
    address constant CUSTODIAN_MODULE_ADDRESS = 0x22503f510C87040C6a16F9880dd3dAacB742e192;
    address constant MULTICALL_ADDRESS = 0x80A5c0A4c09F76E67CB6397858A5a1890a4ec5a9;
    address constant MULTISIG_ADDRESS = 0x9cC553d9F9e9690C0bc97bC2E1d10696d3862aC8;
    address constant STAKED_ASSET_ADDRESS = 0x8BDf6A2DFda084bD242Cd285CF75E80de3eB00ba;
    address constant ORACLE_ADAPTER_ADDRESS = 0xb5c72C24794bbcc2cab1773b7fE05C77194F7273;

    /// @notice Results returned when running this deployment script
    struct DeploymentResult {
        address broadcaster;
        Controller controller;
        IOracleAdapter oracle_adapter;
        RevenueModule revenue_module;
    }

    /// @dev The version for this deployment
    function getVersion() internal pure virtual override returns (string memory) {
        return TARGET_VERSION;
    }

    function run(string memory configDir) public returns (DeploymentResult memory deployment) {
        loadCoreConfig(configDir);
        loadRolesConfig();
        deployment = deploy();
    }

    function deploy() internal broadcast returns (DeploymentResult memory deployment) {
        console2.log("\n========================= Accounts ==========================\n");
        console2.log("broadcaster address: ", broadcaster);

        // save broadcaster
        deployment.broadcaster = broadcaster;

        // deploy controller
        deployment.controller = new Controller{salt: SALT}(
            ASSET_TOKEN_ADDRESS, STAKED_ASSET_ADDRESS, coreParams.ratio, CUSTODIAN_MODULE_ADDRESS, broadcaster
        );

        // deploy revenue module
        deployment.revenue_module = new RevenueModule{salt: SALT}(
            address(COLLATERAL_MANAGER_ADDRESS),
            address(STAKED_ASSET_ADDRESS),
            broadcaster,
            address(deployment.controller),
            address(ASSET_TOKEN_ADDRESS),
            address(MULTISIG_ADDRESS)
        );

        // deploy oracle adapter
        deployment.oracle_adapter = IOracleAdapter(ORACLE_ADAPTER_ADDRESS);

        // hard enforce version
        require(
            keccak256(bytes(deployment.controller.version())) == keccak256(bytes(getVersion())),
            "incorrect controller version"
        );

        // set controller permissions
        deployment.controller.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.controller.grantRole(ADMIN_ROLE, roles.admin_role);
        deployment.controller.grantRole(MINTER_ROLE, roles.minter_role);
        deployment.controller.grantRole(MINTER_ROLE, address(MULTICALL_ADDRESS));
        deployment.controller.grantRole(GATEKEEPER_ROLE, roles.gatekeeper_role);
        deployment.controller.grantRole(SIGNER_MANAGER_ROLE, roles.signer_manager_role);
        deployment.controller.grantRole(RESTRICTER_ROLE, roles.restricter_role);

        // give temporary permissions to broadcaster
        deployment.controller.grantRole(ADMIN_ROLE, broadcaster);

        // configure controller
        deployment.controller.setIsCollateral(address(coreParams.collateral), true);
        deployment.controller.setManager(COLLATERAL_MANAGER_ADDRESS);
        deployment.controller.setOracleAdapter(address(deployment.oracle_adapter));
        deployment.controller.setOracleTolerance(uint96(coreParams.oracle_tolerance));
        deployment.controller.setBlockMintLimit(coreParams.mint_limit);
        deployment.controller.setBlockRedeemLimit(coreParams.redeem_limit);

        // configure revenue module
        deployment.revenue_module.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.revenue_module.grantRole(ADMIN_ROLE, roles.admin_role);
        deployment.revenue_module.grantRole(REVENUE_KEEPER_ROLE, roles.revenue_keeper_role);
        deployment.revenue_module.grantRole(REWARDER_ROLE, roles.rewarder_role);

        // revoke broadcaster admin roles
        deployment.controller.revokeRole(ADMIN_ROLE, broadcaster);
        deployment.controller.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
        deployment.revenue_module.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);

        // Serialize json and print contracts
        serialize(deployment);
        printContracts(deployment);
        printLogo();
    }

    function serialize(DeploymentResult memory deployment) internal {
        console2.log("\nSerializing json...\n");

        // Build objects and keys
        string memory obj = "{}";
        string memory chainKey = "mainnet";

        string memory assetKey = "tGLD";
        string memory contractsObj = "{}";
        string memory contractsKey = "contracts";
        string memory configKey = "config";
        string memory configObj = "{}";

        // serialize contracts
        contractsObj = vm.serializeAddress(contractsKey, "controller", address(deployment.controller));
        contractsObj = vm.serializeAddress(contractsKey, "oracle_adapter", address(deployment.oracle_adapter));
        contractsObj = vm.serializeAddress(contractsKey, "revenue_module", address(deployment.revenue_module));

        // serialize config
        configObj = vm.serializeUint(configKey, "deployment_block", block.number);
        configObj = vm.serializeBytes32(configKey, "domain_separator", deployment.controller.getDomainSeparator());
        configObj = vm.serializeString(configKey, "version", deployment.controller.version());
        configObj = vm.serializeAddress(configKey, "deployer", broadcaster);

        // build final object
        vm.serializeString(assetKey, configKey, configObj);
        string memory assetJson = vm.serializeString(assetKey, contractsKey, contractsObj);
        string memory chainJson = vm.serializeString(chainKey, assetKey, assetJson);

        // Wrap under chainKey
        obj = vm.serializeString("root", chainKey, chainJson);

        // save to file
        string memory path = string.concat("broadcast/DeployController.s.sol/", vm.toString(block.chainid));
        vm.createDir(path, true);
        vm.writeJson(obj, string.concat(path, "/contracts.json"));
    }

    function printContracts(DeploymentResult memory deployment) internal view {
        console2.log("\n========================= Domain ============================\n");
        console2.log("domain separator: ");
        console2.logBytes32(deployment.controller.getDomainSeparator());
        console2.log("order typehash: ");
        console2.logBytes32(deployment.controller.ORDER_TYPEHASH());
        console2.log("context typehash: ");
        console2.logBytes32(deployment.controller.CONTEXT_TYPEHASH());
        console2.log("\n========================= Contracts =========================\n");
        console2.log("Controller: ", address(deployment.controller));
        console2.log("RevenueModule: ", address(deployment.revenue_module));
        console2.log("\n=============================================================\n");
    }
}
