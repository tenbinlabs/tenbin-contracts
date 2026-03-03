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
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {Mock1InchRouter} from "../test/mocks/Mock1InchRouter.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {MockERC4626} from "../test/mocks/MockERC4626.sol";
import {MultiCall} from "../src/MultiCall.sol";
import {RevenueModule} from "../src/RevenueModule.sol";
import {StakedAsset} from "../src/StakedAsset.sol";
import {SwapModule} from "../src/SwapModule.sol";

/// @notice Deploy a mock version of the protocol for testing
contract DeployMock is BaseScript, Config {
    /// @notice Default ratio is 10%
    uint256 constant DEFAULT_RATIO = 2e17;
    /// @notice Default cooldown length for testnet is 180 seconds
    uint128 constant DEFAULT_COOLDOWN_PERIOD = 180 seconds; // TESTNET
    /// @notice Default vesting length for testnet is 1200 seconds
    uint128 constant DEFAULT_VESTING_PERIOD = 1200 seconds; // TESTNET
    /// @notice Default EOA when none are provided in .env
    address constant DEFAULT_EOA = 0x635ECB1700d52a1FbC395c5C92b845A00AF56a38;
    /// @notice 1Inch Aggregation Router V6
    address constant ROUTER_1INCH = 0x111111125421cA6dc452d289314280a0f8842A65;
    /// @notice USDC address
    address constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

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
        address revenue_keeper_role;
        address signer_manager_role;
    }

    /// @notice Config variables set during deployment
    struct DeploymentParameters {
        address multisig;
        address collateral;
        address custodian;
        address signer;
        address vault;
        string assetName;
        string assetSymbol;
        uint256 cooldownPeriod;
        uint256 minSwapPrice;
        uint256 oracleTolerance;
        uint256 ratio;
        uint256 rebalanceCap;
        uint256 swapCap;
        uint256 vestingPeriod;
    }

    /// @notice Contracts deployed by this script
    struct DeploymentResult {
        Controller controller;
        CollateralManager manager;
        AssetToken asset;
        MultiCall multicall;
        StakedAsset staking;
        SwapModule swapModule;
        IERC20 collateral;
        IERC4626 vault;
        Mock1InchRouter router;
        RevenueModule revenueModule;
        AssetSilo silo;
        CustodianModule custodianModule;
    }

    function loadConfig() internal {
        if (block.chainid == 1) _loadConfig("./config/mainnet.toml", false);
        if (block.chainid == 11155111) _loadConfig("./config/sepolia.toml", false);
        if (block.chainid == 31337) _loadConfig("./config/local.toml", false);

        // load roles from config file
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
        roles.signer_manager_role = config.get("signer_manager_role").toAddress();

        // load parameters from config file
        params.collateral = USDC_ADDRESS;
        params.custodian = config.get("custodian").toAddress();
        params.multisig = config.get("multisig").toAddress();
        params.vault = config.get("vault").toAddress();

        if (block.chainid == 11155111 || block.chainid == 31337) {
            params.signer = config.get("signer").toAddress();
        }
    }

    function run() public returns (DeploymentResult memory deployment) {
        loadConfig();
        deployment = deploy();
    }

    function deploy() public broadcast returns (DeploymentResult memory deployment) {
        // load more config
        string memory assetName = config.get("asset_name").toString();
        string memory assetSymbol = config.get("asset_symbol").toString();
        string memory stakedAssetName = string.concat("Staked ", assetName);
        string memory stakedAssetSymbol = string.concat("s", assetSymbol);

        // deploy contracts
        deployment.asset = new AssetToken{salt: SALT}(assetName, assetSymbol, broadcaster);
        deployment.custodianModule = new CustodianModule(broadcaster);
        deployment.controller = new Controller{salt: SALT}(
            address(deployment.asset), DEFAULT_RATIO, address(deployment.custodianModule), broadcaster
        );
        deployment.multicall = new MultiCall{salt: SALT}(broadcaster);

        // deploy manager behind a proxy
        address managerImplementation = address(new CollateralManager{salt: SALT}());
        bytes memory data =
            abi.encodeWithSelector(CollateralManager.initialize.selector, address(deployment.controller), broadcaster);
        ERC1967Proxy proxy = new ERC1967Proxy{salt: SALT}(managerImplementation, data);
        deployment.manager = CollateralManager(address(proxy));

        // deploy staking behind a proxy
        address stakingImplementation = address(new StakedAsset{salt: SALT}());
        data = abi.encodeWithSelector(
            StakedAsset.initialize.selector, stakedAssetName, stakedAssetSymbol, deployment.asset, broadcaster
        );
        proxy = new ERC1967Proxy{salt: SALT}(stakingImplementation, data);
        deployment.staking = StakedAsset(address(proxy));
        deployment.silo = deployment.staking.silo();

        // deploy remaining contracts
        deployment.router = new Mock1InchRouter();
        deployment.swapModule =
            new SwapModule{salt: SALT}(address(deployment.manager), address(deployment.router), broadcaster);
        deployment.revenueModule = new RevenueModule{salt: SALT}(
            address(deployment.manager),
            address(deployment.staking),
            broadcaster,
            address(deployment.controller),
            address(deployment.asset),
            address(params.multisig)
        );

        // use mock USDC for testnet
        if (block.chainid == 31337 || block.chainid == 11155111) {
            deployment.collateral = new MockERC20{salt: SALT}("Mock USDC", "USDC", 6);
            deployment.vault = new MockERC4626{salt: SALT}("Mock USDC Vault", "vUSDC", deployment.collateral);
        } else {
            deployment.collateral = IERC20(USDC_ADDRESS);
            deployment.vault = IERC4626(params.vault);
        }

        console2.log("\n========================= Accounts ==========================\n");
        console2.log("broadcaster address: ", broadcaster);
        console2.log("minter address: ", roles.minter_role);
        console2.log("signer address: ", params.signer);

        // set permissions
        deployment.asset.setMinter(address(deployment.controller));
        deployment.controller.grantRole(ADMIN_ROLE, roles.admin_role);
        deployment.controller.grantRole(MINTER_ROLE, roles.minter_role);
        deployment.controller.grantRole(MINTER_ROLE, address(deployment.multicall));
        deployment.controller.grantRole(GATEKEEPER_ROLE, roles.gatekeeper_role);
        deployment.controller.grantRole(SIGNER_MANAGER_ROLE, roles.signer_manager_role);
        deployment.controller.grantRole(RESTRICTER_ROLE, roles.restricter_role);
        deployment.manager.grantRole(ADMIN_ROLE, roles.admin_role);
        deployment.manager.grantRole(CURATOR_ROLE, roles.curator_role);
        deployment.manager.grantRole(REBALANCER_ROLE, roles.rebalancer_role);
        deployment.manager.grantRole(CAP_ADJUSTER_ROLE, roles.cap_adjuster_role);
        deployment.manager.grantRole(CURATOR_ROLE, address(deployment.multicall));
        deployment.manager.grantRole(GATEKEEPER_ROLE, roles.gatekeeper_role);
        deployment.multicall.grantRole(MULTICALLER_ROLE, roles.multicaller_role);
        deployment.staking.grantRole(ADMIN_ROLE, roles.admin_role);
        deployment.staking.grantRole(REWARDER_ROLE, params.multisig);
        deployment.staking.grantRole(REWARDER_ROLE, address(deployment.revenueModule));
        deployment.staking.grantRole(RESTRICTER_ROLE, roles.restricter_role);
        deployment.revenueModule.grantRole(REVENUE_KEEPER_ROLE, roles.revenue_keeper_role);
        deployment.custodianModule.grantRole(CUSTODIAN_KEEPER_ROLE, roles.custodian_keeper_role);

        // configuration
        deployment.controller.grantRole(ADMIN_ROLE, broadcaster);
        deployment.controller.grantRole(SIGNER_MANAGER_ROLE, broadcaster);
        deployment.controller.setSignerStatus(params.signer, true);
        deployment.manager.grantRole(ADMIN_ROLE, broadcaster);
        deployment.manager.addCollateral(address(deployment.collateral), address(deployment.vault));
        deployment.manager.setSwapModule(address(deployment.swapModule));
        deployment.manager.setRevenueModule(address(deployment.revenueModule));
        deployment.controller.setIsCollateral(address(deployment.collateral), true);
        deployment.controller.setManager(address(deployment.manager));
        deployment.staking.grantRole(ADMIN_ROLE, broadcaster);
        deployment.staking.setCooldownPeriod(DEFAULT_COOLDOWN_PERIOD);
        deployment.staking.setVestingPeriod(DEFAULT_VESTING_PERIOD);
        deployment.custodianModule.setCustodianStatus(params.custodian, true);

        // transfer ownership
        deployment.manager.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.controller.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.multicall.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.staking.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.revenueModule.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.custodianModule.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.asset.transferOwnership(roles.default_admin_role);

        // additionally allow multisig to manage ownership on testnet
        deployment.manager.grantRole(DEFAULT_ADMIN_ROLE, params.multisig);
        deployment.controller.grantRole(DEFAULT_ADMIN_ROLE, params.multisig);
        deployment.multicall.grantRole(DEFAULT_ADMIN_ROLE, params.multisig);
        deployment.staking.grantRole(DEFAULT_ADMIN_ROLE, params.multisig);
        deployment.revenueModule.grantRole(DEFAULT_ADMIN_ROLE, params.multisig);
        deployment.custodianModule.grantRole(DEFAULT_ADMIN_ROLE, params.multisig);

        // renounce deployer roles (except for local dev)
        if (block.chainid != 31337) {
            deployment.controller.revokeRole(ADMIN_ROLE, broadcaster);
            deployment.controller.revokeRole(SIGNER_MANAGER_ROLE, broadcaster);
            deployment.manager.revokeRole(ADMIN_ROLE, broadcaster);
            deployment.manager.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
            deployment.controller.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
            deployment.multicall.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
            deployment.staking.revokeRole(ADMIN_ROLE, broadcaster);
            deployment.staking.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
            deployment.revenueModule.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
            deployment.custodianModule.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
        }

        // mint some tokens to deployer (test network only)
        if (block.chainid == 31337 || block.chainid == 11155111) {
            MockERC20(address(deployment.collateral)).mint(broadcaster, 1_000_000_000_000e6);
            deployment.collateral.approve(address(deployment.controller), 1_000_000_000_000e6);
        }

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
        string memory key = deployment.asset.name();
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
        contractsObj = vm.serializeAddress(contractsKey, "custodian_module", address(deployment.custodianModule));
        contractsObj = vm.serializeAddress(contractsKey, "multicall", address(deployment.multicall));
        contractsObj = vm.serializeAddress(contractsKey, "revenue_module", address(deployment.revenueModule));
        contractsObj = vm.serializeAddress(contractsKey, "silo", address(deployment.silo));
        contractsObj = vm.serializeAddress(contractsKey, "staked_asset", address(deployment.staking));
        contractsObj = vm.serializeAddress(contractsKey, "swap_module", address(deployment.swapModule));

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
        rolesObj = vm.serializeAddress(rolesKey, "rewarder_role", address(deployment.revenueModule));
        rolesObj = vm.serializeAddress(rolesKey, "signer", params.signer);
        rolesObj = vm.serializeAddress(rolesKey, "signer_manager_role", roles.signer_manager_role);

        // serialize json file from objects
        obj = vm.serializeString(key, configKey, configObj);
        obj = vm.serializeString(key, contractsKey, contractsObj);
        obj = vm.serializeString(key, rolesKey, rolesObj);

        // save to file
        string memory path = string.concat("broadcast/DeployMock.s.sol/", vm.toString(block.chainid));
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
        console2.log("Controller: ", address(deployment.controller));
        console2.log("CollateralManager: ", address(deployment.manager));
        console2.log("AssetToken: ", address(deployment.asset));
        console2.log("MultiCall: ", address(deployment.multicall));
        console2.log("StakedAsset: ", address(deployment.staking));
        console2.log("AssetSilo : ", address(deployment.silo));
        console2.log("SwapModule: ", address(deployment.swapModule));
        console2.log("MockERC20: ", address(deployment.collateral));
        console2.log("MockERC4626: ", address(deployment.vault));
        console2.log("Mock1InchRouter: ", address(deployment.router));
        console2.log("RevenueModule : ", address(deployment.revenueModule));
        console2.log("CustodianModule : ", address(deployment.custodianModule));
        console2.log("\n=============================================================\n");
    }

    // mark this as a test contract
    function test() public {}
}
