// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetSilo} from "deploy-target/src/AssetSilo.sol";
import {AssetToken} from "deploy-target/src/AssetToken.sol";
import {BRLOracleAdapter} from "deploy-target/src/oracle/BRLOracleAdapter.sol";
import {CollateralManager} from "deploy-target/src/CollateralManager.sol";
import {console2} from "forge-std/console2.sol";
import {Controller} from "deploy-target/src/Controller.sol";
import {CustodianModule} from "deploy-target/src/CustodianModule.sol";
import {ERC1967Proxy} from "deploy-target/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Gate} from "deploy-target/src/external/morpho/Gate.sol";
import {GoldOracleAdapter} from "deploy-target/src/oracle/GoldOracleAdapter.sol";
import {IAdapter} from "vault-v2/src/interfaces/IAdapter.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IMorpho, Id, MarketParams} from "vault-v2/lib/morpho-blue/src/interfaces/IMorpho.sol";
import {IMorphoMarketV1AdapterV2} from "vault-v2/src/adapters/interfaces/IMorphoMarketV1AdapterV2.sol";
import {IOracleAdapter} from "deploy-target/src/interface/IOracleAdapter.sol";
import {IVaultV2} from "vault-v2/src/interfaces/IVaultV2.sol";
import {IVaultV2Factory} from "vault-v2/src/interfaces/IVaultV2Factory.sol";
import {MarketParamsLib} from "vault-v2/lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {Mock1InchRouter} from "../test/mocks/Mock1InchRouter.sol";
import {MockDistributor} from "../test/mocks/MockDistributor.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {MockERC4626} from "../test/mocks/MockERC4626.sol";
import {MockOracleAdapter} from "../test/mocks/MockOracleAdapter.sol";
import {MorphoAdapterDeployer} from "./MorphoAdapterDeployer.s.sol";
import {MultiCall} from "deploy-target/src/MultiCall.sol";
import {MXNOracleAdapter} from "deploy-target/src/oracle/MXNOracleAdapter.sol";
import {OracleMock} from "vault-v2/lib/morpho-blue/src/mocks/OracleMock.sol";
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
/// 1) Ensure `MAINNET_RPC_URL`, `BROADCASTER_ACCOUNT`, `BROADCASTER_ADDRESS` and (for verification) `ETHERSCAN_API_KEY` are set.
/// 2) Run `FOUNDRY_PROFILE=production forge script script/Deploy.s.sol --sig "run(string,string,bool)" $ASSET_CONFIG $VAULT_CONFIG false --rpc-url $MAINNET_RPC_URL --account "$BROADCASTER_ACCOUNT" --sender "$BROADCASTER_ADDRESS" --slow --verify --verifier etherscan --verifier-api-key $ETHERSCAN_API_KEY`
/// Add --broadcast to broadcast
/// 3) Read the output via `broadcast/Deploy.s.sol/<chainid>/contracts.json`
///
/// Post Deployment:
/// 1) Call claimOwnership() on AssetToken
contract Deploy is MorphoAdapterDeployer {
    using MarketParamsLib for MarketParams;

    /// @notice Morpho Vault V2 Factory Mainnet
    address constant VAULT_V2_FACTORY_ADDRESS = 0xA1D94F746dEfa1928926b84fB2596c06926C0405;
    /// @notice Morpho Vault V2 Factory Sepolia
    address constant VAULT_V2_FACTORY_ADDRESS_SEPOLIA = 0xb3fE2D5f8Af90f194B01db546397058Fcebb85D1;
    /// @notice Local mock oracle price of one 18-decimal collateral unit in 6-decimal loan units:
    /// morpho scales prices by 1e36, so $1 per unit is 1e36 * 1e6 / 1e18 = 1e24.
    uint256 constant LOCAL_ORACLE_PRICE = 1e24;

    /// @notice Starting mock oracle prices in 18-decimal USD.
    uint256 constant MOCK_ORACLE_PRICE_GLD = 3_500e18;
    uint256 constant MOCK_ORACLE_PRICE_BRL = 18e16;
    uint256 constant MOCK_ORACLE_PRICE_MXN = 5e16;
    /// @notice Fallback for an asset with no per-asset figure above.
    uint256 constant MOCK_ORACLE_PRICE_DEFAULT = 1e18;

    /// @notice Dead-deposit seed for each mocked ERC4626 adapter target, in 6-decimal collateral
    /// units. The engine annualizes share-price growth linearly, so a donation of D into a pot of
    /// S reads as D/S * 31_536_000 / window: over the e2e 20s window, 5 USDC into 20M is ~39% APY,
    /// inside the 50% `max_apy` cap. A small pot puts every usable donation over that cap, where
    /// the sample is discarded and the adapter drops out of yield ranking entirely.
    uint256 constant MOCK_TARGET_DEAD_DEPOSIT = 20_000_000e6;

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

    /// @notice A single adapter deployed for the vault
    struct DeployedAdapter {
        IAdapter adapter;
        string adapter_type;
        string name;
    }

    /// @notice A morpho market the vault's MARKET adapter allocates to, with resolved params
    struct DeployedMarket {
        string name;
        MarketParams params;
    }

    /// @notice Morpho vault contracts deployed by this script
    struct VaultDeploymentResult {
        Gate gate;
        IVaultV2 vault;
        IAdapter liquidity_adapter;
        DeployedAdapter[] adapters;
        DeployedMarket[] markets;
    }

    /// @notice Adapter parameters loaded from the adapter configs declared by the vault config
    AdapterParameters[] internal adapterParamsList;

    /// @notice Market parameters loaded from the market configs declared by the vault config
    MarketParameters[] internal marketConfigList;

    function defaultAssetConfigDir() internal view returns (string memory) {
        if (block.chainid == 1) return "./config/mainnet/tgld/tgld.toml";
        if (block.chainid == 11155111) return "./config/sepolia/tgld/tgld_sepolia.toml";
        return "./config/local/tgld/tgld_local.toml";
    }

    function defaultVaultConfigDir() internal view returns (string memory) {
        if (block.chainid == 1) return "./config/mainnet/tgld/vaults/tgld_usdc_vault.toml";
        if (block.chainid == 11155111) return "./config/sepolia/tgld/vaults/tgld_sepolia_vault.toml";
        return "./config/local/tgld/vaults/tgld_local_vault.toml";
    }

    function run(string memory assetConfigDir, string memory vaultConfigDir, bool useMockIntegrations)
        public
        virtual
        returns (CoreDeploymentResult memory core, VaultDeploymentResult memory vault)
    {
        require(block.chainid == 1 || block.chainid == 11155111 || block.chainid == 31337, "chain not supported");
        require(!(useMockIntegrations && block.chainid == 1), "mocks not allowed on mainnet");

        if (bytes(assetConfigDir).length == 0) assetConfigDir = defaultAssetConfigDir();
        if (bytes(vaultConfigDir).length == 0) vaultConfigDir = defaultVaultConfigDir();

        // 1. load configurations
        loadCoreConfig(assetConfigDir);
        loadRolesConfig();
        loadVaultConfig(vaultConfigDir);
        loadAdapterConfigs(vaultConfigDir);
        loadMarketConfigs(vaultConfigDir);

        // 2. deploy vault and its adapters
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

    // Run only core contracts deployment
    function runCoreOnly(string memory assetConfigDir, bool useMockIntegrations)
        public
        virtual
        returns (CoreDeploymentResult memory core)
    {
        require(block.chainid == 1 || block.chainid == 11155111 || block.chainid == 31337, "chain not supported");
        require(!(useMockIntegrations && block.chainid == 1), "mocks not allowed on mainnet");

        if (bytes(assetConfigDir).length == 0) assetConfigDir = defaultAssetConfigDir();

        // load config
        loadCoreConfig(assetConfigDir);
        loadRolesConfig();

        address vault = assetConfig.get("vault").toAddress();
        require(vault != address(0), "vault not set in asset config");

        // deploy
        core = deployCore(IERC4626(vault), useMockIntegrations);

        // serialize and print
        serializeCore(core);
        printCoreDeployment(core);
        printLogo();
    }

    // Run only vault deployment
    function runVaultOnly(string memory assetConfigDir, string memory vaultConfigDir)
        public
        virtual
        returns (VaultDeploymentResult memory vault)
    {
        require(block.chainid == 1 || block.chainid == 11155111 || block.chainid == 31337, "chain not supported");

        if (bytes(assetConfigDir).length == 0) assetConfigDir = defaultAssetConfigDir();
        if (bytes(vaultConfigDir).length == 0) vaultConfigDir = defaultVaultConfigDir();

        // load config
        loadCoreConfig(assetConfigDir);
        loadRolesConfig();
        loadVaultConfig(vaultConfigDir);
        loadAdapterConfigs(vaultConfigDir);
        loadMarketConfigs(vaultConfigDir);

        // if not a new asset vault the manager can be set after deployment
        address manager;
        if (!vaultConfig.get("is_new_asset_vault").toBool()) manager = vaultConfig.get("manager").toAddress();

        // deploy
        vault = deployVault();

        // finalize gate
        finalizeGate(vault, manager);

        // serialize and print
        serializeVaultOnly(vault);
        printVaultDeployment(vault);
        printLogo();
    }

    /// @notice Load every adapter config declared by the vault config. Call outside `broadcast`.
    function loadAdapterConfigs(string memory vaultConfigDir) internal {
        delete adapterParamsList; // a second call must not leave the list longer than vaultParams.adapters
        uint256 marketAdapters;
        for (uint256 i = 0; i < vaultParams.adapters.length; i++) {
            adapterParamsList.push(loadAdapterParams(adapterConfigPath(vaultConfigDir, vaultParams.adapters[i])));
            if (stringMatches(vaultParams.adapters[i], vaultParams.liquidity_adapter)) {
                require(
                    stringMatches(adapterParamsList[i].adapter_type, "VAULT")
                        || stringMatches(adapterParamsList[i].adapter_type, "GENERIC"),
                    "liquidity_adapter must be VAULT or GENERIC"
                );
            }
            if (stringMatches(adapterParamsList[i].adapter_type, "MARKET")) marketAdapters++;
        }
        require(marketAdapters <= 1, "at most one MARKET adapter per vault");
    }

    /// @notice Load every market config declared by the vault config's `markets` key. Only read when
    /// a MARKET adapter is configured, so existing vault configs keep working without the key.
    /// Call outside `broadcast`.
    function loadMarketConfigs(string memory vaultConfigDir) internal {
        delete marketConfigList;
        if (!hasMarketAdapter()) return;
        string[] memory names = vaultConfig.get("markets").toStringArray();
        require(names.length == 1, "exactly one market required for the MARKET adapter");
        for (uint256 i = 0; i < names.length; i++) {
            marketConfigList.push(loadMarketParams(marketConfigPath(vaultConfigDir, names[i])));
        }
    }

    /// @notice Whether the loaded adapter configs include a MARKET adapter.
    function hasMarketAdapter() internal view returns (bool) {
        for (uint256 i = 0; i < adapterParamsList.length; i++) {
            if (stringMatches(adapterParamsList[i].adapter_type, "MARKET")) return true;
        }
        return false;
    }

    /// @notice Testnets only: deploy a seeded mock ERC4626 target for each VAULT/GENERIC adapter
    /// config without a vault address. MARKET adapters have no target vault and are skipped.
    function deployMockTargets(bytes32 salt) internal {
        // loop through adapters, load from storage, and deploy a mock ERC4626 for each adapter
        for (uint256 i = 0; i < adapterParamsList.length; i++) {
            AdapterParameters storage params = adapterParamsList[i];
            if (params.vault != address(0) || stringMatches(params.adapter_type, "MARKET")) continue;

            // mint the seed, deploy a mock named after the adapter, and burn the seed as a dead deposit
            MockERC20(vaultParams.asset).mint(broadcaster, MOCK_TARGET_DEAD_DEPOSIT);
            params.vault = deployMockTarget(salt, params);
            IERC20(vaultParams.asset).approve(params.vault, MOCK_TARGET_DEAD_DEPOSIT);
            IERC4626(params.vault).deposit(MOCK_TARGET_DEAD_DEPOSIT, address(0xDEAD));
        }
    }

    /// @notice Create an ERC4626 target; e2e fixtures may override individual targets.
    function deployMockTarget(bytes32 salt, AdapterParameters memory params) internal virtual returns (address) {
        return address(
            new MockERC4626{salt: keccak256(abi.encodePacked(salt, params.name))}(
                params.name, params.name, IERC20(vaultParams.asset)
            )
        );
    }

    /// @notice Local dev only: fill each market config's unset fields with mocks (collateral token,
    /// $1 oracle, local adaptive curve IRM), create the market on the local morpho blue, and seed it
    /// with one unit of supply as an inflation-attack guard (see MorphoMarketV1AdapterV2).
    function createLocalMarkets(bytes32 salt) internal {
        resolveLocalMorphoSingletons();
        for (uint256 i = 0; i < marketConfigList.length; i++) {
            MarketParameters storage params = marketConfigList[i];
            if (params.collateral_token == address(0)) {
                string memory name = string.concat(params.name, " Collateral");
                params.collateral_token =
                    address(new MockERC20{salt: keccak256(abi.encodePacked(salt, name))}(name, name, 18));
            }
            if (params.oracle == address(0)) {
                OracleMock oracle = new OracleMock{salt: keccak256(abi.encodePacked(salt, params.name))}();
                oracle.setPrice(LOCAL_ORACLE_PRICE);
                params.oracle = address(oracle);
            }
            if (params.irm == address(0)) params.irm = adaptiveCurveIrm;

            MarketParams memory marketParams = toMarketParams(params);
            if (!IMorpho(morphoBlue).isIrmEnabled(marketParams.irm)) IMorpho(morphoBlue).enableIrm(marketParams.irm);
            if (!IMorpho(morphoBlue).isLltvEnabled(marketParams.lltv)) {
                IMorpho(morphoBlue).enableLltv(marketParams.lltv);
            }
            IMorpho(morphoBlue).createMarket(marketParams);

            MockERC20(vaultParams.asset).mint(broadcaster, 1e6);
            IERC20(vaultParams.asset).approve(morphoBlue, 1e6);
            IMorpho(morphoBlue).supply(marketParams, 1e6, 0, address(0xDEAD), hex"");
        }
    }

    /// @notice Cap each configured market on the vault. The market adapter reports three ids per
    /// allocation (adapterId, collateralToken, this/marketParams) and every one needs a cap or
    /// allocate reverts with ZeroAbsoluteCap; the adapterId cap already comes from the adapter's
    /// own config, so this sets the two market-derived ids from the market's config.
    function capMarkets(VaultDeploymentResult memory deployment) internal {
        address marketAdapter = marketAdapterAddress(deployment);
        IMorpho morpho = IMorpho(IMorphoMarketV1AdapterV2(marketAdapter).morpho());
        for (uint256 i = 0; i < marketConfigList.length; i++) {
            MarketParameters memory params = marketConfigList[i];
            MarketParams memory marketParams = toMarketParams(params);
            require(
                marketParams.irm == IMorphoMarketV1AdapterV2(marketAdapter).adaptiveCurveIrm(),
                "market irm does not match adapter"
            );
            requireMarketExists(morpho, marketParams);
            bytes memory collateralId = abi.encode("collateralToken", params.collateral_token);
            bytes memory marketId = abi.encode("this/marketParams", marketAdapter, marketParams);
            deployment.vault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (collateralId, params.absolute_cap)));
            deployment.vault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (collateralId, params.relative_cap)));
            deployment.vault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (marketId, params.absolute_cap)));
            deployment.vault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (marketId, params.relative_cap)));
            deployment.vault.increaseAbsoluteCap(collateralId, params.absolute_cap);
            deployment.vault.increaseRelativeCap(collateralId, params.relative_cap);
            deployment.vault.increaseAbsoluteCap(marketId, params.absolute_cap);
            deployment.vault.increaseRelativeCap(marketId, params.relative_cap);
        }
    }

    /// @notice Require Morpho to return the exact configured market parameters.
    function requireMarketExists(IMorpho morpho, MarketParams memory expected) internal view {
        require(
            keccak256(abi.encode(morpho.idToMarketParams(expected.id()))) == keccak256(abi.encode(expected)),
            "configured Morpho market does not exist"
        );
    }

    /// @notice Address of the vault's single MARKET adapter.
    function marketAdapterAddress(VaultDeploymentResult memory deployment) internal pure returns (address) {
        for (uint256 i = 0; i < deployment.adapters.length; i++) {
            if (stringMatches(deployment.adapters[i].adapter_type, "MARKET")) {
                return address(deployment.adapters[i].adapter);
            }
        }
        revert("no MARKET adapter deployed");
    }

    /// @notice Deploy and configure a morpho v2 vault, its adapters, and the gate.
    /// Gate ownership stays with the broadcaster until finalizeGate wires the collateral manager.
    function deployVault() internal broadcast returns (VaultDeploymentResult memory deployment) {
        deployment = createVault(true);
        configureVault(deployment);
    }

    function createVault(bool initializeLocalMarkets) internal returns (VaultDeploymentResult memory deployment) {
        require(roles.rebalancer_role != address(0), "rebalancer role not set");
        IVaultV2Factory vaultFactory;
        bytes32 salt = keccak256(abi.encodePacked(SALT, vaultParams.symbol));

        // load factory addresses and set up mocks based on chain
        if (block.chainid == 1) {
            vaultFactory = IVaultV2Factory(VAULT_V2_FACTORY_ADDRESS);
        } else if (block.chainid == 11155111) {
            vaultFactory = IVaultV2Factory(VAULT_V2_FACTORY_ADDRESS_SEPOLIA);
        } else {
            // local dev: deploy the morpho factory and a mock collateral shared with the core deployment.
            // Uses artifacts from compiled code to support morpho's solidity version (see MorphoArtifacts.sol).
            vaultFactory = IVaultV2Factory(deployCode("out/VaultV2Factory.sol/VaultV2Factory.json"));
            MockERC20 collateral = new MockERC20{salt: salt}("Mock USDC", "USDC", 6);
            coreParams.collateral = address(collateral);
            vaultParams.asset = address(collateral);
        }
        if (coreParams.collateral != address(0)) {
            require(vaultParams.asset == coreParams.collateral, "vault asset does not match collateral");
        }

        if (initializeLocalMarkets && block.chainid == 31337 && marketConfigList.length > 0) {
            createLocalMarkets(salt);
        }

        // testnet only: mock the adapter target vaults and mint the collateral the dead deposit needs
        if (block.chainid == 11155111 || block.chainid == 31337) {
            deployMockTargets(salt);
            MockERC20(vaultParams.asset).mint(broadcaster, vaultParams.dead_deposit);
        }

        // deploy new vault with broadcaster as initial owner
        deployment.vault = IVaultV2(vaultFactory.createVaultV2(broadcaster, vaultParams.asset, salt));

        // deploy gate
        deployment.gate = new Gate(broadcaster);

        // set name and symbol
        deployment.vault.setName(vaultParams.name);
        deployment.vault.setSymbol(vaultParams.symbol);

        // transfer curator permissions to broadcaster
        deployment.vault.setCurator(broadcaster);

        // set broadcaster as allocator
        deployment.vault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (broadcaster, true)));
        deployment.vault.setIsAllocator(broadcaster, true);
    }

    function configureVault(VaultDeploymentResult memory deployment) internal {
        // deploy every adapter listed in the vault config; a fresh vault needs all of them,
        // so is_new_adapter is ignored (only DeployMorphoAdapter.s.sol respects it)
        deployment.adapters = new DeployedAdapter[](adapterParamsList.length);
        bytes memory liquidityData;
        for (uint256 i = 0; i < adapterParamsList.length; i++) {
            // load parameters
            AdapterParameters memory params = adapterParamsList[i];

            // deploy adapter
            params.parent = address(deployment.vault);
            params.asset = vaultParams.asset;
            (, address adapter) = deployAdapter(params);
            deployment.adapters[i] = DeployedAdapter(IAdapter(adapter), params.adapter_type, params.name);

            // set liquidity adapter if configured
            if (stringMatches(vaultParams.adapters[i], vaultParams.liquidity_adapter)) {
                deployment.liquidity_adapter = IAdapter(adapter);
                if (stringMatches(params.adapter_type, "GENERIC")) liquidityData = abi.encode(uint256(0));
            }
        }
        require(address(deployment.liquidity_adapter) != address(0), "liquidity adapter not deployed");

        // add adapters (submit + immediate call works because timelocks are configured last)
        for (uint256 i = 0; i < deployment.adapters.length; i++) {
            deployment.vault.submit(abi.encodeCall(IVaultV2.addAdapter, address(deployment.adapters[i].adapter)));
            deployment.vault.addAdapter(address(deployment.adapters[i].adapter));
        }

        // set each adapter's caps from its config, keyed by adapterId
        for (uint256 i = 0; i < deployment.adapters.length; i++) {
            bytes memory adapterId = abi.encode("this", deployment.adapters[i].adapter);
            deployment.vault
                .submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (adapterId, adapterParamsList[i].absolute_cap)));
            deployment.vault
                .submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (adapterId, adapterParamsList[i].relative_cap)));
            deployment.vault.increaseAbsoluteCap(adapterId, adapterParamsList[i].absolute_cap);
            deployment.vault.increaseRelativeCap(adapterId, adapterParamsList[i].relative_cap);
        }

        // record the configured markets and cap each one on the vault
        deployment.markets = new DeployedMarket[](marketConfigList.length);
        for (uint256 i = 0; i < marketConfigList.length; i++) {
            deployment.markets[i] = DeployedMarket(marketConfigList[i].name, toMarketParams(marketConfigList[i]));
        }
        if (deployment.markets.length > 0) capMarkets(deployment);

        // set max rate
        deployment.vault.submit(abi.encodeCall(IVaultV2.setMaxRate, (vaultParams.max_rate)));
        deployment.vault.setMaxRate(vaultParams.max_rate);

        // enable liquidity adapter
        deployment.vault.setLiquidityAdapterAndData(address(deployment.liquidity_adapter), liquidityData);

        // perform dead deposit
        IERC20(deployment.vault.asset()).approve(address(deployment.vault), vaultParams.dead_deposit);
        deployment.vault.deposit(vaultParams.dead_deposit, address(0xdead)); // Dead address for burned shares

        // set sentinel and allocators
        deployment.vault.submit(abi.encodeCall(IVaultV2.setIsSentinel, (vaultParams.sentinel, true)));
        deployment.vault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (vaultParams.allocator, true)));
        if (roles.rebalancer_role != vaultParams.allocator) {
            deployment.vault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (roles.rebalancer_role, true)));
        }
        deployment.vault.setIsSentinel(vaultParams.sentinel, true);
        deployment.vault.setIsAllocator(vaultParams.allocator, true);
        if (roles.rebalancer_role != vaultParams.allocator) {
            deployment.vault.setIsAllocator(roles.rebalancer_role, true);
        }

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

        // set timelock; market adapters gate their own submit on the vault's curator, so this has to
        // run while the broadcaster still holds that role
        for (uint256 i = 0; i < deployment.adapters.length; i++) {
            if (stringMatches(deployment.adapters[i].adapter_type, "MARKET")) {
                configureMarketAdapterTimelock(
                    IMorphoMarketV1AdapterV2(address(deployment.adapters[i].adapter)), vaultParams.timelock_duration
                );
            }
        }
        configureTimelock(deployment.vault, vaultParams.timelock_duration);

        deployment.vault.setCurator(vaultParams.curator);
        deployment.vault.setOwner(vaultParams.owner);
    }

    /// @notice Deploy and configure the selected core protocol contracts.
    /// @notice An indicative starting price for `assetSymbol`, USD at 18 decimals.
    /// @dev Mirrors the asset dispatch used for the real adapters, so the two stay side by side.
    function mockOraclePrice(string memory assetSymbol) internal pure returns (uint256) {
        if (stringMatches(assetSymbol, "tGLD")) return MOCK_ORACLE_PRICE_GLD;
        if (stringMatches(assetSymbol, "tBRL")) return MOCK_ORACLE_PRICE_BRL;
        if (stringMatches(assetSymbol, "tMXN")) return MOCK_ORACLE_PRICE_MXN;
        return MOCK_ORACLE_PRICE_DEFAULT;
    }

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

        deployment.oracle_adapter = deployOracleAdapter(useMockIntegrations);

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
        // Mock deployments deliberately leave the controller oracle unset.
        if (!useMockIntegrations) {
            deployment.controller.setOracleAdapter(address(deployment.oracle_adapter));
        }
        deployment.controller.setOracleTolerance(uint96(coreParams.oracle_tolerance));
        deployment.controller.setBlockMintLimit(coreParams.mint_limit);
        deployment.controller.setBlockRedeemLimit(coreParams.redeem_limit);
        configureSigners(deployment, useMockIntegrations);

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

        // DeployNewAsset seeds staking with the dead deposit before roles are revoked.
        initializeStaking(deployment);

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

    function initializeStaking(CoreDeploymentResult memory) internal virtual {}

    function deployOracleAdapter(bool useMockIntegrations) internal virtual returns (IOracleAdapter adapter) {
        if (useMockIntegrations) {
            // A real adapter cannot be used here: each one hardcodes a mainnet Chainlink
            // aggregator, which does not exist on a fresh chain, so `getPrice` would revert every
            // block. This used to be the zero address, which made the engine report a chain-state
            // price of zero for every local and e2e run (ENG-2664).
            adapter = IOracleAdapter(address(new MockOracleAdapter(mockOraclePrice(coreParams.asset_symbol))));
        } else if (stringMatches(coreParams.asset_symbol, "tGLD")) {
            adapter = IOracleAdapter(address(new GoldOracleAdapter()));
            require(adapter.oracle() == coreParams.oracle, "oracle mismatch");
        } else if (stringMatches(coreParams.asset_symbol, "tBRL")) {
            adapter = IOracleAdapter(address(new BRLOracleAdapter()));
            require(adapter.oracle() == coreParams.oracle, "oracle mismatch");
        } else if (stringMatches(coreParams.asset_symbol, "tMXN")) {
            adapter = IOracleAdapter(address(new MXNOracleAdapter()));
            require(adapter.oracle() == coreParams.oracle, "oracle mismatch");
        } else {
            require(coreParams.oracle == address(0), "oracle mismatch");
            adapter = IOracleAdapter(address(0));
        }
    }

    function configureSigners(CoreDeploymentResult memory deployment, bool useMockIntegrations) internal virtual {
        if (useMockIntegrations) deployment.controller.setSignerStatus(coreParams.signer, true);
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
        console2.log("Vault Timelock increases executed for", timelockedSelectors.length, "functions");
    }

    /// @notice Configure timelock settings for adapter functions
    function configureMarketAdapterTimelock(IMorphoMarketV1AdapterV2 adapter, uint256 timelock_duration) internal {
        // Define function selectors that should be timelocked
        bytes4[] memory timelockedSelectors = marketAdapterTimelockSelectors();

        // Submit timelock increases for all selectors
        for (uint256 i = 0; i < timelockedSelectors.length; i++) {
            adapter.submit(abi.encodeCall(adapter.increaseTimelock, (timelockedSelectors[i], timelock_duration)));
        }
        console2.log("Adapter timelock increases submitted for", timelockedSelectors.length, "functions");

        // Execute timelock increases for all selectors
        for (uint256 i = 0; i < timelockedSelectors.length; i++) {
            adapter.increaseTimelock(timelockedSelectors[i], timelock_duration);
        }
        console2.log("Adapter timelock increases executed for", timelockedSelectors.length, "functions");
    }

    /* ------------------------------------ SERIALIZATION ------------------------------------------ */

    function outputDirectory() internal view virtual returns (string memory) {
        return string.concat("broadcast/Deploy.s.sol/", vm.toString(block.chainid));
    }

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
        string memory path = outputDirectory();
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

        string memory path = outputDirectory();
        vm.createDir(path, true);
        vm.writeJson(obj, string.concat(path, "/contracts.json"));
    }

    function serializeVaultOnly(VaultDeploymentResult memory vaultResult) internal {
        console2.log("\nSerializing json...\n");
        string memory path = outputDirectory();
        vm.createDir(path, true);
        vm.writeJson(serializeVault(vaultResult), string.concat(path, "/vault.json"));
    }

    // Builds the vault JSON from the vault deployment result
    function serializeVault(VaultDeploymentResult memory vaultResult) internal returns (string memory vaultJson) {
        // adapter objects, keys in alphabetical order to match the hand-curated deployments.json
        string memory adaptersArr;
        for (uint256 i = 0; i < vaultResult.adapters.length; i++) {
            string memory key = string.concat("adapter_obj_", vm.toString(i));
            address adapter = address(vaultResult.adapters[i].adapter);
            string memory adapterObj = vm.serializeString(key, "adapter_type", vaultResult.adapters[i].adapter_type);
            adapterObj = vm.serializeAddress(key, "address", adapter);
            adapterObj = vm.serializeBytes32(key, "id", keccak256(abi.encode("this", adapter)));
            adapterObj = vm.serializeString(key, "name", vaultResult.adapters[i].name);
            adaptersArr = i == 0 ? adapterObj : string.concat(adaptersArr, ",", adapterObj);
        }

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

        // market objects, ids precomputed so the backend never re-derives solidity abi encodings
        string memory marketsArr;
        for (uint256 i = 0; i < vaultResult.markets.length; i++) {
            string memory key = string.concat("market_obj_", vm.toString(i));
            MarketParams memory marketParams = vaultResult.markets[i].params;
            string memory marketObj = vm.serializeBytes32(
                key,
                "cap_id",
                keccak256(abi.encode("this/marketParams", marketAdapterAddress(vaultResult), marketParams))
            );
            marketObj = vm.serializeBytes32(
                key, "collateral_cap_id", keccak256(abi.encode("collateralToken", marketParams.collateralToken))
            );
            marketObj = vm.serializeAddress(key, "collateral_token", marketParams.collateralToken);
            marketObj = vm.serializeBytes32(key, "id", Id.unwrap(marketParams.id()));
            marketObj = vm.serializeAddress(key, "irm", marketParams.irm);
            marketObj = vm.serializeBytes32(key, "lltv", bytes32(marketParams.lltv));
            marketObj = vm.serializeAddress(key, "loan_token", marketParams.loanToken);
            marketObj = vm.serializeString(key, "name", vaultResult.markets[i].name);
            marketObj = vm.serializeAddress(key, "oracle", marketParams.oracle);
            marketsArr = i == 0 ? marketObj : string.concat(marketsArr, ",", marketObj);
        }

        // Build vault object
        // concatenated by hand: vm.serialize* escapes array-of-object strings instead of embedding them
        vaultJson = string.concat(
            '{"adapters":[',
            adaptersArr,
            '],"config":',
            configObj,
            ',"contracts":',
            contractsObj,
            ',"markets":[',
            marketsArr,
            '],"roles":',
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
        for (uint256 i = 0; i < vaultResult.adapters.length; i++) {
            console2.log("Adapter: ", address(vaultResult.adapters[i].adapter));
            console2.log("  type: ", vaultResult.adapters[i].adapter_type);
            console2.log("  name: ", vaultResult.adapters[i].name);
        }
        console2.log("Liquidity adapter: ", address(vaultResult.liquidity_adapter));
        console2.log("Gate: ", address(vaultResult.gate));
        console2.log("\n=============================================================\n");
    }
}
