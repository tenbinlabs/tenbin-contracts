// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {DeployBase} from "./DeployBase.s.sol";
import {AssetSilo} from "../src/AssetSilo.sol";
import {AssetToken} from "../src/AssetToken.sol";
import {CollateralManager} from "../src/CollateralManager.sol";
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

/// @notice Deploy a current version of the protocol for testing in a mock environment
contract DeployDevelopmentMock is DeployBase {
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

    /// @notice Contracts deployed by this script
    struct DeploymentResult {
        Controller controller;
        CollateralManager manager;
        AssetToken asset;
        MultiCall multicall;
        StakedAsset staking;
        SwapModule swap_module;
        IERC20 collateral;
        IERC4626 vault;
        Mock1InchRouter one_inch_router;
        RevenueModule revenue_module;
        AssetSilo silo;
        CustodianModule custodian_module;
    }

    /// @dev The version for this deployment
    function getVersion() internal pure override returns (string memory) {
        return "1.1.1";
    }

    function run() public virtual returns (DeploymentResult memory deployment) {
        string memory configDir;
        if (block.chainid == 1) configDir = "./config/mainnet/tgld/tgld.toml";
        if (block.chainid == 11155111) configDir = "./config/sepolia/sepolia.toml";
        if (block.chainid == 31337) configDir = "./config/local/local.toml";
        loadConfig(configDir);
        deployment = deploy();
    }

    function deploy() public broadcast returns (DeploymentResult memory deployment) {
        // load config
        deployment.collateral = IERC20(params.collateral);
        deployment.vault = IERC4626(params.vault);

        // deploy asset
        deployment.asset = new AssetToken{salt: SALT}(params.asset_name, params.asset_symbol, broadcaster);

        // deploy staked asset
        address stakingImplementation = address(new StakedAsset{salt: SALT}());
        bytes memory data = abi.encodeWithSelector(
            StakedAsset.initialize.selector,
            params.staked_asset_name,
            params.staked_asset_symbol,
            deployment.asset,
            broadcaster,
            0,
            address(0)
        );
        ERC1967Proxy proxy = new ERC1967Proxy{salt: SALT}(stakingImplementation, data);
        deployment.staking = StakedAsset(address(proxy));
        deployment.silo = deployment.staking.silo();

        deployment.custodian_module = new CustodianModule(broadcaster);
        deployment.controller = new Controller{salt: SALT}(
            address(deployment.asset),
            address(deployment.staking),
            DEFAULT_RATIO,
            address(deployment.custodian_module),
            broadcaster
        );
        deployment.multicall = new MultiCall{salt: SALT}(broadcaster);

        // deploy manager behind a proxy
        address managerImplementation = address(new CollateralManager{salt: SALT}());
        data =
            abi.encodeWithSelector(CollateralManager.initialize.selector, address(deployment.controller), broadcaster);
        proxy = new ERC1967Proxy{salt: SALT}(managerImplementation, data);
        deployment.manager = CollateralManager(address(proxy));

        // deploy remaining contracts
        deployment.one_inch_router = new Mock1InchRouter();
        deployment.swap_module =
            new SwapModule{salt: SALT}(address(deployment.manager), address(deployment.one_inch_router), broadcaster);
        deployment.revenue_module = new RevenueModule{salt: SALT}(
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
        }

        printAccounts();

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
        deployment.manager.grantRole(CURATOR_ROLE, address(deployment.controller));
        deployment.manager.grantRole(GATEKEEPER_ROLE, roles.gatekeeper_role);
        deployment.multicall.grantRole(MULTICALLER_ROLE, roles.multicaller_role);
        deployment.staking.grantRole(ADMIN_ROLE, roles.admin_role);
        deployment.staking.grantRole(REWARDER_ROLE, params.multisig);
        deployment.staking.grantRole(REWARDER_ROLE, address(deployment.revenue_module));
        deployment.staking.grantRole(RESTRICTER_ROLE, roles.restricter_role);
        deployment.staking.grantRole(CAP_ADJUSTER_ROLE, roles.cap_adjuster_role);
        deployment.staking.grantRole(INSTANT_UNSTAKER_ROLE, address(deployment.controller));
        deployment.revenue_module.grantRole(REVENUE_KEEPER_ROLE, roles.revenue_keeper_role);
        deployment.custodian_module.grantRole(CUSTODIAN_KEEPER_ROLE, roles.custodian_keeper_role);

        // configuration
        deployment.controller.grantRole(ADMIN_ROLE, broadcaster);
        deployment.controller.grantRole(SIGNER_MANAGER_ROLE, broadcaster);
        deployment.controller.setSignerStatus(params.signer, true);
        deployment.manager.grantRole(ADMIN_ROLE, broadcaster);
        deployment.manager.addCollateral(address(deployment.collateral), address(deployment.vault));
        deployment.manager.setSwapModule(address(deployment.swap_module));
        deployment.manager.setRevenueModule(address(deployment.revenue_module));
        deployment.controller.setIsCollateral(address(deployment.collateral), true);
        deployment.controller.setManager(address(deployment.manager));
        deployment.staking.grantRole(ADMIN_ROLE, broadcaster);
        if (block.chainid != 1) {
            // TODO Create a separation ENG-1261
            deployment.staking.setCooldownPeriod(DEFAULT_COOLDOWN_PERIOD);
            deployment.staking.setVestingPeriod(DEFAULT_VESTING_PERIOD);
        } else {
            deployment.staking.setCooldownPeriod(config.get("cooldown_period").toUint256());
            deployment.staking.setVestingPeriod(config.get("vesting_period").toUint128());
        }

        deployment.custodian_module.setCustodianStatus(params.custodian, true);

        // transfer ownership
        deployment.manager.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.controller.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.multicall.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.staking.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.revenue_module.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.custodian_module.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.asset.transferOwnership(roles.default_admin_role);

        // additionally allow multisig to manage ownership on testnet
        deployment.manager.grantRole(DEFAULT_ADMIN_ROLE, params.multisig);
        deployment.controller.grantRole(DEFAULT_ADMIN_ROLE, params.multisig);
        deployment.multicall.grantRole(DEFAULT_ADMIN_ROLE, params.multisig);
        deployment.staking.grantRole(DEFAULT_ADMIN_ROLE, params.multisig);
        deployment.revenue_module.grantRole(DEFAULT_ADMIN_ROLE, params.multisig);
        deployment.custodian_module.grantRole(DEFAULT_ADMIN_ROLE, params.multisig);

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
            deployment.revenue_module.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
            deployment.custodian_module.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
        }

        // mint some tokens to deployer (test network only)
        if (block.chainid == 31337 || block.chainid == 11155111) {
            MockERC20(address(deployment.collateral)).mint(broadcaster, 1_000_000_000_000e6);
            deployment.collateral.approve(address(deployment.controller), 1_000_000_000_000e6);
        }

        // Serialize json and print contracts
        serialize(deployment);
        printContracts(deployment);
        console2.log("SERIALIZATION SUCCESSFUL.\n==========================");
        console2.log("contracts.json saved to: broadcast/DeployDevelopment.s.sol/\n");
        printLogo();
    }

    // Given a deployment result, serialize the JSON
    function serialize(DeploymentResult memory deployment) internal {
        console2.log("\nSerializing json...\n");
        // objects
        string memory obj = "{}";

        // keys
        string memory chainKey;
        string memory contractsObj = "{}";
        string memory configObj = "{}";

        // keys
        string memory assetKey = deployment.asset.symbol();
        string memory contractsKey = "contracts";
        string memory configKey = "config";

        if (block.chainid == 1) chainKey = "mainnet";
        else if (block.chainid == 11155111) chainKey = "sepolia";
        else if (block.chainid == 31337) chainKey = "localhost";

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
        contractsObj = vm.serializeAddress(contractsKey, "revenue_module", address(deployment.revenue_module));
        contractsObj = vm.serializeAddress(contractsKey, "silo", address(deployment.silo));
        contractsObj = vm.serializeAddress(contractsKey, "staked_asset", address(deployment.staking));
        contractsObj = vm.serializeAddress(contractsKey, "swap_module", address(deployment.swap_module));

        // Build asset object (builder id: "asset")
        vm.serializeString(assetKey, configKey, configObj);
        vm.serializeString(assetKey, contractsKey, contractsObj);
        string memory assetJson = vm.serializeString(
            assetKey, "roles", getRolesObject(address(deployment.multicall), address(deployment.revenue_module))
        );

        // Build chain object (builder id: "chain")
        string memory chainJson = vm.serializeString(chainKey, "global", getGlobalObject());
        chainJson = vm.serializeString(chainKey, assetKey, assetJson);

        // Wrap under chainKey (builder id: "root")
        obj = vm.serializeString("root", chainKey, chainJson);

        // save to file
        // writes to broadcast/DeployDevelopment to keep consistent with back end deployment
        string memory path = string.concat("broadcast/DeployDevelopment.s.sol/", vm.toString(block.chainid));
        vm.createDir(path, true);
        vm.writeJson(obj, string.concat(path, "/contracts.json"));
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
        console2.log("SwapModule: ", address(deployment.swap_module));
        console2.log("MockERC20: ", address(deployment.collateral));
        console2.log("MockERC4626: ", address(deployment.vault));
        console2.log("Mock1InchRouter: ", address(deployment.one_inch_router));
        console2.log("RevenueModule : ", address(deployment.revenue_module));
        console2.log("CustodianModule : ", address(deployment.custodian_module));
        console2.log("\n=============================================================\n");
    }
}
