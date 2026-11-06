// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Id, MarketParams} from "vault-v2/lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "vault-v2/lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {DeployBase} from "../../script/DeployBase.s.sol";
import {MorphoAdapterDeployer} from "../../script/MorphoAdapterDeployer.s.sol";
import {MainnetMorphoMarketConfigHarness} from "../harness/MainnetMorphoMarketConfigHarness.sol";

contract MainnetMorphoMarketConfigTest is Test {
    using MarketParamsLib for MarketParams;

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant OWNER = 0x698c6d3726846C4AD4Dc9331862b92Cd80D2fb99;
    address internal constant IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    uint256 internal constant ABSOLUTE_CAP = 1_000_000_000000;
    uint256 internal constant RELATIVE_CAP = 200000000000000000;
    uint256 internal constant LLTV = 860000000000000000;

    struct ConfigCase {
        string vault_config;
        string liquidity_adapter;
        string market_adapter;
        string[3] generic_adapters;
        string market_name;
        address parent;
        address collateral;
        address oracle;
        bytes32 market_id;
    }

    function test_MainnetMarketConfigs() public {
        vm.chainId(1);
        ConfigCase[3] memory cases = configCases();
        MainnetMorphoMarketConfigHarness harness = new MainnetMorphoMarketConfigHarness();

        for (uint256 i = 0; i < cases.length; i++) {
            assertConfig(harness, cases[i]);
        }
    }

    function test_RevertWhenMarketIsLiquidityAdapter() public {
        vm.chainId(1);
        ConfigCase memory config = configCases()[0];
        MainnetMorphoMarketConfigHarness harness = new MainnetMorphoMarketConfigHarness();
        vm.expectRevert("liquidity_adapter must be VAULT or GENERIC");
        harness.loadWithLiquidityAdapter(config.vault_config, config.market_adapter);
    }

    function assertConfig(MainnetMorphoMarketConfigHarness harness, ConfigCase memory expected) internal {
        harness.load(expected.vault_config);
        DeployBase.VaultParameters memory vault = harness.vaultParameters();
        assertEq(vault.asset, USDC, "vault asset");
        assertEq(vault.owner, OWNER, "vault owner");
        assertEq(vault.adapters.length, 4, "vault adapter references");
        assertEq(vault.adapters[2], expected.liquidity_adapter, "liquidity adapter reference");
        assertEq(vault.adapters[0], expected.market_adapter, "market adapter reference");
        assertEq(vault.liquidity_adapter, expected.liquidity_adapter, "liquidity adapter");
        assertEq(harness.adapterCount(), 4, "resolved adapter count");
        assertEq(harness.marketCount(), 1, "resolved market count");
        address[3] memory targets = [
            0x73edDFa87C71ADdC275c2b9890f5c3a8480bC9E6,
            0xbeef088055857739C12CD3765F20b7679Def0f51,
            0xBc65ad17c5C0a2A4D159fa5a503f4992c7B545FE
        ];
        for (uint256 i = 0; i < targets.length; i++) {
            assertEq(vault.adapters[i + 1], expected.generic_adapters[i], "generic adapter reference");
            MorphoAdapterDeployer.AdapterParameters memory generic = harness.adapterParameters(i + 1);
            assertEq(generic.adapter_type, "GENERIC", "generic adapter type");
            assertEq(generic.parent, expected.parent, "generic adapter parent");
            assertEq(generic.asset, USDC, "generic adapter asset");
            assertEq(generic.vault, targets[i], "generic adapter target");
            assertEq(generic.owner, OWNER, "generic adapter owner");
            assertFalse(generic.is_new_adapter, "generic adapter must already be deployed");
            assertEq(generic.absolute_cap, i == 1 ? 100_000_000_000000 : 20_000_000_000000, "generic absolute cap");
            assertEq(generic.relative_cap, i == 1 ? 1e18 : 5e17, "generic relative cap");
        }

        MorphoAdapterDeployer.AdapterParameters memory adapter = harness.adapterParameters(0);
        assertEq(adapter.adapter_type, "MARKET", "adapter type");
        assertEq(adapter.name, expected.market_name, "adapter name");
        assertEq(adapter.parent, expected.parent, "adapter parent");
        assertEq(adapter.asset, USDC, "adapter asset");
        assertEq(adapter.vault, address(0), "adapter target vault");
        assertEq(adapter.owner, OWNER, "adapter owner");
        assertFalse(adapter.is_new_adapter, "adapter must already be deployed");
        assertEq(adapter.absolute_cap, ABSOLUTE_CAP, "adapter absolute cap");
        assertEq(adapter.relative_cap, RELATIVE_CAP, "adapter relative cap");

        (MorphoAdapterDeployer.MarketParameters memory configured, MarketParams memory market) =
            harness.marketParameters(0);
        assertEq(configured.name, expected.market_name, "market name");
        assertEq(market.loanToken, USDC, "market loan token");
        assertEq(market.collateralToken, expected.collateral, "market collateral");
        assertEq(market.oracle, expected.oracle, "market oracle");
        assertEq(market.irm, IRM, "market irm");
        assertEq(market.lltv, LLTV, "market lltv");
        assertEq(Id.unwrap(market.id()), expected.market_id, "derived market id");
        assertEq(configured.absolute_cap, adapter.absolute_cap, "market absolute cap");
        assertEq(configured.relative_cap, adapter.relative_cap, "market relative cap");
    }

    function configCases() internal pure returns (ConfigCase[3] memory cases) {
        cases[0] = ConfigCase({
            vault_config: "./config/mainnet/tbrl/vaults/tbrl_usdc_vault.toml",
            liquidity_adapter: "tbrl_usdc_steakhousev2_adapter",
            market_adapter: "tbrl_usdc_market_adapter",
            generic_adapters: ["tbrl_usdc_aave_adapter", "tbrl_usdc_steakhousev2_adapter", "tbrl_usdc_spark_adapter"],
            market_name: "stBRL/USDC",
            parent: 0xE275a69B93A5745e1560ee82D033205D323BfAd9,
            collateral: 0xDaB276F6E19CCC54cA5aaA2645A94087ca776a3f,
            oracle: 0x17CD3E35B513B8174334593D203fEa3c44723DBC,
            market_id: 0xcac5902b997725b46ff9cc1eecc7607d566f591d88904daf6b4491f060495308
        });
        cases[1] = ConfigCase({
            vault_config: "./config/mainnet/tgld/vaults/tgld_usdc_vault.toml",
            liquidity_adapter: "tgld_usdc_steakhousev2_adapter",
            market_adapter: "tgld_usdc_market_adapter",
            generic_adapters: ["tgld_usdc_aave_adapter", "tgld_usdc_steakhousev2_adapter", "tgld_usdc_spark_adapter"],
            market_name: "stGLD/USDC",
            parent: 0x7290245b3e564f0Ae2dA5af0690eF4842CF13c75,
            collateral: 0x8d301801d899dC81fEabBDE69407A53b82bdBF19,
            oracle: 0x150dB979573A2344dFC2Ee0D635194d0a71CEA19,
            market_id: 0x3c2ce083d3ac6329ae69fd68bf23d4fada5587271860d987788dfd4f0ac3b5f0
        });
        cases[2] = ConfigCase({
            vault_config: "./config/mainnet/tmxn/vaults/tmxn_usdc_vault.toml",
            liquidity_adapter: "tmxn_usdc_steakhousev2_adapter",
            market_adapter: "tmxn_usdc_market_adapter",
            generic_adapters: ["tmxn_usdc_aave_adapter", "tmxn_usdc_steakhousev2_adapter", "tmxn_usdc_spark_adapter"],
            market_name: "stMXN/USDC",
            parent: 0x43E3f5e27422C3a938269368eb7c3A3B545Bb6ca,
            collateral: 0x8BDf6A2DFda084bD242Cd285CF75E80de3eB00ba,
            oracle: 0x51aAA61b6de864F9a41d968ce6b067322536d95A,
            market_id: 0x245859412ff82dabcea25ddab15fe5ee5650e20b1af05f65ea1bd8db96416522
        });
    }
}
