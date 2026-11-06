// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/console2.sol";
import {DeployBase} from "./DeployBase.s.sol";
import {GenericMorphoAdapterFactory} from "deploy-target/src/external/morpho/GenericMorphoAdapterFactory.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IMorpho, Id, MarketParams} from "vault-v2/lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "vault-v2/lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {IMorphoMarketV1AdapterV2} from "vault-v2/src/adapters/interfaces/IMorphoMarketV1AdapterV2.sol";
import {IMorphoMarketV1AdapterV2Factory} from "vault-v2/src/adapters/interfaces/IMorphoMarketV1AdapterV2Factory.sol";
import {IMorphoVaultV1AdapterFactory} from "vault-v2/src/adapters/interfaces/IMorphoVaultV1AdapterFactory.sol";
import {IVaultV2} from "vault-v2/src/interfaces/IVaultV2.sol";
import {StdConfig} from "forge-std/StdConfig.sol";

/// @notice Shared morpho adapter deployment machinery: config loading, type dispatch, and per-chain
/// factory resolution. The adapter_type key selects the adapter:
/// - "VAULT": MorphoVaultV1Adapter allocating into a morpho v1 vault
/// - "MARKET": MorphoMarketV1AdapterV2 allocating into morpho blue markets (market wiring is a
///   separate curator operation via the adapter's own submit/timelock system)
/// - "GENERIC": GenericMorphoAdapter allocating into any ERC4626 vault
/// Mainnet and sepolia route through an already deployed factory; local dev deploys the factory first.
abstract contract MorphoAdapterDeployer is DeployBase {
    using MarketParamsLib for MarketParams;

    /// @notice USDC on Ethereum mainnet.
    address constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    /// @notice MorphoVaultV1AdapterFactory mainnet
    address constant VAULT_V1_ADAPTER_FACTORY_MAINNET = 0xD1B8E2dee25c2b89DCD2f98448a7ce87d6F63394;
    /// @notice MorphoVaultV1AdapterFactory sepolia
    address constant VAULT_V1_ADAPTER_FACTORY_SEPOLIA = 0x6a86a72C13cd29350A779befa70E3B08Cd870F84;
    /// @notice MorphoMarketV1AdapterV2Factory mainnet
    address constant MARKET_V1_ADAPTER_V2_FACTORY_MAINNET = 0x32BB1c0D48D8b1B3363e86eeB9A0300BAd61ccc1;
    /// @notice MorphoMarketV1AdapterV2Factory sepolia
    address constant MARKET_V1_ADAPTER_V2_FACTORY_SEPOLIA = 0x5481f54CACdf0aECE9f71F2Bb2c0A8e44b2d5D81;
    /// @notice GenericMorphoAdapterFactory mainnet
    address constant GENERIC_ADAPTER_FACTORY_MAINNET = 0x0Ef32Bd202A55Bb938Adf36814A1e545c1D2E86F;
    /// @notice GenericMorphoAdapterFactory sepolia
    address constant GENERIC_ADAPTER_FACTORY_SEPOLIA = 0x06569B453AFb7c9328FAe293213bc5227861F8ca;

    /// @notice Morpho blue singleton, resolved by resolveLocalMorphoSingletons
    address internal morphoBlue;
    /// @notice Adaptive curve IRM, resolved by resolveLocalMorphoSingletons
    address internal adaptiveCurveIrm;

    /// @notice Adapter parameters loaded from an adapter config file
    struct AdapterParameters {
        string adapter_type;
        address asset;
        address vault;
        address owner;
        address parent;
        bool is_new_adapter;
        string name;
        uint256 absolute_cap;
        uint256 relative_cap;
    }

    /// @notice Morpho market parameters loaded from a market config file
    struct MarketParameters {
        string name;
        address collateral_token;
        address oracle;
        address irm;
        uint256 lltv;
        uint256 absolute_cap;
        uint256 relative_cap;
    }

    /// @notice Validated data needed to configure an existing market adapter.
    struct ExistingMarketAdapterData {
        address factory;
        address adapter;
        MarketParams market_params;
        bytes adapter_id_data;
        bytes collateral_cap_id_data;
        bytes market_cap_id_data;
        bytes32 adapter_id;
        bytes32 market_id;
        bytes32 collateral_cap_id;
        bytes32 market_cap_id;
        uint256 absolute_cap;
        uint256 relative_cap;
    }

    /// @notice Load adapter parameters from an adapter config toml file. Call outside `broadcast`:
    /// a StdConfig deployed inside a broadcast would be recorded as a transaction.
    function loadAdapterParams(string memory configDir) internal returns (AdapterParameters memory params) {
        StdConfig adapterConfig = new StdConfig(configDir, false);
        vm.makePersistent(address(adapterConfig));

        params.adapter_type = adapterConfig.get("adapter_type").toString();
        params.asset = adapterConfig.get("asset").toAddress();
        params.vault = adapterConfig.get("vault").toAddress();
        params.owner = adapterConfig.get("owner").toAddress();
        params.parent = adapterConfig.get("parent").toAddress();
        params.is_new_adapter = adapterConfig.get("is_new_adapter").toBool();
        params.name = adapterConfig.get("name").toString();
        params.absolute_cap = adapterConfig.get("absolute_cap").toUint256();
        params.relative_cap = adapterConfig.get("relative_cap").toUint256();
    }

    /// @notice Resolve an adapter config path from its declaring vault config and adapter name.
    function adapterConfigPath(string memory vaultConfigDir, string memory name) internal pure returns (string memory) {
        string[] memory parts = vm.split(vaultConfigDir, "/vaults/");
        require(parts.length == 2, "vault config path must contain /vaults/");
        return string.concat(parts[0], "/adapters/", name, ".toml");
    }

    /// @notice Resolve a market config path from its declaring vault config and market name.
    function marketConfigPath(string memory vaultConfigDir, string memory name) internal pure returns (string memory) {
        string[] memory parts = vm.split(vaultConfigDir, "/vaults/");
        require(parts.length == 2, "vault config path must contain /vaults/");
        return string.concat(parts[0], "/markets/", name, ".toml");
    }

    /// @notice Load one market config. Call outside `broadcast` so StdConfig is not recorded as a transaction.
    function loadMarketParams(string memory configDir) internal returns (MarketParameters memory params) {
        StdConfig marketConfig = new StdConfig(configDir, false);
        vm.makePersistent(address(marketConfig));

        params.name = marketConfig.get("name").toString();
        params.collateral_token = marketConfig.get("collateral_token").toAddress();
        params.oracle = marketConfig.get("oracle").toAddress();
        params.irm = marketConfig.get("irm").toAddress();
        params.lltv = marketConfig.get("lltv").toUint256();
        params.absolute_cap = marketConfig.get("absolute_cap").toUint256();
        params.relative_cap = marketConfig.get("relative_cap").toUint256();
        if (block.chainid != 31337) {
            require(params.collateral_token != address(0), "collateral_token not set");
            require(params.oracle != address(0), "oracle not set");
            require(params.irm != address(0), "irm not set");
        }
    }

    /// @notice Full morpho market params; the loan asset is always the configured parent vault asset.
    function toMarketParams(MarketParameters memory params) internal view returns (MarketParams memory) {
        return MarketParams({
            loanToken: vaultParams.asset,
            collateralToken: params.collateral_token,
            oracle: params.oracle,
            irm: params.irm,
            lltv: params.lltv
        });
    }

    /// @notice Load and validate the configuration and deployment of an existing mainnet market adapter.
    function loadAndValidateExistingMarketAdapter(
        string memory adapterConfigDir,
        string memory vaultConfigDir,
        address adapter
    ) internal returns (AdapterParameters memory params, ExistingMarketAdapterData memory data) {
        require(block.chainid == 1, "existing adapter path is mainnet only");
        require(adapter != address(0) && adapter.code.length > 0, "adapter not deployed");

        params = loadAdapterParams(adapterConfigDir);
        loadVaultConfig(vaultConfigDir);

        require(!params.is_new_adapter, "existing adapter config must set is_new_adapter = false");
        require(stringMatches(params.adapter_type, "MARKET"), "existing adapter must be MARKET");
        require(params.vault == address(0), "market adapter target vault must be zero");
        require(params.asset == USDC_MAINNET && vaultParams.asset == USDC_MAINNET, "asset must be mainnet USDC");
        require(params.parent != address(0) && params.parent.code.length > 0, "parent vault not deployed");
        require(params.owner != address(0) && vaultParams.curator != address(0), "vault roles not configured");
        require(params.owner == vaultParams.owner, "adapter owner does not match vault config");
        require(IVaultV2(params.parent).asset() == USDC_MAINNET, "parent asset does not match config");
        require(IVaultV2(params.parent).owner() == params.owner, "parent owner does not match config");
        require(IVaultV2(params.parent).curator() == vaultParams.curator, "parent curator does not match config");
        require(vaultContainsAdapterConfig(adapterConfigDir, vaultConfigDir), "adapter config not declared by vault");

        IMorphoMarketV1AdapterV2 marketAdapter = IMorphoMarketV1AdapterV2(adapter);
        IMorphoMarketV1AdapterV2Factory factory = IMorphoMarketV1AdapterV2Factory(MARKET_V1_ADAPTER_V2_FACTORY_MAINNET);
        require(marketAdapter.factory() == address(factory), "adapter factory mismatch");
        require(factory.isMorphoMarketV1AdapterV2(adapter), "adapter not registered with factory");
        require(factory.morphoMarketV1AdapterV2(params.parent) == adapter, "adapter does not match parent lookup");
        require(marketAdapter.parentVault() == params.parent, "adapter parent mismatch");
        require(marketAdapter.asset() == USDC_MAINNET, "adapter asset mismatch");
        require(marketAdapter.morpho() == factory.morpho(), "adapter morpho mismatch");
        require(marketAdapter.adaptiveCurveIrm() == factory.adaptiveCurveIrm(), "adapter irm mismatch");
        string[] memory marketNames = vaultConfig.get("markets").toStringArray();
        require(marketNames.length == 1, "existing MARKET adapter requires exactly one market");
        MarketParameters memory configuredMarket = loadMarketParams(marketConfigPath(vaultConfigDir, marketNames[0]));
        MarketParams memory marketParams = toMarketParams(configuredMarket);
        require(marketParams.irm == marketAdapter.adaptiveCurveIrm(), "market irm does not match adapter");
        require(
            configuredMarket.absolute_cap == params.absolute_cap
                && configuredMarket.relative_cap == params.relative_cap,
            "market caps do not match adapter caps"
        );

        Id marketId = marketParams.id();
        MarketParams memory registeredParams = IMorpho(marketAdapter.morpho()).idToMarketParams(marketId);
        require(
            keccak256(abi.encode(registeredParams)) == keccak256(abi.encode(marketParams)),
            "derived market id not registered"
        );

        bytes memory adapterIdData = abi.encode("this", adapter);
        bytes memory collateralCapIdData = abi.encode("collateralToken", marketParams.collateralToken);
        bytes memory marketCapIdData = abi.encode("this/marketParams", adapter, marketParams);
        data = ExistingMarketAdapterData({
            factory: address(factory),
            adapter: adapter,
            market_params: marketParams,
            adapter_id_data: adapterIdData,
            collateral_cap_id_data: collateralCapIdData,
            market_cap_id_data: marketCapIdData,
            adapter_id: keccak256(adapterIdData),
            market_id: Id.unwrap(marketId),
            collateral_cap_id: keccak256(collateralCapIdData),
            market_cap_id: keccak256(marketCapIdData),
            absolute_cap: configuredMarket.absolute_cap,
            relative_cap: configuredMarket.relative_cap
        });
        require(marketAdapter.adapterId() == data.adapter_id, "adapter id mismatch");
    }

    /// @notice Whether an adapter config is declared by a vault config.
    function vaultContainsAdapterConfig(string memory adapterConfigDir, string memory vaultConfigDir)
        internal
        view
        returns (bool)
    {
        for (uint256 i = 0; i < vaultParams.adapters.length; i++) {
            if (stringMatches(adapterConfigPath(vaultConfigDir, vaultParams.adapters[i]), adapterConfigDir)) {
                return true;
            }
        }
        return false;
    }

    /// @notice Selectors whose timelocks are configured on every market adapter.
    function marketAdapterTimelockSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IMorphoMarketV1AdapterV2.abdicate.selector;
        selectors[1] = IMorphoMarketV1AdapterV2.setSkimRecipient.selector;
        selectors[2] = IMorphoMarketV1AdapterV2.burnShares.selector;
        selectors[3] = IMorphoMarketV1AdapterV2.increaseTimelock.selector;
    }

    /// @notice Deploy the adapter selected by params.adapter_type through its per-chain factory.
    function deployAdapter(AdapterParameters memory params) internal returns (address factory, address adapter) {
        require(IVaultV2(params.parent).asset() == params.asset, "parent asset does not match config");

        // deploy an adapter depending on adapter type
        if (stringMatches(params.adapter_type, "VAULT")) {
            require(params.vault != address(0), "vault not set");
            require(IERC4626(params.vault).asset() == params.asset, "vault asset does not match config");
            IMorphoVaultV1AdapterFactory vaultFactory = resolveVaultV1Factory();
            factory = address(vaultFactory);
            adapter = vaultFactory.createMorphoVaultV1Adapter(params.parent, params.vault);
        } else if (stringMatches(params.adapter_type, "MARKET")) {
            IMorphoMarketV1AdapterV2Factory marketFactory = resolveMarketV1V2Factory();
            factory = address(marketFactory);
            adapter = marketFactory.createMorphoMarketV1AdapterV2(params.parent);
        } else if (stringMatches(params.adapter_type, "GENERIC")) {
            require(params.vault != address(0), "vault not set");
            require(IERC4626(params.vault).asset() == params.asset, "vault asset does not match config");
            GenericMorphoAdapterFactory genericFactory = resolveGenericFactory();
            factory = address(genericFactory);
            adapter = genericFactory.createGenericMorphoAdapter(params.parent, params.vault, params.owner);
        } else {
            revert("unknown adapter_type");
        }
    }

    /// @notice Resolve the vault v1 adapter factory for the current chain, deploying it on local dev.
    function resolveVaultV1Factory() internal returns (IMorphoVaultV1AdapterFactory factory) {
        if (block.chainid == 1) return IMorphoVaultV1AdapterFactory(VAULT_V1_ADAPTER_FACTORY_MAINNET);
        if (block.chainid == 11155111) return IMorphoVaultV1AdapterFactory(VAULT_V1_ADAPTER_FACTORY_SEPOLIA);

        // local dev: deploy the factory using solc-0.8.28 compiled artifacts
        return IMorphoVaultV1AdapterFactory(
            deployCode("out/MorphoVaultV1AdapterFactory.sol/MorphoVaultV1AdapterFactory.json")
        );
    }

    /// @notice Resolve the market v1 adapter v2 factory for the current chain, deploying it on local dev.
    function resolveMarketV1V2Factory() internal returns (IMorphoMarketV1AdapterV2Factory factory) {
        // for known networks, use existing adapter factories
        if (block.chainid == 1) {
            require(MARKET_V1_ADAPTER_V2_FACTORY_MAINNET != address(0), "adapter factory not deployed on mainnet");
            return IMorphoMarketV1AdapterV2Factory(MARKET_V1_ADAPTER_V2_FACTORY_MAINNET);
        }
        if (block.chainid == 11155111) {
            require(MARKET_V1_ADAPTER_V2_FACTORY_SEPOLIA != address(0), "adapter factory not deployed on sepolia");
            return IMorphoMarketV1AdapterV2Factory(MARKET_V1_ADAPTER_V2_FACTORY_SEPOLIA);
        }

        // local dev: deploy the factory (and the morpho singletons it wraps) using compiled artifacts
        resolveLocalMorphoSingletons();
        return IMorphoMarketV1AdapterV2Factory(
            deployCode(
                "out/MorphoMarketV1AdapterV2Factory.sol/MorphoMarketV1AdapterV2Factory.json",
                abi.encode(morphoBlue, adaptiveCurveIrm)
            )
        );
    }

    /// @notice Local dev only: deploy the morpho blue + adaptive curve IRM singletons the market
    /// adapter factory and market creation need (solc-0.8.19 artifacts, see MorphoBlueArtifacts.sol).
    /// Idempotent. Mainnet/sepolia route through pre-deployed factories and never resolve these.
    function resolveLocalMorphoSingletons() internal {
        require(block.chainid != 1 && block.chainid != 11155111, "local dev only");
        if (morphoBlue != address(0)) return;
        morphoBlue = deployCode("out/Morpho.sol/Morpho.json", abi.encode(broadcaster));
        adaptiveCurveIrm = deployCode("out/AdaptiveCurveIrm.sol/AdaptiveCurveIrm.json", abi.encode(morphoBlue));
    }

    /// @notice Resolve the generic adapter factory for the current chain, deploying it on local dev.
    function resolveGenericFactory() internal returns (GenericMorphoAdapterFactory factory) {
        if (block.chainid == 1) {
            require(GENERIC_ADAPTER_FACTORY_MAINNET != address(0), "adapter factory not deployed on mainnet");
            return GenericMorphoAdapterFactory(GENERIC_ADAPTER_FACTORY_MAINNET);
        }
        if (block.chainid == 11155111) {
            require(GENERIC_ADAPTER_FACTORY_SEPOLIA != address(0), "adapter factory not deployed on sepolia");
            return GenericMorphoAdapterFactory(GENERIC_ADAPTER_FACTORY_SEPOLIA);
        }

        // local dev: deploy the factory alongside the adapter, or reuse the one an earlier run
        // deployed — repeating the deterministic CREATE2 with the same salt and bytecode would revert.
        // The proxy is called directly so the factory lands at the predicted address in every context.
        bytes memory initCode = type(GenericMorphoAdapterFactory).creationCode;
        address predicted = computeCreate2Address(SALT, keccak256(initCode));
        if (predicted.code.length == 0) {
            (bool success,) = CREATE2_FACTORY.call(abi.encodePacked(SALT, initCode));
            require(success && predicted.code.length > 0, "generic factory deployment failed");
        }
        return GenericMorphoAdapterFactory(predicted);
    }
}
