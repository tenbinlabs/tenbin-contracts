// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {GenericMorphoAdapter} from "tenbin-contracts/src/external/morpho/GenericMorphoAdapter.sol";
import {GenericMorphoAdapterFactory} from "tenbin-contracts/src/external/morpho/GenericMorphoAdapterFactory.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IMorpho, Id, MarketParams} from "vault-v2/lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "vault-v2/lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {IMorphoMarketV1AdapterV2} from "vault-v2/src/adapters/interfaces/IMorphoMarketV1AdapterV2.sol";
import {IMorphoVaultV1Adapter} from "vault-v2/src/adapters/interfaces/IMorphoVaultV1Adapter.sol";
import {IAdapter} from "vault-v2/src/interfaces/IAdapter.sol";
import {IVaultV2} from "vault-v2/src/interfaces/IVaultV2.sol";
import {VaultChecksBase} from "./VaultChecksBase.sol";

/// @notice Adapter, cap, and market state of the deployed vault must match its config
abstract contract AdapterChecksBase is VaultChecksBase {
    using MarketParamsLib for MarketParams;

    /// @notice Morpho Blue singleton on mainnet
    address internal constant MORPHO_BLUE = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;

    /// @notice Adapter config joined with its deployment
    struct AdapterConfig {
        string adapterType;
        string name;
        address addr;
        bytes32 id;
        address target;
        address owner;
        uint256 absoluteCap;
        uint256 relativeCap;
    }

    /// @notice Market config joined with its deployed cap ids
    struct MarketConfig {
        MarketParams params;
        bytes32 id;
        bytes32 capId;
        bytes32 collateralCapId;
        uint256 absoluteCap;
        uint256 relativeCap;
    }

    AdapterConfig[] internal adapterConfigs;
    MarketConfig[] internal marketConfigs;
    address internal configuredLiquidityAdapter;
    address internal genericAdapterFactory;
    address internal marketAdapterFactory;

    function setUp() public virtual override {
        super.setUp();
        string memory configDir = string.concat("./config/mainnet/", toLower(assetName));
        string memory vaultToml =
            vm.readFile(string.concat(configDir, "/vaults/", toLower(assetName), "_usdc_vault.toml"));
        // forge-lint: disable-next-line(unsafe-cheatcode)
        string memory json = vm.readFile("./deployments.json");
        string memory vaultPath = string.concat(".mainnet.", assetName, ".vault");

        string[] memory adapterNames = vm.parseTomlStringArray(vaultToml, ".mainnet.string.adapters");
        string memory liquidityAdapterName = vm.parseTomlString(vaultToml, ".mainnet.string.liquidity_adapter");
        for (uint256 i = 0; i < adapterNames.length; i++) {
            string memory toml = vm.readFile(string.concat(configDir, "/adapters/", adapterNames[i], ".toml"));
            AdapterConfig memory config = AdapterConfig({
                adapterType: vm.parseTomlString(toml, ".mainnet.string.adapter_type"),
                name: vm.parseTomlString(toml, ".mainnet.string.name"),
                addr: address(0),
                id: bytes32(0),
                target: vm.parseTomlAddress(toml, ".mainnet.address.vault"),
                owner: vm.parseTomlAddress(toml, ".mainnet.address.owner"),
                absoluteCap: vm.parseTomlUint(toml, ".mainnet.uint.absolute_cap"),
                relativeCap: vm.parseTomlUint(toml, ".mainnet.uint.relative_cap")
            });
            (config.addr, config.id) = deployedAdapter(config.name);
            adapterConfigs.push(config);
            if (_eq(adapterNames[i], liquidityAdapterName)) configuredLiquidityAdapter = config.addr;
        }

        string[] memory marketNames = vm.parseTomlStringArray(vaultToml, ".mainnet.string.markets");
        assertFalse(vm.keyExistsJson(json, string.concat(vaultPath, ".markets[", vm.toString(marketNames.length), "]")));
        for (uint256 i = 0; i < marketNames.length; i++) {
            string memory toml = vm.readFile(string.concat(configDir, "/markets/", marketNames[i], ".toml"));
            string memory marketPath = string.concat(vaultPath, ".markets[", vm.toString(i), "]");
            assertEq(
                vm.parseJsonString(json, string.concat(marketPath, ".name")),
                vm.parseTomlString(toml, ".mainnet.string.name")
            );
            marketConfigs.push(
                MarketConfig({
                    params: MarketParams({
                        loanToken: vaultParams.asset,
                        collateralToken: vm.parseTomlAddress(toml, ".mainnet.address.collateral_token"),
                        oracle: vm.parseTomlAddress(toml, ".mainnet.address.oracle"),
                        irm: vm.parseTomlAddress(toml, ".mainnet.address.irm"),
                        lltv: vm.parseTomlUint(toml, ".mainnet.uint.lltv")
                    }),
                    id: vm.parseJsonBytes32(json, string.concat(marketPath, ".id")),
                    capId: vm.parseJsonBytes32(json, string.concat(marketPath, ".cap_id")),
                    collateralCapId: vm.parseJsonBytes32(json, string.concat(marketPath, ".collateral_cap_id")),
                    absoluteCap: vm.parseTomlUint(toml, ".mainnet.uint.absolute_cap"),
                    relativeCap: vm.parseTomlUint(toml, ".mainnet.uint.relative_cap")
                })
            );
        }

        genericAdapterFactory = vm.parseJsonAddress(json, ".mainnet.global.factories.generic_morpho_adapter");
        marketAdapterFactory = vm.parseJsonAddress(json, ".mainnet.global.factories.morpho_market_v1_adapter_v2");
    }

    // Every enabled adapter must be covered. A disabled adapter (both caps zero) may drop its config.
    function testAdapterConfigCoverage() public view {
        IVaultV2 vault = IVaultV2(vaultContracts.vault);
        for (uint256 i = 0; i < vaultAdapters.length; i++) {
            bytes32 id = vaultAdapters[i].id;
            if (vault.absoluteCap(id) == 0 && vault.relativeCap(id) == 0) continue;
            adapterConfig(vaultAdapters[i].addr);
        }
    }

    // Liquidity adapter and data must match what Deploy sets for the configured adapter
    function testLiquidityAdapterConfig() public view {
        IVaultV2 vault = IVaultV2(vaultContracts.vault);
        assertEq(vault.liquidityAdapter(), configuredLiquidityAdapter);
        AdapterConfig memory config = adapterConfig(configuredLiquidityAdapter);
        bytes memory expectedData = _eq(config.adapterType, "GENERIC") ? abi.encode(uint256(0)) : bytes("");
        assertEq(vault.liquidityData(), expectedData);
    }

    // Adapter and market caps must match config. A disabled adapter (both caps zero) is being wound down
    // and keeps its config until removed.
    function testAdapterCaps() public view {
        IVaultV2 vault = IVaultV2(vaultContracts.vault);
        for (uint256 i = 0; i < adapterConfigs.length; i++) {
            bytes32 id = adapterConfigs[i].id;
            if (vault.absoluteCap(id) == 0 && vault.relativeCap(id) == 0) continue;
            assertEq(vault.absoluteCap(id), adapterConfigs[i].absoluteCap, adapterConfigs[i].name);
            assertEq(vault.relativeCap(id), adapterConfigs[i].relativeCap, adapterConfigs[i].name);
        }
        for (uint256 i = 0; i < marketConfigs.length; i++) {
            MarketConfig memory market = marketConfigs[i];
            assertEq(vault.absoluteCap(market.capId), market.absoluteCap);
            assertEq(vault.relativeCap(market.capId), market.relativeCap);
            assertEq(vault.absoluteCap(market.collateralCapId), market.absoluteCap);
            assertEq(vault.relativeCap(market.collateralCapId), market.relativeCap);
        }
    }

    // Each adapter must point at its configured parent, target, and owner
    function testAdapterIdentity() public view {
        for (uint256 i = 0; i < adapterConfigs.length; i++) {
            AdapterConfig memory config = adapterConfigs[i];
            if (_eq(config.adapterType, "GENERIC")) {
                GenericMorphoAdapter adapter = GenericMorphoAdapter(config.addr);
                assertEq(address(adapter.parentVault()), vaultContracts.vault, config.name);
                assertEq(address(adapter.vault()), config.target, config.name);
                assertEq(adapter.asset(), vaultParams.asset, config.name);
                assertEq(adapter.adapterId(), config.id, config.name);
                assertEq(adapter.owner(), config.owner, config.name);
                assertEq(adapter.pendingOwner(), address(0), config.name);
                assertTrue(GenericMorphoAdapterFactory(genericAdapterFactory).isGenericMorphoAdapter(config.addr));
            } else if (_eq(config.adapterType, "VAULT")) {
                IMorphoVaultV1Adapter adapter = IMorphoVaultV1Adapter(config.addr);
                assertEq(adapter.parentVault(), vaultContracts.vault, config.name);
                assertEq(adapter.morphoVaultV1(), config.target, config.name);
                assertEq(adapter.adapterId(), config.id, config.name);
            } else if (_eq(config.adapterType, "MARKET")) {
                IMorphoMarketV1AdapterV2 adapter = IMorphoMarketV1AdapterV2(config.addr);
                assertEq(adapter.factory(), marketAdapterFactory, config.name);
                assertEq(adapter.parentVault(), vaultContracts.vault, config.name);
                assertEq(adapter.asset(), vaultParams.asset, config.name);
                assertEq(adapter.morpho(), MORPHO_BLUE, config.name);
                assertEq(adapter.adapterId(), config.id, config.name);
                // the rebalancing engine only moves a market adapter with a single market
                assertLe(adapter.marketIdsLength(), 1, config.name);
                for (uint256 j = 0; j < adapter.marketIdsLength(); j++) {
                    assertTrue(isConfiguredMarket(adapter.marketIds(j)), config.name);
                }
            } else {
                revert(string.concat("unknown adapter type: ", config.adapterType));
            }
        }
    }

    // Market params and cap ids must match config
    function testMarketConfig() public view {
        AdapterConfig memory marketAdapter = adapterConfigOfType("MARKET");
        IMorphoMarketV1AdapterV2 adapter = IMorphoMarketV1AdapterV2(marketAdapter.addr);
        for (uint256 i = 0; i < marketConfigs.length; i++) {
            MarketConfig memory market = marketConfigs[i];
            assertEq(Id.unwrap(market.params.id()), market.id);
            MarketParams memory onchain = IMorpho(MORPHO_BLUE).idToMarketParams(Id.wrap(market.id));
            assertEq(onchain.loanToken, market.params.loanToken);
            assertEq(onchain.collateralToken, market.params.collateralToken);
            assertEq(onchain.oracle, market.params.oracle);
            assertEq(onchain.irm, market.params.irm);
            assertEq(onchain.lltv, market.params.lltv);

            bytes32[] memory ids = adapter.ids(market.params);
            assertEq(ids[0], marketAdapter.id);
            assertEq(ids[1], market.collateralCapId);
            assertEq(ids[2], market.capId);
        }
    }

    // Every read the execution engine makes each block must succeed
    function testEngineReadPath() public view {
        for (uint256 i = 0; i < adapterConfigs.length; i++) {
            AdapterConfig memory config = adapterConfigs[i];
            IAdapter(config.addr).realAssets();
            if (_eq(config.adapterType, "MARKET")) {
                for (uint256 j = 0; j < marketConfigs.length; j++) {
                    IMorpho(MORPHO_BLUE).market(Id.wrap(marketConfigs[j].id));
                    IMorphoMarketV1AdapterV2(config.addr).expectedSupplyAssets(marketConfigs[j].id);
                }
            } else {
                IERC4626(config.target).convertToAssets(1e27);
                IERC4626(config.target).maxWithdraw(config.addr);
            }
        }
    }

    // Deployed address and id of the adapter named `name` in deployments.json
    function deployedAdapter(string memory name) internal view returns (address, bytes32) {
        for (uint256 i = 0; i < vaultAdapters.length; i++) {
            if (_eq(vaultAdapters[i].name, name)) return (vaultAdapters[i].addr, vaultAdapters[i].id);
        }
        revert(string.concat("adapter not deployed: ", name));
    }

    function adapterConfig(address addr) internal view returns (AdapterConfig memory) {
        for (uint256 i = 0; i < adapterConfigs.length; i++) {
            if (adapterConfigs[i].addr == addr) return adapterConfigs[i];
        }
        revert("adapter not configured");
    }

    function adapterConfigOfType(string memory adapterType) internal view returns (AdapterConfig memory) {
        for (uint256 i = 0; i < adapterConfigs.length; i++) {
            if (_eq(adapterConfigs[i].adapterType, adapterType)) return adapterConfigs[i];
        }
        revert(string.concat("no adapter of type ", adapterType));
    }

    function isConfiguredMarket(bytes32 id) internal view returns (bool) {
        for (uint256 i = 0; i < marketConfigs.length; i++) {
            if (marketConfigs[i].id == id) return true;
        }
        return false;
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
