// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetSilo} from "deploy-target/src/AssetSilo.sol";
import {AssetToken} from "deploy-target/src/AssetToken.sol";
import {BRLOracleAdapter} from "deploy-target/src/oracle/BRLOracleAdapter.sol";
import {CollateralManager} from "deploy-target/src/CollateralManager.sol";
import {console2} from "forge-std/console2.sol";
import {Controller} from "deploy-target/src/Controller.sol";
import {CustodianModule} from "deploy-target/src/CustodianModule.sol";
import {DeployBase} from "./DeployBase.s.sol";
import {ERC1967Proxy} from "deploy-target/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Gate} from "deploy-target/src/external/morpho/Gate.sol";
import {GoldOracleAdapter} from "deploy-target/src/oracle/GoldOracleAdapter.sol";
import {IAdapter} from "vault-v2/src/interfaces/IAdapter.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IMorphoVaultV1AdapterFactory} from "vault-v2/src/adapters/interfaces/IMorphoVaultV1AdapterFactory.sol";
import {IOracleAdapter} from "deploy-target/src/interface/IOracleAdapter.sol";
import {IVaultV2} from "vault-v2/src/interfaces/IVaultV2.sol";
import {IVaultV2Factory} from "vault-v2/src/interfaces/IVaultV2Factory.sol";
import {Mock1InchRouter} from "../test/mocks/Mock1InchRouter.sol";
import {MockDistributor} from "../test/mocks/MockDistributor.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {MockERC4626} from "../test/mocks/MockERC4626.sol";
import {MultiCall} from "deploy-target/src/MultiCall.sol";
import {MXNOracleAdapter} from "deploy-target/src/oracle/MXNOracleAdapter.sol";
import {RevenueModule} from "deploy-target/src/RevenueModule.sol";
import {StakedAsset} from "deploy-target/src/StakedAsset.sol";
import {SwapModule} from "deploy-target/src/SwapModule.sol";

/// @notice Deploy and configure the full protocol (morpho vault + core contracts) on any supported chain.
/// The Foundry profile selects production contracts from lib/tenbin-contracts or development contracts from src.
/// Supported chains: mainnet (1), sepolia (11155111, mocks), local dev (31337, mocks + local morpho factories).
/// The profile and the mock flag are independent: `FOUNDRY_PROFILE=production` + `run(..., true)` deploys the
/// public release contracts with mock integrations (how chain_integration and bdd-e2e test against anvil).
///
/// Deployment instructions
/// 1) Ensure `MAINNET_RPC_URL`, `BROADCASTER_KEY`, `BROADCASTER_ADDRESS` and (for verification) `ETHERSCAN_API_KEY` are set.
/// 2) Run `FOUNDRY_PROFILE=production forge script script/Deploy.s.sol --sig "run(string,string,bool)" $ASSET_CONFIG $VAULT_CONFIG false --rpc-url $MAINNET_RPC_URL --private-key $BROADCASTER_KEY --slow --verify --verifier etherscan --verifier-api-key $ETHERSCAN_API_KEY`
/// Add --broadcast to broadcast
/// 3) Read the output via `broadcast/Deploy.s.sol/<chainid>/contracts.json`
///
/// Post Deployment:
/// 1) Call claimOwnership() on AssetToken
contract Deploy is DeployBase {
    /// @notice Morpho Vault V2 Factory Mainnet
    address constant VAULT_V2_FACTORY_ADDRESS = 0xA1D94F746dEfa1928926b84fB2596c06926C0405;
    /// @notice Morpho Vault V2 Factory Sepolia
    address constant VAULT_V2_FACTORY_ADDRESS_SEPOLIA = 0xb3fE2D5f8Af90f194B01db546397058Fcebb85D1;
    /// @notice Morpho VaultV1Adapter Factory Mainnet
    address constant VAULT_V1_ADAPTER_FACTORY_ADDRESS = 0xD1B8E2dee25c2b89DCD2f98448a7ce87d6F63394;
    /// @notice Morpho VaultV1Adapter Factory Sepolia
    address constant VAULT_V1_ADAPTER_FACTORY_ADDRESS_SEPOLIA = 0x6a86a72C13cd29350A779befa70E3B08Cd870F84;

    /// @notice Core protocol contracts deployed by this script
    struct CoreDeploymentResult {
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
        StakedAsset staked_asset;
        SwapModule swap_module;
    }

    /// @notice Morpho vault contracts deployed by this script
    struct VaultDeploymentResult {
        Gate gate;
        IVaultV2 vault;
        IAdapter adapter;
    }

    function defaultAssetConfigDir() internal view returns (string memory) {
        if (block.chainid == 1) return "./config/mainnet/tgld/tgld.toml";
        if (block.chainid == 11155111) return "./config/sepolia/tgld/tgld_sepolia.toml";
        return "./config/local/local.toml";
    }

    function defaultVaultConfigDir() internal view returns (string memory) {
        if (block.chainid == 1) return "./config/mainnet/tgld/vaults/tgld_usdc_vault.toml";
        if (block.chainid == 11155111) return "./config/sepolia/tgld/vaults/tgld_sepolia_vault.toml";
        return "./config/local/local_vault.toml";
    }

    function run(string memory assetConfigDir, string memory vaultConfigDir, bool useMockIntegrations)
        public
        returns (CoreDeploymentResult memory core, VaultDeploymentResult memory vault)
    {
        require(block.chainid == 1 || block.chainid == 11155111 || block.chainid == 31337, "chain not supported");

        if (bytes(assetConfigDir).length == 0) assetConfigDir = defaultAssetConfigDir();
        if (bytes(vaultConfigDir).length == 0) vaultConfigDir = defaultVaultConfigDir();

        // 1. load configurations
        loadCoreConfig(assetConfigDir);
        loadRolesConfig();
        loadVaultConfig(vaultConfigDir);

        // 2. deploy vault and liquidity adapter
        vault = deployVault();

        // 3. deploy core contracts
        core = deployCore(IERC4626(address(vault.vault)), useMockIntegrations);

        // wire the gate to the collateral manager deployed above and hand it over to the curator
        finalizeGate(vault, address(core.manager));

        // 4. serialize json and save to broadcast/Deploy.s.sol/<chainid>/contracts.json
        serialize(core, vault);
        printCoreDeployment(core);
        printVaultDeployment(vault);
        printLogo();
    }

    function runCoreOnly(string memory assetConfigDir, bool useMockIntegrations)
        public
        returns (CoreDeploymentResult memory core)
    {
        require(block.chainid == 1 || block.chainid == 11155111 || block.chainid == 31337, "chain not supported");

        if (bytes(assetConfigDir).length == 0) assetConfigDir = defaultAssetConfigDir();

        loadCoreConfig(assetConfigDir);
        loadRolesConfig();

        address vault = assetConfig.get("vault").toAddress();
        require(vault != address(0), "vault not set in asset config");

        core = deployCore(IERC4626(vault), useMockIntegrations);
        serializeCore(core);
        printCoreDeployment(core);
        printLogo();
    }

    function runVaultOnly(string memory vaultConfigDir) public returns (VaultDeploymentResult memory vault) {
        require(block.chainid == 1 || block.chainid == 11155111 || block.chainid == 31337, "chain not supported");

        if (bytes(vaultConfigDir).length == 0) vaultConfigDir = defaultVaultConfigDir();

        loadVaultConfig(vaultConfigDir);
        address manager;
        if (!vaultConfig.get("is_new_asset_vault").toBool()) manager = vaultConfig.get("manager").toAddress();

        vault = deployVault();
        finalizeGate(vault, manager);
        serializeVaultOnly(vault);
        printVaultDeployment(vault);
        printLogo();
    }

    /// @notice Deploy and configure a morpho v2 vault, its liquidity adapter, and the gate.
    /// Gate ownership stays with the broadcaster until finalizeGate wires the collateral manager.
    function deployVault() internal broadcast returns (VaultDeploymentResult memory deployment) {
        IVaultV2Factory vaultFactory;
        IMorphoVaultV1AdapterFactory adapterFactory;

        bytes32 salt = keccak256(abi.encodePacked(SALT, vaultParams.symbol));

        // load factory addresses and set up mocks based on chain
        if (block.chainid == 1) {
            vaultFactory = IVaultV2Factory(VAULT_V2_FACTORY_ADDRESS);
            adapterFactory = IMorphoVaultV1AdapterFactory(VAULT_V1_ADAPTER_FACTORY_ADDRESS);
        } else if (block.chainid == 11155111) {
            vaultFactory = IVaultV2Factory(VAULT_V2_FACTORY_ADDRESS_SEPOLIA);
            adapterFactory = IMorphoVaultV1AdapterFactory(VAULT_V1_ADAPTER_FACTORY_ADDRESS_SEPOLIA);
            // mint mock collateral to cover the dead deposits and deploy a mock initial vault
            MockERC20(vaultParams.asset).mint(broadcaster, 1e6 + vaultParams.dead_deposit);
            vaultParams.initial_vault =
                address(new MockERC4626{salt: salt}("Steakhouse USDC", "SUSDC", IERC20(vaultParams.asset)));
            IERC20(vaultParams.asset).approve(vaultParams.initial_vault, 1e6);
            IERC4626(vaultParams.initial_vault).deposit(1e6, address(0xDEAD));
        } else {
            // local dev: deploy the morpho factories and a mock collateral shared with the core deployment.
            // Artifact-path form is required: the "File.sol:Name" form only resolves artifacts in the
            // current compile graph, and the solc-0.8.28 morpho contracts can't be imported across the
            // pragma split — they exist only on disk after a project-wide build (see MorphoArtifacts.sol).
            vaultFactory = IVaultV2Factory(deployCode("out/VaultV2Factory.sol/VaultV2Factory.json"));
            adapterFactory = IMorphoVaultV1AdapterFactory(
                deployCode("out/MorphoVaultV1AdapterFactory.sol/MorphoVaultV1AdapterFactory.json")
            );
            MockERC20 collateral = new MockERC20{salt: salt}("Mock USDC", "USDC", 6);
            coreParams.collateral = address(collateral);
            vaultParams.asset = address(collateral);
            vaultParams.initial_vault = address(new MockERC4626{salt: salt}("Steakhouse USDC", "SUSDC", collateral));
            collateral.mint(broadcaster, 1e6 + vaultParams.dead_deposit);
            collateral.approve(vaultParams.initial_vault, 1e6);
            IERC4626(vaultParams.initial_vault).deposit(1e6, address(0xDEAD));
        }
        if (coreParams.collateral != address(0)) {
            require(vaultParams.asset == coreParams.collateral, "vault asset does not match collateral");
        }

        // deploy new vault with broadcaster as initial owner
        deployment.vault = IVaultV2(vaultFactory.createVaultV2(broadcaster, vaultParams.asset, salt));

        // deploy adapter
        deployment.adapter =
            IAdapter(adapterFactory.createMorphoVaultV1Adapter(address(deployment.vault), vaultParams.initial_vault));

        // deploy gate
        deployment.gate = new Gate(broadcaster);

        // set name and symbol
        deployment.vault.setName(vaultParams.name);
        deployment.vault.setSymbol(vaultParams.symbol);

        // transfer curator permissions to broadcaster
        deployment.vault.setCurator(broadcaster);

        // add adapter
        deployment.vault.submit(abi.encodeCall(IVaultV2.addAdapter, address(deployment.adapter)));
        deployment.vault.addAdapter(address(deployment.adapter));

        // set broadcaster as allocator
        deployment.vault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (broadcaster, true)));
        deployment.vault.setIsAllocator(broadcaster, true);

        // set caps
        bytes memory adapterId = abi.encode("this", deployment.adapter);
        deployment.vault
            .submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (adapterId, vaultParams.initial_absolute_cap)));
        deployment.vault
            .submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (adapterId, vaultParams.initial_relative_cap)));
        deployment.vault.increaseAbsoluteCap(adapterId, vaultParams.initial_absolute_cap);
        deployment.vault.increaseRelativeCap(adapterId, vaultParams.initial_relative_cap);

        // set max rate
        deployment.vault.submit(abi.encodeCall(IVaultV2.setMaxRate, (vaultParams.max_rate)));
        deployment.vault.setMaxRate(vaultParams.max_rate);

        // enable liquidity adapter
        deployment.vault.setLiquidityAdapterAndData(address(deployment.adapter), new bytes(0));

        // perform dead deposit
        IERC20(deployment.vault.asset()).approve(address(deployment.vault), vaultParams.dead_deposit);
        deployment.vault.deposit(vaultParams.dead_deposit, address(0xdead)); // Dead address for burned shares

        // set sentinel and allocator
        deployment.vault.submit(abi.encodeCall(IVaultV2.setIsSentinel, (vaultParams.sentinel, true)));
        deployment.vault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (vaultParams.allocator, true)));
        deployment.vault.setIsSentinel(vaultParams.sentinel, true);
        deployment.vault.setIsAllocator(vaultParams.allocator, true);

        // set gate
        deployment.vault.submit(abi.encodeCall(IVaultV2.setSendAssetsGate, (address(deployment.gate))));
        deployment.vault.submit(abi.encodeCall(IVaultV2.setReceiveAssetsGate, (address(deployment.gate))));
        deployment.vault.submit(abi.encodeCall(IVaultV2.setSendSharesGate, (address(deployment.gate))));
        deployment.vault.submit(abi.encodeCall(IVaultV2.setReceiveSharesGate, (address(deployment.gate))));
        deployment.vault.setSendAssetsGate(address(deployment.gate));
        deployment.vault.setReceiveAssetsGate(address(deployment.gate));
        deployment.vault.setSendSharesGate(address(deployment.gate));
        deployment.vault.setReceiveSharesGate(address(deployment.gate));

        // SET FINAL ROLES
        deployment.vault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (broadcaster, false)));
        deployment.vault.setIsAllocator(broadcaster, false);

        // set timelock
        configureTimelock(deployment.vault, vaultParams.timelock_duration);

        deployment.vault.setCurator(vaultParams.curator);
        deployment.vault.setOwner(vaultParams.owner);
    }

    /// @notice Deploy and configure the selected core protocol contracts.
    function deployCore(IERC4626 vault, bool useMockIntegrations)
        internal
        broadcast
        returns (CoreDeploymentResult memory deployment)
    {
        require(coreParams.collateral != address(0), "invalid collateral");
        printAccounts();
        deployment.broadcaster = broadcaster;
        bytes32 salt = keccak256(abi.encode(SALT, coreParams.asset_symbol));

        // deploy asset token
        deployment.asset = new AssetToken{salt: salt}(coreParams.asset_name, coreParams.asset_symbol, broadcaster);

        // deploy custodian module
        deployment.custodian_module = new CustodianModule(broadcaster);

        // deploy staking behind a proxy
        address stakingImplementation = address(new StakedAsset{salt: salt}());
        bytes memory data = abi.encodeWithSelector(
            StakedAsset.initialize.selector,
            coreParams.staked_asset_name,
            coreParams.staked_asset_symbol,
            deployment.asset,
            broadcaster
        );
        ERC1967Proxy proxy = new ERC1967Proxy{salt: salt}(stakingImplementation, data);
        deployment.staked_asset = StakedAsset(address(proxy));

        // deploy controller
        deployment.controller = new Controller{salt: salt}(
            address(deployment.asset),
            address(deployment.staked_asset),
            coreParams.ratio,
            address(deployment.custodian_module),
            broadcaster
        );
        require(stringMatches(deployment.controller.version(), getVersion()), "controller version mismatch");

        // deploy multicall
        deployment.multicall = new MultiCall{salt: salt}(broadcaster);

        // deploy manager behind a proxy
        address managerImplementation = address(new CollateralManager{salt: salt}());
        data =
            abi.encodeWithSelector(CollateralManager.initialize.selector, address(deployment.controller), broadcaster);
        proxy = new ERC1967Proxy{salt: salt}(managerImplementation, data);
        deployment.manager = CollateralManager(address(proxy));

        deployment.silo = AssetSilo(address(deployment.staked_asset.silo()));

        // collateral comes from config (fresh mock on local dev); vault is caller-supplied
        deployment.collateral = IERC20(coreParams.collateral);
        deployment.vault = vault;

        if (useMockIntegrations) {
            deployment.one_inch_router = address(new Mock1InchRouter());
        } else {
            require(block.chainid == 1, "live integrations require mainnet");
            require(coreParams.one_inch_router != address(0), "Invalid router");
            deployment.one_inch_router = coreParams.one_inch_router;
        }
        deployment.swap_module =
            new SwapModule{salt: salt}(address(deployment.manager), deployment.one_inch_router, roles.admin_role);

        // deploy revenue module
        deployment.revenue_module = new RevenueModule{salt: salt}(
            address(deployment.manager),
            address(deployment.staked_asset),
            broadcaster,
            address(deployment.controller),
            address(deployment.asset),
            address(coreParams.multisig)
        );

        if (useMockIntegrations) {
            deployment.oracle_adapter = IOracleAdapter(address(0));
        } else if (stringMatches(coreParams.asset_symbol, "tGLD")) {
            deployment.oracle_adapter = IOracleAdapter(address(new GoldOracleAdapter()));
            require(deployment.oracle_adapter.oracle() == coreParams.oracle, "oracle mismatch");
        } else if (stringMatches(coreParams.asset_symbol, "tBRL")) {
            deployment.oracle_adapter = IOracleAdapter(address(new BRLOracleAdapter()));
            require(deployment.oracle_adapter.oracle() == coreParams.oracle, "oracle mismatch");
        } else if (stringMatches(coreParams.asset_symbol, "tMXN")) {
            deployment.oracle_adapter = IOracleAdapter(address(new MXNOracleAdapter()));
            require(deployment.oracle_adapter.oracle() == coreParams.oracle, "oracle mismatch");
        } else {
            require(coreParams.oracle == address(0), "oracle mismatch");
            deployment.oracle_adapter = IOracleAdapter(address(0));
        }

        // set asset permissions
        deployment.asset.setMinter(address(deployment.controller));

        // set controller permissions
        deployment.controller.grantRole(ADMIN_ROLE, roles.admin_role);
        deployment.controller.grantRole(MINTER_ROLE, roles.minter_role);
        deployment.controller.grantRole(MINTER_ROLE, address(deployment.multicall));
        deployment.controller.grantRole(GATEKEEPER_ROLE, roles.gatekeeper_role);
        deployment.controller.grantRole(GATEKEEPER_ROLE, roles.admin_role);
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
        deployment.manager.grantRole(GATEKEEPER_ROLE, roles.admin_role);
        if (block.chainid == 1) deployment.manager.setDistributor(DISTRIBUTOR);
        else deployment.manager.setDistributor(address(new MockDistributor()));
        deployment.manager.setClaimRecipient(REWARD_RECIPIENT, address(0));

        // set multicall permissions
        deployment.multicall.grantRole(MULTICALLER_ROLE, roles.multicaller_role);

        // set staking permissions
        deployment.staked_asset.grantRole(ADMIN_ROLE, roles.admin_role);
        deployment.staked_asset.grantRole(REWARDER_ROLE, roles.rewarder_role);
        deployment.staked_asset.grantRole(REWARDER_ROLE, address(deployment.revenue_module));
        deployment.staked_asset.grantRole(RESTRICTER_ROLE, roles.restricter_role);
        deployment.staked_asset.grantRole(CAP_ADJUSTER_ROLE, roles.cap_adjuster_role);
        deployment.staked_asset.grantRole(INSTANT_UNSTAKER_ROLE, address(deployment.controller));

        // set revenue module permissions
        deployment.revenue_module.grantRole(ADMIN_ROLE, roles.admin_role);
        deployment.revenue_module.grantRole(REVENUE_KEEPER_ROLE, roles.revenue_keeper_role);
        deployment.custodian_module.grantRole(CUSTODIAN_KEEPER_ROLE, roles.custodian_keeper_role);

        // give temporary permissions to broadcaster
        deployment.controller.grantRole(ADMIN_ROLE, broadcaster);
        deployment.controller.grantRole(SIGNER_MANAGER_ROLE, broadcaster);
        deployment.manager.grantRole(ADMIN_ROLE, broadcaster);
        deployment.manager.grantRole(CAP_ADJUSTER_ROLE, broadcaster);
        deployment.staked_asset.grantRole(ADMIN_ROLE, broadcaster);
        deployment.staked_asset.grantRole(CAP_ADJUSTER_ROLE, broadcaster);

        // configure controller
        deployment.controller.setIsCollateral(address(deployment.collateral), true);
        deployment.controller.setManager(address(deployment.manager));
        deployment.controller.setOracleAdapter(address(deployment.oracle_adapter));
        deployment.controller.setOracleTolerance(uint96(coreParams.oracle_tolerance));
        deployment.controller.setBlockMintLimit(coreParams.mint_limit);
        deployment.controller.setBlockRedeemLimit(coreParams.redeem_limit);
        if (useMockIntegrations) deployment.controller.setSignerStatus(coreParams.signer, true);

        // configure manager
        deployment.manager.addCollateral(address(deployment.collateral), address(deployment.vault));
        deployment.manager.setSwapModule(address(deployment.swap_module));
        deployment.manager.setRevenueModule(address(deployment.revenue_module));
        deployment.manager.setRebalanceCap(address(deployment.collateral), coreParams.rebalance_cap);

        // configure staking
        deployment.staked_asset.setCooldownPeriod(coreParams.cooldown_period);
        deployment.staked_asset.setVestingPeriod(uint128(coreParams.vesting_period));
        deployment.staked_asset.setInstantUnstakeCap(coreParams.instant_unstake_cap);

        // configure custodian module
        deployment.custodian_module.setCustodianStatus(coreParams.custodian, true);

        // transfer ownership
        deployment.manager.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.controller.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.multicall.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.staked_asset.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.revenue_module.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.custodian_module.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.asset.transferOwnership(roles.default_admin_role);

        // testnet and mock options
        if (useMockIntegrations) {
            // additionally allow multisig to manage ownership
            deployment.manager.grantRole(DEFAULT_ADMIN_ROLE, coreParams.multisig);
            deployment.controller.grantRole(DEFAULT_ADMIN_ROLE, coreParams.multisig);
            deployment.multicall.grantRole(DEFAULT_ADMIN_ROLE, coreParams.multisig);
            deployment.staked_asset.grantRole(DEFAULT_ADMIN_ROLE, coreParams.multisig);
            deployment.revenue_module.grantRole(DEFAULT_ADMIN_ROLE, coreParams.multisig);
            deployment.custodian_module.grantRole(DEFAULT_ADMIN_ROLE, coreParams.multisig);

            if (block.chainid != 1) {
                MockERC20(address(deployment.collateral)).mint(broadcaster, 1_000_000_000_000e6);
                deployment.collateral.approve(address(deployment.controller), 1_000_000_000_000e6);
            }
        }

        // renounce broadcaster roles (except for local dev)
        if (block.chainid != 31337) {
            deployment.controller.revokeRole(ADMIN_ROLE, broadcaster);
            deployment.manager.revokeRole(ADMIN_ROLE, broadcaster);
            deployment.staked_asset.revokeRole(ADMIN_ROLE, broadcaster);
            deployment.controller.revokeRole(SIGNER_MANAGER_ROLE, broadcaster);
            deployment.manager.revokeRole(CAP_ADJUSTER_ROLE, broadcaster);
            deployment.staked_asset.revokeRole(CAP_ADJUSTER_ROLE, broadcaster);

            deployment.controller.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
            deployment.manager.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
            deployment.multicall.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
            deployment.staked_asset.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
            deployment.revenue_module.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
            deployment.custodian_module.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
        }
    }

    /// @notice Wire the gate to the collateral manager deployed by this run and hand ownership to the curator
    function finalizeGate(VaultDeploymentResult memory vaultResult, address manager) internal broadcast {
        vaultResult.gate.setManager(manager);
        vaultResult.gate.transferOwnership(vaultParams.curator);
    }

    /// @notice Configure timelock settings for critical functions
    function configureTimelock(IVaultV2 vault, uint256 timelock_duration) internal {
        // Define function selectors that should be timelocked
        bytes4[] memory timelockedSelectors = new bytes4[](11);
        timelockedSelectors[0] = IVaultV2.setReceiveSharesGate.selector;
        timelockedSelectors[1] = IVaultV2.setSendSharesGate.selector;
        timelockedSelectors[2] = IVaultV2.setReceiveAssetsGate.selector;
        timelockedSelectors[3] = IVaultV2.setSendAssetsGate.selector;
        timelockedSelectors[4] = IVaultV2.addAdapter.selector;
        timelockedSelectors[5] = IVaultV2.increaseAbsoluteCap.selector;
        timelockedSelectors[6] = IVaultV2.increaseRelativeCap.selector;
        timelockedSelectors[7] = IVaultV2.setForceDeallocatePenalty.selector;
        timelockedSelectors[8] = IVaultV2.abdicate.selector;
        timelockedSelectors[9] = IVaultV2.removeAdapter.selector;
        timelockedSelectors[10] = IVaultV2.increaseTimelock.selector;

        // Submit timelock increases for all selectors
        for (uint256 i = 0; i < timelockedSelectors.length; i++) {
            vault.submit(abi.encodeCall(vault.increaseTimelock, (timelockedSelectors[i], timelock_duration)));
        }
        console2.log("Timelock increases submitted for", timelockedSelectors.length, "functions");

        // Execute timelock increases for all selectors
        for (uint256 i = 0; i < timelockedSelectors.length; i++) {
            vault.increaseTimelock(timelockedSelectors[i], timelock_duration);
        }
        console2.log("Timelock increases executed for", timelockedSelectors.length, "functions");
    }

    /* ------------------------------------ SERIALIZATION ------------------------------------------ */

    // Given the deployment results, serialize the JSON
    function serialize(CoreDeploymentResult memory deployment, VaultDeploymentResult memory vaultResult) internal {
        console2.log("\nSerializing json...\n");

        // keys
        string memory chainKey;
        if (block.chainid == 1) chainKey = "mainnet";
        else if (block.chainid == 11155111) chainKey = "sepolia";
        else chainKey = "localhost";
        string memory assetKey = deployment.asset.symbol();

        // serialize config
        string memory configKey = "asset_config_obj";
        string memory configObj = vm.serializeString(configKey, "asset_name", deployment.asset.name());
        configObj = vm.serializeString(configKey, "asset_symbol", deployment.asset.symbol());
        configObj = vm.serializeUint(configKey, "deployment_block", block.number);
        configObj = vm.serializeBytes32(configKey, "domain_separator", deployment.controller.getDomainSeparator());
        configObj = vm.serializeString(configKey, "staked_asset_name", deployment.staked_asset.name());
        configObj = vm.serializeString(configKey, "staked_asset_symbol", deployment.staked_asset.symbol());
        configObj = vm.serializeString(configKey, "version", deployment.controller.version());
        configObj = vm.serializeAddress(configKey, "deployer", broadcaster);

        // serialize contracts
        string memory contractsKey = "asset_contracts_obj";
        string memory contractsObj = vm.serializeAddress(contractsKey, "asset_token", address(deployment.asset));
        contractsObj = vm.serializeAddress(contractsKey, "collateral", address(deployment.collateral));
        contractsObj = vm.serializeAddress(contractsKey, "collateral_manager", address(deployment.manager));
        contractsObj = vm.serializeAddress(contractsKey, "controller", address(deployment.controller));
        contractsObj = vm.serializeAddress(contractsKey, "custodian_module", address(deployment.custodian_module));
        contractsObj = vm.serializeAddress(contractsKey, "multicall", address(deployment.multicall));
        contractsObj = vm.serializeAddress(contractsKey, "oracle_adapter", address(deployment.oracle_adapter));
        contractsObj = vm.serializeAddress(contractsKey, "revenue_module", address(deployment.revenue_module));
        contractsObj = vm.serializeAddress(contractsKey, "silo", address(deployment.silo));
        contractsObj = vm.serializeAddress(contractsKey, "staked_asset", address(deployment.staked_asset));
        contractsObj = vm.serializeAddress(contractsKey, "swap_module", address(deployment.swap_module));

        // Build asset object
        vm.serializeString(assetKey, "config", configObj);
        vm.serializeString(assetKey, "contracts", contractsObj);
        vm.serializeString(
            assetKey, "roles", getRolesObject(address(deployment.multicall), address(deployment.revenue_module))
        );
        string memory assetJson = vm.serializeString(assetKey, "vault", serializeVault(vaultResult));

        // Build chain object
        string memory chainJson = vm.serializeString(chainKey, "global", getGlobalObject());
        chainJson = vm.serializeString(chainKey, assetKey, assetJson);

        // Wrap under chainKey
        string memory obj = vm.serializeString("root", chainKey, chainJson);

        // save to file
        string memory path = string.concat("broadcast/Deploy.s.sol/", vm.toString(block.chainid));
        vm.createDir(path, true);
        vm.writeJson(obj, string.concat(path, "/contracts.json"));
    }

    function serializeCore(CoreDeploymentResult memory deployment) internal {
        console2.log("\nSerializing json...\n");

        string memory chainKey;
        if (block.chainid == 1) chainKey = "mainnet";
        else if (block.chainid == 11155111) chainKey = "sepolia";
        else chainKey = "localhost";
        string memory assetKey = deployment.asset.symbol();

        string memory configKey = "asset_config_obj";
        string memory configObj = vm.serializeString(configKey, "asset_name", deployment.asset.name());
        configObj = vm.serializeString(configKey, "asset_symbol", deployment.asset.symbol());
        configObj = vm.serializeUint(configKey, "deployment_block", block.number);
        configObj = vm.serializeBytes32(configKey, "domain_separator", deployment.controller.getDomainSeparator());
        configObj = vm.serializeString(configKey, "staked_asset_name", deployment.staked_asset.name());
        configObj = vm.serializeString(configKey, "staked_asset_symbol", deployment.staked_asset.symbol());
        configObj = vm.serializeString(configKey, "version", deployment.controller.version());
        configObj = vm.serializeAddress(configKey, "deployer", broadcaster);

        string memory contractsKey = "asset_contracts_obj";
        string memory contractsObj = vm.serializeAddress(contractsKey, "asset_token", address(deployment.asset));
        contractsObj = vm.serializeAddress(contractsKey, "collateral", address(deployment.collateral));
        contractsObj = vm.serializeAddress(contractsKey, "collateral_manager", address(deployment.manager));
        contractsObj = vm.serializeAddress(contractsKey, "controller", address(deployment.controller));
        contractsObj = vm.serializeAddress(contractsKey, "custodian_module", address(deployment.custodian_module));
        contractsObj = vm.serializeAddress(contractsKey, "multicall", address(deployment.multicall));
        contractsObj = vm.serializeAddress(contractsKey, "oracle_adapter", address(deployment.oracle_adapter));
        contractsObj = vm.serializeAddress(contractsKey, "revenue_module", address(deployment.revenue_module));
        contractsObj = vm.serializeAddress(contractsKey, "silo", address(deployment.silo));
        contractsObj = vm.serializeAddress(contractsKey, "staked_asset", address(deployment.staked_asset));
        contractsObj = vm.serializeAddress(contractsKey, "swap_module", address(deployment.swap_module));

        vm.serializeString(assetKey, "config", configObj);
        vm.serializeString(assetKey, "contracts", contractsObj);
        string memory assetJson = vm.serializeString(
            assetKey, "roles", getRolesObject(address(deployment.multicall), address(deployment.revenue_module))
        );

        string memory chainJson = vm.serializeString(chainKey, "global", getGlobalObject());
        chainJson = vm.serializeString(chainKey, assetKey, assetJson);
        string memory obj = vm.serializeString("root", chainKey, chainJson);

        string memory path = string.concat("broadcast/Deploy.s.sol/", vm.toString(block.chainid));
        vm.createDir(path, true);
        vm.writeJson(obj, string.concat(path, "/contracts.json"));
    }

    function serializeVaultOnly(VaultDeploymentResult memory vaultResult) internal {
        console2.log("\nSerializing json...\n");
        string memory path = string.concat("broadcast/Deploy.s.sol/", vm.toString(block.chainid));
        vm.createDir(path, true);
        vm.writeJson(serializeVault(vaultResult), string.concat(path, "/vault.json"));
    }

    // Builds the vault JSON from the vault deployment result
    function serializeVault(VaultDeploymentResult memory vaultResult) internal returns (string memory vaultJson) {
        // single liquidity adapter, named after the underlying vault it wraps
        string memory adapterObj = vm.serializeAddress("adapter_obj", "address", address(vaultResult.adapter));
        adapterObj =
            vm.serializeBytes32("adapter_obj", "id", keccak256(abi.encode("this", address(vaultResult.adapter))));
        adapterObj = vm.serializeString("adapter_obj", "name", IERC4626(vaultParams.initial_vault).name());

        // serialize config: label the vault's underlying asset by its real token symbol
        string memory configObj =
            vm.serializeString("vault_config_obj", "asset", IERC20Metadata(vaultParams.asset).symbol());
        configObj = vm.serializeUint("vault_config_obj", "deployment_block", block.number);

        // serialize contracts
        string memory contractsObj = vm.serializeAddress("vault_contracts_obj", "gate", address(vaultResult.gate));
        contractsObj = vm.serializeAddress("vault_contracts_obj", "vault", address(vaultResult.vault));

        // serialize roles
        string memory rolesObj = vm.serializeAddress("vault_roles_obj", "allocator", vaultParams.allocator);
        rolesObj = vm.serializeAddress("vault_roles_obj", "curator", vaultParams.curator);
        rolesObj = vm.serializeAddress("vault_roles_obj", "owner", vaultParams.owner);
        rolesObj = vm.serializeAddress("vault_roles_obj", "sentinel", vaultParams.sentinel);

        // Build vault object
        // concatenated by hand: vm.serialize* escapes array-of-object strings instead of embedding them
        vaultJson = string.concat(
            '{"adapters":[',
            adapterObj,
            '],"config":',
            configObj,
            ',"contracts":',
            contractsObj,
            ',"roles":',
            rolesObj,
            "}"
        );
    }

    function printCoreDeployment(CoreDeploymentResult memory deployment) internal view {
        console2.log("\n========================= Domain ============================\n");
        console2.log("domain separator: ");
        console2.logBytes32(deployment.controller.getDomainSeparator());
        console2.log("order typehash: ");
        console2.logBytes32(
            keccak256(
                "Order(uint8 order_type,uint256 nonce,uint256 expiry,address payer,address recipient,address collateral_token,uint256 collateral_amount,uint256 asset_amount)"
            )
        );
        console2.log("\n========================= Core =========================\n");
        console2.log("AssetSilo : ", address(deployment.silo));
        console2.log("AssetToken: ", address(deployment.asset));
        console2.log("CollateralManager: ", address(deployment.manager));
        console2.log("Controller: ", address(deployment.controller));
        console2.log("CustodianModule : ", address(deployment.custodian_module));
        console2.log("MultiCall: ", address(deployment.multicall));
        console2.log("OracleAdapter:", address(deployment.oracle_adapter));
        console2.log("RevenueModule : ", address(deployment.revenue_module));
        console2.log("StakedAsset: ", address(deployment.staked_asset));
        console2.log("SwapModule: ", address(deployment.swap_module));
        console2.log("Collateral: ", address(deployment.collateral));
        console2.log("\n=============================================================\n");
    }

    function printVaultDeployment(VaultDeploymentResult memory vaultResult) internal pure {
        console2.log("\n========================= Vault =========================\n");
        console2.log("Vault: ", address(vaultResult.vault));
        console2.log("Adapter: ", address(vaultResult.adapter));
        console2.log("Gate: ", address(vaultResult.gate));
        console2.log("\n=============================================================\n");
    }
}
