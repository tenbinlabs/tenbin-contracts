// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetSilo} from "tenbin-contracts/src/AssetSilo.sol";
import {AssetToken} from "tenbin-contracts/src/AssetToken.sol";
import {CollateralManager} from "tenbin-contracts/src/CollateralManager.sol";
import {console2} from "forge-std/console2.sol";
import {Controller} from "tenbin-contracts/src/Controller.sol";
import {CustodianModule} from "tenbin-contracts/src/CustodianModule.sol";
import {DeployBase} from "./DeployBase.s.sol";
import {ERC1967Proxy} from "tenbin-contracts/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {GoldOracleAdapter} from "tenbin-contracts/src/oracle/GoldOracleAdapter.sol";
import {IERC20} from "tenbin-contracts/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "tenbin-contracts/lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IOracleAdapter} from "tenbin-contracts/src/interface/IOracleAdapter.sol";
import {MultiCall} from "tenbin-contracts/src/MultiCall.sol";
import {RevenueModule} from "tenbin-contracts/src/RevenueModule.sol";
import {StakedAsset} from "tenbin-contracts/src/StakedAsset.sol";
import {SwapModule} from "tenbin-contracts/src/SwapModule.sol";

/// @notice Deploy and configure the protocol using config/*.toml file to mainnet
contract DeployProduction is DeployBase {
    /// @notice Default mainnet config directory to be used if none was specified
    string constant DEFAULT_DIR = "./config/mainnet/tgld/tgld.toml";

    /// @notice Contracts deployed by this script
    struct DeploymentResult {
        address broadcaster;
        address one_inch_router;
        AssetSilo silo;
        AssetToken asset;
        Controller controller;
        CustodianModule custodian_module;
        CollateralManager manager;
        IERC20 collateral;
        IERC4626 vault;
        MultiCall multicall;
        IOracleAdapter oracle_adapter;
        RevenueModule revenue_module;
        StakedAsset staking;
        SwapModule swap_module;
    }

    /// @dev The version for this deployment
    function getVersion() internal pure override returns (string memory) {
        return "1.0.0";
    }

    function run(string memory configDir) public returns (DeploymentResult memory deployment) {
        if (bytes(configDir).length != 0) {
            loadConfig(configDir);
        } else {
            loadConfig(DEFAULT_DIR);
        }
        deployment = deploy();
    }

    function deploy() public broadcast returns (DeploymentResult memory deployment) {
        printAccounts();

        deployment.broadcaster = broadcaster;

        // deploy core contracts
        deployment.asset = new AssetToken{salt: SALT}(params.asset_name, params.asset_symbol, broadcaster);
        deployment.custodian_module = new CustodianModule(broadcaster);
        deployment.controller = new Controller{salt: SALT}(
            address(deployment.asset), params.ratio, address(deployment.custodian_module), broadcaster
        );
        deployment.multicall = new MultiCall{salt: SALT}(broadcaster);

        // deploy manager behind a proxy
        address managerImplementation = address(new CollateralManager{salt: SALT}());
        bytes memory data =
            abi.encodeWithSelector(CollateralManager.initialize.selector, address(deployment.controller), broadcaster);
        ERC1967Proxy proxy = new ERC1967Proxy{salt: SALT}(managerImplementation, data);
        deployment.manager = CollateralManager(address(proxy));
        deployment.one_inch_router = params.one_inch_router;

        // deploy staking behind a proxy
        address stakingImplementation = address(new StakedAsset{salt: SALT}());
        data = abi.encodeWithSelector(
            StakedAsset.initialize.selector,
            params.staked_asset_name,
            params.staked_asset_symbol,
            deployment.asset,
            broadcaster,
            0,
            address(0)
        );
        proxy = new ERC1967Proxy{salt: SALT}(stakingImplementation, data);
        deployment.staking = StakedAsset(address(proxy));
        deployment.silo = AssetSilo(address(deployment.staking.silo()));

        // deploy swap module
        deployment.swap_module = new SwapModule{salt: SALT}(
            address(deployment.manager), address(deployment.one_inch_router), roles.admin_role
        );

        // deploy revenue module
        deployment.revenue_module = new RevenueModule{salt: SALT}(
            address(deployment.manager),
            address(deployment.staking),
            broadcaster,
            address(deployment.controller),
            address(deployment.asset),
            address(params.multisig)
        );

        // deploy oracle adapter
        deployment.oracle_adapter = IOracleAdapter(address(new GoldOracleAdapter(params.oracle)));

        // save vault & collateral addresses in storage
        deployment.collateral = IERC20(params.collateral);
        deployment.vault = IERC4626(params.vault);

        // set asset permissions
        deployment.asset.setMinter(address(deployment.controller));

        // set controller permissions
        deployment.controller.grantRole(ADMIN_ROLE, roles.admin_role);
        deployment.controller.grantRole(MINTER_ROLE, roles.minter_role);
        deployment.controller.grantRole(MINTER_ROLE, address(deployment.multicall));
        deployment.controller.grantRole(GATEKEEPER_ROLE, roles.gatekeeper_role);
        deployment.controller.grantRole(SIGNER_MANAGER_ROLE, roles.signer_manager_role);
        deployment.controller.grantRole(RESTRICTER_ROLE, roles.restricter_role);

        // set manager permissions
        deployment.manager.grantRole(ADMIN_ROLE, roles.admin_role);
        deployment.manager.grantRole(CURATOR_ROLE, roles.curator_role);
        deployment.manager.grantRole(REBALANCER_ROLE, roles.rebalancer_role);
        deployment.manager.grantRole(CAP_ADJUSTER_ROLE, roles.cap_adjuster_role);
        deployment.manager.grantRole(CURATOR_ROLE, address(deployment.multicall));
        deployment.manager.grantRole(CURATOR_ROLE, address(deployment.controller));
        deployment.manager.grantRole(GATEKEEPER_ROLE, roles.gatekeeper_role);

        // set multicall permissions
        deployment.multicall.grantRole(MULTICALLER_ROLE, roles.multicaller_role);

        // set staking permissions
        deployment.staking.grantRole(ADMIN_ROLE, roles.admin_role);
        deployment.staking.grantRole(REWARDER_ROLE, roles.rewarder_role);
        deployment.staking.grantRole(REWARDER_ROLE, address(deployment.revenue_module));
        deployment.staking.grantRole(RESTRICTER_ROLE, roles.restricter_role);
        deployment.staking.grantRole(CAP_ADJUSTER_ROLE, roles.cap_adjuster_role);
        deployment.staking.grantRole(INSTANT_UNSTAKER_ROLE, address(deployment.controller));

        // set module permissions
        deployment.revenue_module.grantRole(ADMIN_ROLE, roles.admin_role);
        deployment.revenue_module.grantRole(REVENUE_KEEPER_ROLE, roles.revenue_keeper_role);
        deployment.custodian_module.grantRole(CUSTODIAN_KEEPER_ROLE, roles.custodian_keeper_role);

        // give temporary permissions to broadcaster
        deployment.controller.grantRole(ADMIN_ROLE, broadcaster);
        deployment.controller.grantRole(SIGNER_MANAGER_ROLE, broadcaster);
        deployment.manager.grantRole(ADMIN_ROLE, broadcaster);
        deployment.manager.grantRole(CAP_ADJUSTER_ROLE, broadcaster);
        deployment.staking.grantRole(ADMIN_ROLE, broadcaster);
        deployment.staking.grantRole(CAP_ADJUSTER_ROLE, broadcaster);

        // configure controller
        deployment.controller.setIsCollateral(address(deployment.collateral), true);
        deployment.controller.setManager(address(deployment.manager));
        deployment.controller.setOracleAdapter(address(deployment.oracle_adapter));
        deployment.controller.setOracleTolerance(uint96(params.oracle_tolerance));

        // configure manager
        deployment.manager.addCollateral(address(deployment.collateral), address(deployment.vault));
        deployment.manager.setSwapModule(address(deployment.swap_module));
        deployment.manager.setRevenueModule(address(deployment.revenue_module));
        deployment.manager.setRebalanceCap(address(deployment.collateral), params.rebalance_cap);

        // configure staking
        deployment.staking.setCooldownPeriod(params.cooldown_period);
        deployment.staking.setVestingPeriod(uint128(params.vesting_period));

        // configure custodian module
        deployment.custodian_module.setCustodianStatus(params.custodian, true);

        // revoke broadcaster cap adjuster role
        deployment.manager.revokeRole(CAP_ADJUSTER_ROLE, broadcaster);
        deployment.staking.revokeRole(CAP_ADJUSTER_ROLE, broadcaster);

        // transfer ownership
        deployment.manager.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.controller.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.multicall.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.staking.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.revenue_module.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.custodian_module.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.asset.transferOwnership(roles.default_admin_role);

        // revoke broadcaster admin roles
        deployment.controller.revokeRole(ADMIN_ROLE, broadcaster);
        deployment.manager.revokeRole(ADMIN_ROLE, broadcaster);
        deployment.staking.revokeRole(ADMIN_ROLE, broadcaster);
        deployment.controller.revokeRole(SIGNER_MANAGER_ROLE, broadcaster);

        // revoke broadcaster default admin roles
        deployment.controller.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
        deployment.manager.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
        deployment.multicall.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
        deployment.staking.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
        deployment.revenue_module.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
        deployment.custodian_module.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);

        // Serialize json and print contracts
        serialize(deployment);
        printContracts(deployment);
        printLogo();
    }

    // Given a deployment result, serialize the JSON
    function serialize(DeploymentResult memory deployment) internal {
        console2.log("\nSerializing json...\n");
        // objects
        string memory obj = "{}";

        // keys
        string memory chainKey = "mainnet";
        string memory assetKey = deployment.asset.symbol();

        // Build chain object
        string memory chainJson = vm.serializeString(chainKey, "globa", getGlobalObject());
        chainJson = vm.serializeString(chainKey, assetKey, serializeAsset(deployment));

        // Wrap under chainKey
        obj = vm.serializeString("root", chainKey, chainJson);

        // save to file
        string memory path = string.concat("broadcast/DeployProduction.s.sol/", vm.toString(block.chainid));
        vm.createDir(path, true);
        vm.writeJson(obj, string.concat(path, "/contracts.json"));
    }

    // Builds the asset JSON from deployment result
    function serializeAsset(DeploymentResult memory deployment) internal returns (string memory assetJson) {
        // objects
        string memory contractsObj = "{}";
        string memory configObj = "{}";

        // keys
        string memory assetKey = deployment.asset.symbol();
        string memory contractsKey = "contracts";
        string memory configKey = "config";

        // serialize config
        configObj = vm.serializeString(configKey, "asset_name", deployment.asset.name());
        configObj = vm.serializeString(configKey, "asset_symbol", deployment.asset.symbol());
        configObj = vm.serializeUint(configKey, "deployment_block", block.number);
        configObj = vm.serializeBytes32(configKey, "domain_separator", deployment.controller.getDomainSeparator());
        configObj = vm.serializeString(configKey, "staked_asset_name", deployment.staking.name());
        configObj = vm.serializeString(configKey, "staked_asset_symbol", deployment.staking.symbol());
        configObj = vm.serializeString(configKey, "version", deployment.controller.version());
        configObj = vm.serializeAddress(configKey, "deployer", broadcaster);

        // serialize contracts
        contractsObj = vm.serializeAddress(contractsKey, "asset_token", address(deployment.asset));
        contractsObj = vm.serializeAddress(contractsKey, "collateral", address(deployment.collateral));
        contractsObj = vm.serializeAddress(contractsKey, "collateral_manager", address(deployment.manager));
        contractsObj = vm.serializeAddress(contractsKey, "controller", address(deployment.controller));
        contractsObj = vm.serializeAddress(contractsKey, "custodian_module", address(deployment.custodian_module));
        contractsObj = vm.serializeAddress(contractsKey, "multicall", address(deployment.multicall));
        contractsObj = vm.serializeAddress(contractsKey, "oracle_adapter", address(deployment.oracle_adapter));
        contractsObj = vm.serializeAddress(contractsKey, "revenue_module", address(deployment.revenue_module));
        contractsObj = vm.serializeAddress(contractsKey, "silo", address(deployment.silo));
        contractsObj = vm.serializeAddress(contractsKey, "staked_asset", address(deployment.staking));
        contractsObj = vm.serializeAddress(contractsKey, "swap_module", address(deployment.swap_module));

        // Build asset object
        vm.serializeString(assetKey, configKey, configObj);
        vm.serializeString(assetKey, contractsKey, contractsObj);
        assetJson = vm.serializeString(
            assetKey, "roles", getRolesObject(address(deployment.multicall), address(deployment.revenue_module))
        );
    }

    function printContracts(DeploymentResult memory deployment) internal view {
        console2.log("\n========================= Domain ============================\n");
        console2.log("domain separator: ");
        console2.logBytes32(deployment.controller.getDomainSeparator());
        console2.log("order typehash: ");
        console2.logBytes32(
            keccak256(
                "Order(uint8 order_type,uint256 nonce,uint256 expiry,address payer,address recipient,address collateral_token,uint256 collateral_amount,uint256 asset_amount)"
            )
        );
        console2.log("\n========================= Contracts =========================\n");
        console2.log("AssetSilo : ", address(deployment.silo));
        console2.log("AssetToken: ", address(deployment.asset));
        console2.log("CollateralManager: ", address(deployment.manager));
        console2.log("Controller: ", address(deployment.controller));
        console2.log("CustodianModule : ", address(deployment.custodian_module));
        console2.log("MultiCall: ", address(deployment.multicall));
        console2.log("OracleAdapter:", address(deployment.oracle_adapter));
        console2.log("RevenueModule : ", address(deployment.revenue_module));
        console2.log("StakedAsset: ", address(deployment.staking));
        console2.log("SwapModule: ", address(deployment.swap_module));
        console2.log("Vault: ", address(deployment.vault));

        console2.log("\n=============================================================\n");
    }
}
