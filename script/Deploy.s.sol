// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetSilo} from "../src/AssetSilo.sol";
import {AssetToken} from "../src/AssetToken.sol";
import {BaseScript} from "./Base.s.sol";
import {CollateralManager} from "../src/CollateralManager.sol";
import {Config} from "forge-std/Config.sol";
import {console2} from "forge-std/console2.sol";
import {Controller} from "../src/Controller.sol";
import {CustodianModule} from "../src/CustodianModule.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {GoldOracleAdapter} from "../src/oracle/GoldOracleAdapter.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IOracleAdapter} from "../src/interface/IOracleAdapter.sol";
import {MultiCall} from "../src/MultiCall.sol";
import {RevenueModule} from "../src/RevenueModule.sol";
import {StakedAsset} from "../src/StakedAsset.sol";
import {SwapModule} from "../src/SwapModule.sol";

/// @notice Deploy and configure the protocol using config/*.toml file
contract Deploy is BaseScript, Config {
    /// @notice Roles loaded from config file
    RolesParameters internal roles;

    /// @notice Parameters loaded from config file
    DeploymentParameters internal params;

    /// @notice Roles set during deployment
    struct RolesParameters {
        address admin_role;
        address cap_adjuster_role;
        address curator_role;
        address custodian_keeper_role;
        address default_admin_role;
        address gatekeeper_role;
        address minter_role;
        address multicaller_role;
        address rebalancer_role;
        address restricter_role;
        address rewarder_role;
        address revenue_keeper_role;
        address signer_manager_role;
    }

    /// @notice Config variables set during deployment
    struct DeploymentParameters {
        address multisig;
        address collateral;
        address custodian;
        address one_inch_router;
        address oracle;
        address vault;
        string asset_name;
        string asset_symbol;
        string staked_asset_name;
        string staked_asset_symbol;
        uint256 cooldown_period;
        uint256 min_swap_price;
        uint256 oracle_tolerance;
        uint256 ratio;
        uint256 rebalance_cap;
        uint256 swap_cap;
        uint256 vesting_period;
    }

    /// @notice Contracts deployed by this script
    struct DeploymentResult {
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

    function loadConfig() internal {
        if (block.chainid == 1) _loadConfig("./config/mainnet.toml", false);
        if (block.chainid == 11155111) _loadConfig("./config/sepolia.toml", false);
        if (block.chainid == 31337) _loadConfig("./config/local.toml", false);

        // load roles
        roles.admin_role = config.get("admin_role").toAddress();
        roles.cap_adjuster_role = config.get("cap_adjuster_role").toAddress();
        roles.curator_role = config.get("curator_role").toAddress();
        roles.custodian_keeper_role = config.get("custodian_keeper_role").toAddress();
        roles.gatekeeper_role = config.get("gatekeeper_role").toAddress();
        roles.minter_role = config.get("minter_role").toAddress();
        roles.multicaller_role = config.get("multicaller_role").toAddress();
        roles.default_admin_role = config.get("default_admin_role").toAddress();
        roles.rebalancer_role = config.get("rebalancer_role").toAddress();
        roles.restricter_role = config.get("restricter_role").toAddress();
        roles.revenue_keeper_role = config.get("revenue_keeper_role").toAddress();
        roles.rewarder_role = config.get("rewarder_role").toAddress();
        roles.signer_manager_role = config.get("signer_manager_role").toAddress();

        // load parameters
        params.collateral = config.get("collateral").toAddress();
        params.custodian = config.get("custodian").toAddress();
        params.multisig = config.get("multisig").toAddress();
        params.oracle = config.get("oracle").toAddress();
        params.vault = config.get("vault").toAddress();

        // load strings
        params.asset_name = config.get("asset_name").toString();
        params.asset_symbol = config.get("asset_symbol").toString();
        params.staked_asset_name = config.get("staked_asset_name").toString();
        params.staked_asset_symbol = config.get("staked_asset_symbol").toString();

        // load uint
        params.cooldown_period = config.get("cooldown_period").toUint256();
        params.min_swap_price = config.get("min_swap_price").toUint256();
        params.oracle_tolerance = config.get("oracle_tolerance").toUint256();
        params.ratio = config.get("ratio").toUint256();
        params.rebalance_cap = config.get("rebalance_cap").toUint256();
        params.swap_cap = config.get("swap_cap").toUint256();
        params.vesting_period = config.get("vesting_period").toUint256();
    }

    function run() public returns (DeploymentResult memory deployment) {
        loadConfig();
        deployment = deploy();
    }

    function deploy() public broadcast returns (DeploymentResult memory deployment) {
        console2.log("\n========================= Accounts ==========================\n");
        console2.log("broadcaster address: ", broadcaster);
        console2.log("minter address: ", roles.minter_role);

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
            broadcaster
        );
        proxy = new ERC1967Proxy{salt: SALT}(stakingImplementation, data);
        deployment.staking = StakedAsset(address(proxy));
        deployment.silo = deployment.staking.silo();

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
        deployment.oracle_adapter = new GoldOracleAdapter(params.oracle);

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
        deployment.manager.grantRole(CAP_ADJUSTER_ROLE, broadcaster);
        deployment.manager.grantRole(CURATOR_ROLE, address(deployment.multicall));
        deployment.manager.grantRole(GATEKEEPER_ROLE, roles.gatekeeper_role);

        // set multicall permissions
        deployment.multicall.grantRole(MULTICALLER_ROLE, roles.multicaller_role);

        // set staking permissions
        deployment.staking.grantRole(ADMIN_ROLE, roles.admin_role);
        deployment.staking.grantRole(REWARDER_ROLE, roles.rewarder_role);
        deployment.staking.grantRole(REWARDER_ROLE, address(deployment.revenue_module));
        deployment.staking.grantRole(RESTRICTER_ROLE, roles.restricter_role);

        // set module permissions
        deployment.revenue_module.grantRole(ADMIN_ROLE, roles.admin_role);
        deployment.revenue_module.grantRole(REVENUE_KEEPER_ROLE, roles.revenue_keeper_role);
        deployment.custodian_module.grantRole(CUSTODIAN_KEEPER_ROLE, roles.custodian_keeper_role);

        // give temporary permissions to broadcaster
        deployment.controller.grantRole(ADMIN_ROLE, broadcaster);
        deployment.controller.grantRole(SIGNER_MANAGER_ROLE, broadcaster);
        deployment.manager.grantRole(ADMIN_ROLE, broadcaster);
        deployment.staking.grantRole(ADMIN_ROLE, broadcaster);

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
    function serialize(DeploymentResult memory deployment) internal returns (string memory obj) {
        console2.log("\nSerializing json...\n");
        // objects
        obj = "{}";
        string memory rolesObj = "{}";
        string memory contractsObj = "{}";
        string memory configObj = "{}";

        // keys
        string memory key = deployment.asset.symbol();
        string memory rolesKey = "roles";
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

        // serialize contracts
        contractsObj = vm.serializeAddress(contractsKey, "asset_token", address(deployment.asset));
        contractsObj = vm.serializeAddress(contractsKey, "collateral", address(deployment.collateral));
        contractsObj = vm.serializeAddress(contractsKey, "collateral_manager", address(deployment.manager));
        contractsObj = vm.serializeAddress(contractsKey, "controller", address(deployment.controller));
        contractsObj = vm.serializeAddress(contractsKey, "custodian_module", address(deployment.custodian_module));
        contractsObj = vm.serializeAddress(contractsKey, "multicall", address(deployment.multicall));
        contractsObj = vm.serializeAddress(contractsKey, "revenue_module", address(deployment.revenue_module));
        contractsObj = vm.serializeAddress(contractsKey, "silo", address(deployment.silo));
        contractsObj = vm.serializeAddress(contractsKey, "staked_asset", address(deployment.staking));
        contractsObj = vm.serializeAddress(contractsKey, "swap_module", address(deployment.swap_module));

        // serialize accounts
        rolesObj = vm.serializeAddress(rolesKey, "admin_role", roles.admin_role);
        rolesObj = vm.serializeAddress(rolesKey, "cap_adjuster_role", roles.cap_adjuster_role);
        rolesObj = vm.serializeAddress(rolesKey, "curator_role", roles.curator_role);
        rolesObj = vm.serializeAddress(rolesKey, "custodian", params.custodian);
        rolesObj = vm.serializeAddress(rolesKey, "custodian_keeper_role", roles.custodian_keeper_role);
        rolesObj = vm.serializeAddress(rolesKey, "deployer", broadcaster);
        rolesObj = vm.serializeAddress(rolesKey, "gatekeeper_role", roles.gatekeeper_role);
        rolesObj = vm.serializeAddress(rolesKey, "minter_role", roles.minter_role);
        rolesObj = vm.serializeAddress(rolesKey, "multicaller_role", roles.multicaller_role);
        rolesObj = vm.serializeAddress(rolesKey, "multisig", params.multisig);
        rolesObj = vm.serializeAddress(rolesKey, "default_admin_role", roles.default_admin_role);
        rolesObj = vm.serializeAddress(rolesKey, "rebalancer_role", roles.rebalancer_role);
        rolesObj = vm.serializeAddress(rolesKey, "restricter_role", roles.restricter_role);
        rolesObj = vm.serializeAddress(rolesKey, "revenue_keeper_role", roles.revenue_keeper_role);
        rolesObj = vm.serializeAddress(rolesKey, "rewarder_role", roles.rewarder_role);
        rolesObj = vm.serializeAddress(rolesKey, "signer_manager_role", roles.signer_manager_role);

        // serialize json file from objects
        obj = vm.serializeString(key, configKey, configObj);
        obj = vm.serializeString(key, contractsKey, contractsObj);
        obj = vm.serializeString(key, rolesKey, rolesObj);

        // save to file
        string memory path = string.concat("broadcast/Deploy.s.sol/", vm.toString(block.chainid));
        vm.createDir(path, true);
        vm.writeJson(obj, string.concat(path, "/deployments.json"));
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
        console2.log("StakedAsset: ", address(deployment.staking));
        console2.log("Vault: ", address(deployment.vault));
        console2.log("RevenueModule : ", address(deployment.revenue_module));
        console2.log("SwapModule: ", address(deployment.swap_module));

        console2.log("\n=============================================================\n");
    }

    // mark this as a test contract
    function test() public {}
}
