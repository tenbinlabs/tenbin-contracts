// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {DeployMorphoAdapter} from "script/DeployMorphoAdapter.s.sol";
import {ForkBaseTest} from "./ForkBaseTest.sol";
import {GenericMorphoAdapter} from "deploy-target/src/external/morpho/GenericMorphoAdapter.sol";
import {GenericMorphoAdapterFactory} from "deploy-target/src/external/morpho/GenericMorphoAdapterFactory.sol";
import {IMorphoMarketV1AdapterV2} from "vault-v2/src/adapters/interfaces/IMorphoMarketV1AdapterV2.sol";
import {IMorphoMarketV1AdapterV2Factory} from "vault-v2/src/adapters/interfaces/IMorphoMarketV1AdapterV2Factory.sol";
import {IMorphoVaultV1Adapter} from "vault-v2/src/adapters/interfaces/IMorphoVaultV1Adapter.sol";
import {IMorphoVaultV1AdapterFactory} from "vault-v2/src/adapters/interfaces/IMorphoVaultV1AdapterFactory.sol";
import {IVaultV2} from "vault-v2/src/interfaces/IVaultV2.sol";

/// @notice Exercises script/DeployMorphoAdapter.s.sol on a mainnet fork across adapter types and chains.
/// Branches the checked-in configs cannot reach (31337 path, market type, unused vault pair) use temp
/// TOML fixtures written to cache/test/adapters/, pointing at real mainnet contracts on the fork.
/// forge test --match-contract DeployMorphoAdapterForkTest -vvv
contract DeployMorphoAdapterForkTest is ForkBaseTest {
    // mainnet contracts (verified live at the fork block)
    address internal constant TGLD_PARENT_VAULT = 0x7290245b3e564f0Ae2dA5af0690eF4842CF13c75;
    address internal constant TBRL_PARENT_VAULT = 0xE275a69B93A5745e1560ee82D033205D323BfAd9;
    address internal constant STEAKHOUSE_USDC = 0xBEEF01735c132Ada46AA9aA4c54623cAA92A64CB;
    /// @dev Gauntlet USDC Prime — a morpho v1 vault with no adapter for the tGLD parent yet. The factory
    /// uses a zero CREATE2 salt, so an already-deployed pair (e.g. tBRL + Steakhouse) cannot be re-created.
    address internal constant GT_USDC = 0xdd0f28e19C1780eb6396170735D45153D261490d;
    address internal constant OWNER_MULTISIG = 0x698c6d3726846C4AD4Dc9331862b92Cd80D2fb99;
    address internal constant GENERIC_ADAPTER_FACTORY = 0x0Ef32Bd202A55Bb938Adf36814A1e545c1D2E86F;
    address internal constant MARKET_ADAPTER_FACTORY = 0x32BB1c0D48D8b1B3363e86eeB9A0300BAd61ccc1;
    address internal constant TBRL_MARKET_ADAPTER = 0x5fb8838114449eec7c67262418C5c3B6a0AFC882;
    address internal constant TGLD_MARKET_ADAPTER = 0x61a28892e8c0C9a7A0F6498754FF43Bf8093A53F;
    uint256 internal constant EXISTING_ADAPTER_FORK_BLOCK = 25844084;
    uint256 internal constant GENERIC_FACTORY_FORK_BLOCK = 25985062;
    /// @dev The factory keeps one market adapter per parent vault, so a deploy test must fork before
    /// the real tGLD adapter existed. Pinned explicitly rather than inherited from `forkBlock`.
    uint256 internal constant PRE_ADAPTER_FORK_BLOCK = 25383000;

    string internal constant FIXTURE_DIR = "cache/test/adapters/adapters/";
    string internal constant SKIP_CONFIG = "cache/test/adapters/adapters/existing_vault.toml";

    function setUp() public override {
        super.setUp();
        vm.createDir(FIXTURE_DIR, true);
        string memory existing = writeFixture(
            "existing_vault", "mainnet", "VAULT", address(usdc), STEAKHOUSE_USDC, OWNER_MULTISIG, TBRL_PARENT_VAULT
        );
        vm.writeFile(existing, vm.replace(vm.readFile(existing), "is_new_adapter = true", "is_new_adapter = false"));
    }

    /// @notice The vault type routes through the already deployed mainnet factory.
    function test_fork_DeployMorphoAdapter_VaultType() public {
        assertEq(block.chainid, 1, "expected a mainnet fork");
        string memory config = writeFixture(
            "vault_mainnet", "mainnet", "VAULT", address(usdc), GT_USDC, OWNER_MULTISIG, TGLD_PARENT_VAULT
        );

        DeployMorphoAdapter.DeploymentResult memory result = new DeployMorphoAdapter().run(config);
        IMorphoVaultV1Adapter adapter = IMorphoVaultV1Adapter(result.adapter);

        assertEq(result.broadcaster, getTestBroadcaster(), "unexpected broadcaster");
        assertEq(result.factory, VAULT_V1_ADAPTER_FACTORY_ADDRESS, "factory is not the mainnet factory");
        assertNotEq(result.adapter, address(0), "adapter not deployed");

        // adapter immutables
        assertEq(adapter.factory(), VAULT_V1_ADAPTER_FACTORY_ADDRESS, "adapter not deployed by the mainnet factory");
        assertEq(adapter.parentVault(), TGLD_PARENT_VAULT, "invalid parent vault");
        assertEq(adapter.morphoVaultV1(), GT_USDC, "invalid morpho v1 vault");
        assertEq(adapter.adapterId(), keccak256(abi.encode("this", result.adapter)), "invalid adapter id");

        // factory registration
        IMorphoVaultV1AdapterFactory factory = IMorphoVaultV1AdapterFactory(result.factory);
        assertTrue(factory.isMorphoVaultV1Adapter(result.adapter), "adapter not registered with the factory");
        assertEq(
            factory.morphoVaultV1Adapter(TGLD_PARENT_VAULT, GT_USDC),
            result.adapter,
            "factory lookup does not resolve to the adapter"
        );
    }

    /// @notice is_new_adapter = false skips the deployment entirely.
    function test_fork_DeployMorphoAdapter_Skip() public {
        DeployMorphoAdapter.DeploymentResult memory result = new DeployMorphoAdapter().run(SKIP_CONFIG);

        assertEq(result.broadcaster, getTestBroadcaster(), "unexpected broadcaster");
        assertEq(result.factory, address(0), "factory must not be set on skip");
        assertEq(result.adapter, address(0), "adapter must not be deployed on skip");
    }

    /// @notice The generic type routes through the configured mainnet factory.
    function test_fork_DeployMorphoAdapter_GenericFactoryMainnet() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), GENERIC_FACTORY_FORK_BLOCK);
        string memory config = writeFixture(
            "generic_mainnet", "mainnet", "GENERIC", address(usdc), GT_USDC, OWNER_MULTISIG, TGLD_PARENT_VAULT
        );
        DeployMorphoAdapter.DeploymentResult memory result = new DeployMorphoAdapter().run(config);
        GenericMorphoAdapter adapter = GenericMorphoAdapter(result.adapter);

        assertEq(result.factory, GENERIC_ADAPTER_FACTORY, "wrong generic factory");
        assertEq(address(adapter.parentVault()), TGLD_PARENT_VAULT, "invalid parent vault");
        assertEq(address(adapter.vault()), GT_USDC, "invalid target vault");
        assertTrue(GenericMorphoAdapterFactory(result.factory).isGenericMorphoAdapter(result.adapter));
    }

    /// @notice The market type routes through the configured mainnet factory.
    function test_fork_DeployMorphoAdapter_MarketFactoryMainnet() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), PRE_ADAPTER_FORK_BLOCK);
        string memory config = writeFixture(
            "market_mainnet", "mainnet", "MARKET", address(usdc), address(0), OWNER_MULTISIG, TGLD_PARENT_VAULT
        );
        DeployMorphoAdapter.DeploymentResult memory result =
            new DeployMorphoAdapter().run(config, writeMarketVaultFixture("mainnet"));
        IMorphoMarketV1AdapterV2 adapter = IMorphoMarketV1AdapterV2(result.adapter);

        assertEq(result.factory, MARKET_ADAPTER_FACTORY, "wrong market factory");
        assertEq(adapter.parentVault(), TGLD_PARENT_VAULT, "invalid parent vault");
        assertEq(adapter.asset(), address(usdc), "invalid adapter asset");
        assertTrue(IMorphoMarketV1AdapterV2Factory(result.factory).isMorphoMarketV1AdapterV2(result.adapter));
    }

    /// @notice The existing-adapter path validates the deployed tGLD adapter and derives its configured ids.
    function test_fork_DeployMorphoAdapter_ExistingMarketAdapter() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), EXISTING_ADAPTER_FORK_BLOCK);
        DeployMorphoAdapter.ExistingAdapterResult memory result = new DeployMorphoAdapter()
            .runExisting(
                "./config/mainnet/tgld/adapters/tgld_usdc_market_adapter.toml",
                "./config/mainnet/tgld/vaults/tgld_usdc_vault.toml",
                TGLD_MARKET_ADAPTER
            );

        assertEq(result.factory, MARKET_ADAPTER_FACTORY, "wrong factory");
        assertEq(result.adapter, TGLD_MARKET_ADAPTER, "wrong adapter");
        assertEq(result.adapter_id, 0x3247ff10f7748cc530dae0e7d84b454cc922fdd00e95cea8c02c2a8ed54d448e);
        assertEq(result.market_id, 0x3c2ce083d3ac6329ae69fd68bf23d4fada5587271860d987788dfd4f0ac3b5f0);
        assertEq(result.collateral_cap_id, 0x0198a1a75ab7c4db2d20e4e2f012c6429107aded3c9141c4f03992aa85f7bf27);
        assertEq(result.market_cap_id, 0x89b748c40aab5b141b7fa9986cf1b2748bf9b94b421a7c10eb88063db26ec5bb);
    }

    /// @notice A deployed adapter for another parent cannot be paired with the tGLD config.
    function test_fork_Revert_DeployMorphoAdapter_ExistingAdapterMismatch() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), EXISTING_ADAPTER_FORK_BLOCK);
        DeployMorphoAdapter script = new DeployMorphoAdapter();

        vm.expectRevert("adapter does not match parent lookup");
        script.runExisting(
            "./config/mainnet/tgld/adapters/tgld_usdc_market_adapter.toml",
            "./config/mainnet/tgld/vaults/tgld_usdc_vault.toml",
            TBRL_MARKET_ADAPTER
        );
    }

    /// @notice Local dev deploys the vault v1 factory itself rather than using a hardcoded address.
    function test_fork_DeployMorphoAdapter_VaultType_Local() public {
        string memory config =
            writeFixture("vault_local", "31337", "VAULT", address(usdc), GT_USDC, OWNER_MULTISIG, TGLD_PARENT_VAULT);
        vm.chainId(31337);

        DeployMorphoAdapter.DeploymentResult memory result = new DeployMorphoAdapter().run(config);
        IMorphoVaultV1Adapter adapter = IMorphoVaultV1Adapter(result.adapter);

        assertNotEq(result.factory, VAULT_V1_ADAPTER_FACTORY_ADDRESS, "local run must not use the mainnet factory");
        assertNotEq(result.factory, address(0), "factory not deployed");
        assertEq(adapter.factory(), result.factory, "adapter not deployed by the local factory");
        assertEq(adapter.parentVault(), TGLD_PARENT_VAULT, "invalid parent vault");
        assertEq(adapter.morphoVaultV1(), GT_USDC, "invalid morpho v1 vault");
        assertTrue(
            IMorphoVaultV1AdapterFactory(result.factory).isMorphoVaultV1Adapter(result.adapter),
            "adapter not registered"
        );
    }

    /// @notice Local dev deploys the market factory itself, against locally deployed morpho and IRM singletons.
    function test_fork_DeployMorphoAdapter_MarketType_Local() public {
        string memory config = writeFixture(
            "market_local", "31337", "MARKET", address(usdc), address(0), OWNER_MULTISIG, TGLD_PARENT_VAULT
        );
        vm.chainId(31337);

        DeployMorphoAdapter.DeploymentResult memory result =
            new DeployMorphoAdapter().run(config, writeMarketVaultFixture("31337"));
        IMorphoMarketV1AdapterV2 adapter = IMorphoMarketV1AdapterV2(result.adapter);
        IMorphoMarketV1AdapterV2Factory factory = IMorphoMarketV1AdapterV2Factory(result.factory);

        // factory immutables come from the locally deployed morpho singletons
        address morphoBlue = factory.morpho();
        address adaptiveCurveIrm = factory.adaptiveCurveIrm();
        assertGt(morphoBlue.code.length, 0, "morpho blue not deployed");
        assertGt(adaptiveCurveIrm.code.length, 0, "irm not deployed");

        // adapter immutables
        assertEq(adapter.factory(), result.factory, "adapter not deployed by the local factory");
        assertEq(adapter.parentVault(), TGLD_PARENT_VAULT, "invalid parent vault");
        assertEq(adapter.morpho(), morphoBlue, "invalid adapter morpho");
        assertEq(adapter.adaptiveCurveIrm(), adaptiveCurveIrm, "invalid adapter irm");
        assertEq(adapter.asset(), address(usdc), "invalid adapter asset");
        assertEq(adapter.adapterId(), keccak256(abi.encode("this", result.adapter)), "invalid adapter id");

        // markets are wired separately by the curator, so the adapter starts empty
        assertEq(adapter.marketIdsLength(), 0, "adapter should start with no markets");

        // factory registration
        assertTrue(factory.isMorphoMarketV1AdapterV2(result.adapter), "adapter not registered");
        assertEq(
            factory.morphoMarketV1AdapterV2(TGLD_PARENT_VAULT),
            result.adapter,
            "factory lookup does not resolve to the adapter"
        );
    }

    /// @notice Local dev deploys the generic factory itself, against real mainnet vaults.
    function test_fork_DeployMorphoAdapter_GenericType_Local() public {
        string memory config = writeFixture(
            "generic_local", "31337", "GENERIC", address(usdc), STEAKHOUSE_USDC, OWNER_MULTISIG, TGLD_PARENT_VAULT
        );
        vm.chainId(31337);

        DeployMorphoAdapter.DeploymentResult memory result = new DeployMorphoAdapter().run(config);
        GenericMorphoAdapter adapter = GenericMorphoAdapter(result.adapter);
        GenericMorphoAdapterFactory factory = GenericMorphoAdapterFactory(result.factory);

        // adapter immutables
        assertEq(address(adapter.parentVault()), TGLD_PARENT_VAULT, "invalid parent vault");
        assertEq(address(adapter.vault()), STEAKHOUSE_USDC, "invalid target vault");
        assertEq(adapter.asset(), IVaultV2(TGLD_PARENT_VAULT).asset(), "invalid adapter asset");
        assertEq(adapter.adapterId(), keccak256(abi.encode("this", result.adapter)), "invalid adapter id");
        assertEq(adapter.owner(), OWNER_MULTISIG, "invalid adapter owner");

        // factory registration
        assertTrue(factory.isGenericMorphoAdapter(result.adapter), "adapter not registered");
        assertEq(
            factory.genericMorphoAdapter(TGLD_PARENT_VAULT, STEAKHOUSE_USDC),
            result.adapter,
            "factory lookup does not resolve to the adapter"
        );
    }

    /// @notice A second generic deployment on the same local chain reuses the factory instead of
    /// colliding on the deterministic CREATE2 address.
    function test_fork_DeployMorphoAdapter_GenericType_Local_ReusesFactory() public {
        string memory first = writeFixture(
            "generic_local_1", "31337", "GENERIC", address(usdc), STEAKHOUSE_USDC, OWNER_MULTISIG, TGLD_PARENT_VAULT
        );
        string memory second = writeFixture(
            "generic_local_2", "31337", "GENERIC", address(usdc), GT_USDC, OWNER_MULTISIG, TGLD_PARENT_VAULT
        );
        vm.chainId(31337);

        DeployMorphoAdapter.DeploymentResult memory result1 = new DeployMorphoAdapter().run(first);
        DeployMorphoAdapter.DeploymentResult memory result2 = new DeployMorphoAdapter().run(second);

        assertEq(result1.factory, result2.factory, "second run must reuse the deployed factory");
        assertNotEq(result1.adapter, result2.adapter, "adapters must be distinct");

        GenericMorphoAdapterFactory factory = GenericMorphoAdapterFactory(result1.factory);
        assertTrue(factory.isGenericMorphoAdapter(result1.adapter), "first adapter not registered");
        assertTrue(factory.isGenericMorphoAdapter(result2.adapter), "second adapter not registered");
    }

    /// @notice An unrecognized adapter_type is rejected.
    function test_fork_Revert_DeployMorphoAdapter_UnknownType() public {
        string memory config = writeFixture(
            "bogus_mainnet", "mainnet", "BOGUS", address(usdc), STEAKHOUSE_USDC, OWNER_MULTISIG, TGLD_PARENT_VAULT
        );
        DeployMorphoAdapter script = new DeployMorphoAdapter();

        vm.expectRevert("unknown adapter_type");
        script.run(config);
    }

    /// @notice A config asset that does not match the parent vault's asset is rejected.
    function test_fork_Revert_DeployMorphoAdapter_AssetMismatch() public {
        string memory config = writeFixture(
            "mismatch_mainnet", "mainnet", "VAULT", address(usdt), GT_USDC, OWNER_MULTISIG, TGLD_PARENT_VAULT
        );
        DeployMorphoAdapter script = new DeployMorphoAdapter();

        vm.expectRevert("parent asset does not match config");
        script.run(config);
    }

    /// @notice Chains other than mainnet, sepolia and local dev are rejected before reading any config.
    function test_fork_Revert_DeployMorphoAdapter_UnsupportedChain() public {
        vm.chainId(42161);
        DeployMorphoAdapter script = new DeployMorphoAdapter();

        vm.expectRevert("chain not supported");
        script.run("");
    }

    function writeMarketVaultFixture(string memory chainKey) internal returns (string memory path) {
        vm.createDir("cache/test/adapters/vaults", true);
        vm.createDir("cache/test/adapters/markets", true);
        path = string.concat("cache/test/adapters/vaults/", chainKey, ".toml");
        string memory vault = vm.readFile("config/mainnet/tgld/vaults/tgld_usdc_vault.toml");
        string memory market = vm.readFile("config/mainnet/tgld/markets/tgld_stgld_usdc_market.toml");
        bool local = keccak256(bytes(chainKey)) == keccak256("31337");
        vault = vm.replace(vault, "tgld_usdc_market_adapter", local ? "market_local" : "market_mainnet");
        if (local) {
            vault = vm.replace(vault, "mainnet", "31337");
            market = vm.replace(market, "mainnet", "31337");
            market = vm.replace(
                market, "0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC", "0x0000000000000000000000000000000000000000"
            );
        }
        vault = vm.replace(vault, "tgld_stgld_usdc_market", string.concat(chainKey, "_market"));
        vm.writeFile(path, vault);
        vm.writeFile(string.concat("cache/test/adapters/markets/", chainKey, "_market.toml"), market);
    }

    /// @notice Write a temp adapter config fixture and return its path.
    function writeFixture(
        string memory name,
        string memory chainKey,
        string memory adapterType,
        address asset,
        address vault_,
        address owner_,
        address parent
    ) internal returns (string memory path) {
        path = string.concat(FIXTURE_DIR, name, ".toml");
        string memory content = string.concat(
            "[",
            chainKey,
            "]\n", //
            "endpoint_url = \"http://localhost:8545\"\n\n"
        );
        content = string.concat(
            content, "[", chainKey, ".string]\n", "adapter_type = \"", adapterType, "\"\n", "name = \"", name, "\"\n\n"
        );
        content = string.concat(
            content,
            "[",
            chainKey,
            ".address]\n",
            "asset = \"",
            vm.toString(asset),
            "\"\n",
            "vault = \"",
            vm.toString(vault_),
            "\"\n"
        );
        content = string.concat(
            content, "owner = \"", vm.toString(owner_), "\"\n", "parent = \"", vm.toString(parent), "\"\n\n"
        );
        content = string.concat(
            content,
            "[",
            chainKey,
            ".uint]\n",
            "absolute_cap = 100_000_000_000000\n",
            "relative_cap = 1_000000000000000000\n\n"
        );
        content = string.concat(content, "[", chainKey, ".bool]\n", "is_new_adapter = true\n");
        vm.writeFile(path, content);
    }
}
