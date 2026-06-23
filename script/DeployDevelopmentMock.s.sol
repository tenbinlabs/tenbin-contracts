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
import {MockDistributor} from "../test/mocks/MockDistributor.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {MockERC4626} from "../test/mocks/MockERC4626.sol";
import {MultiCall} from "../src/MultiCall.sol";
import {RevenueModule} from "../src/RevenueModule.sol";
import {StakedAsset} from "../src/StakedAsset.sol";
import {SwapModule} from "../src/SwapModule.sol";

/// @notice Deploy the current version of the protocol for testing in a mock environment
/// FOUNDRY_PROFILE=production forge script script/DeployDevelopmentMock.s.sol $CONFIG_DIR --rpc-url $MAINNET_RPC_URL --private-key $BROADCASTER_KEY --verify --verifier etherscan --verifier-api-key $ETHERSCAN_API_KEY --slow
contract DeployDevelopmentMock is DeployBase {
    /// @notice Contracts deployed by this script
    struct DeploymentResult {
        address broadcaster;
        AssetSilo silo;
        Controller controller;
        CollateralManager manager;
        CustodianModule custodian_module;
        AssetToken asset;
        MultiCall multicall;
        StakedAsset staked_asset;
        SwapModule swap_module;
        IERC20 collateral;
        IERC4626 vault;
        Mock1InchRouter one_inch_router;
        RevenueModule revenue_module;
    }

    /// @dev The version for this deployment
    function getVersion() internal pure override returns (string memory) {
        return "1.4.3";
    }

    // run and load config dir from CI
    function run(string memory configDir) public virtual returns (DeploymentResult memory deployment) {
        if (bytes(configDir).length == 0) {
            // default config for testing
            if (block.chainid == 1) configDir = "./config/mainnet/tgld/tgld.toml";
            else if (block.chainid == 11155111) configDir = "./config/sepolia/tgld/tgld_sepolia.toml";
            else if (block.chainid == 31337) configDir = "./config/local/local.toml";
            else revert("chain not supported");
        }

        loadConfig(configDir);
        deployment = deploy();
    }

    function deploy() public broadcast returns (DeploymentResult memory deployment) {
        // update salt and cache broadcaster
        SALT = bytes32(abi.encodePacked(constructCreate2Salt(), params.asset_name));
        deployment.broadcaster = broadcaster;

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
            broadcaster
        );
        ERC1967Proxy proxy = new ERC1967Proxy{salt: SALT}(stakingImplementation, data);
        deployment.staked_asset = StakedAsset(address(proxy));
        deployment.silo = deployment.staked_asset.silo();

        deployment.custodian_module = new CustodianModule(broadcaster);
        deployment.controller = new Controller{salt: SALT}(
            address(deployment.asset),
            address(deployment.staked_asset),
            params.ratio,
            address(deployment.custodian_module),
            broadcaster
        );

        require(stringMatches(deployment.controller.version(), getVersion()), "controller version mismatch");

        // deploy multicall
        deployment.multicall = new MultiCall{salt: SALT}(broadcaster);

        // deploy manager behind a proxy
        address managerImplementation = address(new CollateralManager{salt: SALT}());
        data =
            abi.encodeWithSelector(CollateralManager.initialize.selector, address(deployment.controller), broadcaster);
        proxy = new ERC1967Proxy{salt: SALT}(managerImplementation, data);
        deployment.manager = CollateralManager(address(proxy));

        // deploy swap module
        deployment.one_inch_router = new Mock1InchRouter();
        deployment.swap_module =
            new SwapModule{salt: SALT}(address(deployment.manager), address(deployment.one_inch_router), broadcaster);

        // deploy revenue module
        deployment.revenue_module = new RevenueModule{salt: SALT}(
            address(deployment.manager),
            address(deployment.staked_asset),
            broadcaster,
            address(deployment.controller),
            address(deployment.asset),
            address(params.multisig)
        );

        // testnet and mock options
        if (block.chainid == 11155111) {
            // sepolia: mint mock ERC20 tokens to broadcaster
            require(address(deployment.collateral) != address(0), "invalid collateral");
            MockERC20(address(deployment.collateral)).mint(broadcaster, 1e6);
            params.signer = config.get("signer").toAddress();
            deployment.manager.setDistributor(address(new MockDistributor()));
        } else if (block.chainid == 31337) {
            // local dev: use mock token and vault
            deployment.collateral = new MockERC20{salt: SALT}("Mock USDC", "USDC", 6);
            deployment.vault = new MockERC4626{salt: SALT}("Mock USDC Vault", "vUSDC", deployment.collateral);

            // perform dead deposit
            MockERC20(address(deployment.collateral)).mint(broadcaster, 1e6);
            deployment.collateral.approve(address(deployment.vault), 1e6);
            deployment.vault.deposit(1e6, address(0xDEAD));
            params.signer = config.get("signer").toAddress();
            deployment.manager.setDistributor(address(new MockDistributor()));
        } else {
            deployment.manager.setDistributor(DISTRIBUTOR);
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
        deployment.manager.setClaimRecipient(REWARD_RECIPIENT, address(0));
        deployment.multicall.grantRole(MULTICALLER_ROLE, roles.multicaller_role);
        deployment.staked_asset.grantRole(ADMIN_ROLE, roles.admin_role);
        deployment.staked_asset.grantRole(REWARDER_ROLE, params.multisig);
        deployment.staked_asset.grantRole(REWARDER_ROLE, address(deployment.revenue_module));
        deployment.staked_asset.grantRole(RESTRICTER_ROLE, roles.restricter_role);
        deployment.staked_asset.grantRole(CAP_ADJUSTER_ROLE, roles.cap_adjuster_role);
        deployment.staked_asset.grantRole(INSTANT_UNSTAKER_ROLE, address(deployment.controller));
        deployment.revenue_module.grantRole(REVENUE_KEEPER_ROLE, roles.revenue_keeper_role);
        deployment.custodian_module.grantRole(CUSTODIAN_KEEPER_ROLE, roles.custodian_keeper_role);

        // temporarily grant roles to broadcaster
        deployment.controller.grantRole(ADMIN_ROLE, broadcaster);
        deployment.controller.grantRole(SIGNER_MANAGER_ROLE, broadcaster);
        deployment.manager.grantRole(ADMIN_ROLE, broadcaster);
        deployment.staked_asset.grantRole(ADMIN_ROLE, broadcaster);
        deployment.staked_asset.grantRole(CAP_ADJUSTER_ROLE, broadcaster);

        // configure controller
        deployment.controller.setSignerStatus(params.signer, true);
        deployment.controller.setIsCollateral(address(deployment.collateral), true);
        deployment.controller.setManager(address(deployment.manager));
        deployment.controller.setBlockMintLimit(params.mint_limit);
        deployment.controller.setBlockRedeemLimit(params.redeem_limit);

        // configure manager
        deployment.manager.addCollateral(address(deployment.collateral), address(deployment.vault));
        deployment.manager.setSwapModule(address(deployment.swap_module));
        deployment.manager.setRevenueModule(address(deployment.revenue_module));

        // configure staking
        deployment.staked_asset.setCooldownPeriod(params.cooldown_period);
        deployment.staked_asset.setVestingPeriod(params.vesting_period);
        deployment.staked_asset.setInstantUnstakeCap(params.instant_unstake_cap);

        // add custodian
        deployment.custodian_module.setCustodianStatus(params.custodian, true);

        // transfer ownership
        deployment.manager.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.controller.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.multicall.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.staked_asset.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.revenue_module.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.custodian_module.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.asset.transferOwnership(roles.default_admin_role);

        // additionally allow multisig to manage ownership on testnet
        deployment.manager.grantRole(DEFAULT_ADMIN_ROLE, params.multisig);
        deployment.controller.grantRole(DEFAULT_ADMIN_ROLE, params.multisig);
        deployment.multicall.grantRole(DEFAULT_ADMIN_ROLE, params.multisig);
        deployment.staked_asset.grantRole(DEFAULT_ADMIN_ROLE, params.multisig);
        deployment.revenue_module.grantRole(DEFAULT_ADMIN_ROLE, params.multisig);
        deployment.custodian_module.grantRole(DEFAULT_ADMIN_ROLE, params.multisig);

        // perform testnet and mock options
        if (block.chainid == 31337 || block.chainid == 11155111) {
            MockERC20(address(deployment.collateral)).mint(broadcaster, 1_000_000_000_000e6);
            deployment.collateral.approve(address(deployment.controller), 1_000_000_000_000e6);
            deployment.controller.setSignerStatus(params.signer, true);
        }

        // renounce deployer roles (except for local dev)
        if (block.chainid != 31337) {
            deployment.controller.revokeRole(ADMIN_ROLE, broadcaster);
            deployment.controller.revokeRole(SIGNER_MANAGER_ROLE, broadcaster);
            deployment.manager.revokeRole(ADMIN_ROLE, broadcaster);
            deployment.manager.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
            deployment.controller.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
            deployment.multicall.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
            deployment.staked_asset.revokeRole(ADMIN_ROLE, broadcaster);
            deployment.staked_asset.revokeRole(CAP_ADJUSTER_ROLE, broadcaster);
            deployment.staked_asset.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
            deployment.revenue_module.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
            deployment.custodian_module.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
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
        configObj = vm.serializeString(configKey, "staked_asset_name", deployment.staked_asset.name());
        configObj = vm.serializeString(configKey, "staked_asset_symbol", deployment.staked_asset.symbol());
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
        contractsObj = vm.serializeAddress(contractsKey, "staked_asset", address(deployment.staked_asset));
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
        console2.logBytes32(deployment.controller.ORDER_TYPEHASH());
        console2.log("context typehash: ");
        console2.logBytes32(deployment.controller.CONTEXT_TYPEHASH());
        console2.log("\n========================= Contracts =========================\n");
        console2.log("Controller: ", address(deployment.controller));
        console2.log("CollateralManager: ", address(deployment.manager));
        console2.log("AssetToken: ", address(deployment.asset));
        console2.log("MultiCall: ", address(deployment.multicall));
        console2.log("StakedAsset: ", address(deployment.staked_asset));
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
