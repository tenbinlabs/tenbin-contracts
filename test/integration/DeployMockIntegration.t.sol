// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Config} from "forge-std/Config.sol";
import {Deploy} from "../../script/Deploy.s.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IMorphoMarketV1AdapterV2} from "vault-v2/src/adapters/interfaces/IMorphoMarketV1AdapterV2.sol";
import {IMorphoStaticTyping, Id, MarketParams} from "vault-v2/lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "vault-v2/lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {IMorphoVaultV1Adapter} from "vault-v2/src/adapters/interfaces/IMorphoVaultV1Adapter.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Test} from "forge-std/Test.sol";

// test deployment script
// this requires .env is set up correctly
contract DeployMockTest is Test, Config {
    using SafeERC20 for IERC20;

    // roles
    bytes32 internal constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 internal constant CAP_ADJUSTER_ROLE = keccak256("CAP_ADJUSTER_ROLE");
    bytes32 internal constant CURATOR_ROLE = keccak256("CURATOR_ROLE");
    bytes32 internal constant CUSTODIAN_KEEPER_ROLE = keccak256("CUSTODIAN_KEEPER_ROLE");
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant GATEKEEPER_ROLE = keccak256("GATEKEEPER_ROLE");
    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 internal constant MULTICALLER_ROLE = keccak256("MULTICALLER_ROLE");
    bytes32 internal constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");
    bytes32 internal constant RESTRICTER_ROLE = keccak256("RESTRICTER_ROLE");
    bytes32 internal constant REVENUE_KEEPER_ROLE = keccak256("REVENUE_KEEPER_ROLE");
    bytes32 internal constant REWARDER_ROLE = keccak256("REWARDER_ROLE");
    bytes32 internal constant SIGNER_MANAGER_ROLE = keccak256("SIGNER_MANAGER_ROLE");
    bytes32 internal constant INSTANT_UNSTAKER_ROLE = keccak256("INSTANT_UNSTAKER_ROLE");

    // variables
    Deploy.CoreDeploymentResult deployment;
    Deploy deployer;

    function setUp() public {
        deployer = new Deploy();
        (deployment,) = deployer.run("", "", true);
    }

    function test_DeployMockIntegration() public {
        _loadConfig("./config/local/tgld/tgld_local.toml", false);
        // check default admin roles
        assertEq(deployment.controller.hasRole(DEFAULT_ADMIN_ROLE, config.get("default_admin_role").toAddress()), true);
        assertEq(deployment.manager.hasRole(DEFAULT_ADMIN_ROLE, config.get("default_admin_role").toAddress()), true);
        assertEq(deployment.asset.pendingOwner(), config.get("default_admin_role").toAddress());
        assertEq(deployment.multicall.hasRole(DEFAULT_ADMIN_ROLE, config.get("default_admin_role").toAddress()), true);
        assertEq(
            deployment.staked_asset.hasRole(DEFAULT_ADMIN_ROLE, config.get("default_admin_role").toAddress()), true
        );
        assertEq(
            deployment.revenue_module.hasRole(DEFAULT_ADMIN_ROLE, config.get("default_admin_role").toAddress()), true
        );
        assertEq(
            deployment.custodian_module.hasRole(DEFAULT_ADMIN_ROLE, config.get("default_admin_role").toAddress()), true
        );

        // check controller roles
        assertEq(deployment.controller.hasRole(MINTER_ROLE, config.get("minter_role").toAddress()), true);
        assertEq(deployment.controller.hasRole(GATEKEEPER_ROLE, config.get("gatekeeper_role").toAddress()), true);
        assertEq(deployment.controller.hasRole(ADMIN_ROLE, config.get("admin_role").toAddress()), true);
        assertEq(
            deployment.controller.hasRole(SIGNER_MANAGER_ROLE, config.get("signer_manager_role").toAddress()), true
        );
        assertEq(deployment.controller.hasRole(RESTRICTER_ROLE, config.get("restricter_role").toAddress()), true);

        // check manager roles
        assertEq(deployment.manager.revenueModule(), address(deployment.revenue_module));
        assertEq(deployment.manager.hasRole(ADMIN_ROLE, config.get("admin_role").toAddress()), true);
        assertEq(deployment.manager.hasRole(CURATOR_ROLE, config.get("curator_role").toAddress()), true);
        assertEq(deployment.manager.hasRole(CURATOR_ROLE, address(deployment.multicall)), true);
        assertEq(deployment.manager.hasRole(CURATOR_ROLE, address(deployment.controller)), true);
        assertEq(deployment.manager.hasRole(REBALANCER_ROLE, config.get("rebalancer_role").toAddress()), true);
        assertEq(deployment.manager.hasRole(GATEKEEPER_ROLE, config.get("gatekeeper_role").toAddress()), true);
        assertEq(deployment.manager.hasRole(CAP_ADJUSTER_ROLE, config.get("cap_adjuster_role").toAddress()), true);

        // check staking roles
        assertEq(deployment.staked_asset.hasRole(REWARDER_ROLE, config.get("rewarder_role").toAddress()), true);
        assertEq(deployment.staked_asset.hasRole(REWARDER_ROLE, address(deployment.revenue_module)), true);
        assertEq(deployment.staked_asset.hasRole(ADMIN_ROLE, config.get("admin_role").toAddress()), true);
        assertEq(deployment.staked_asset.hasRole(RESTRICTER_ROLE, config.get("restricter_role").toAddress()), true);
        assertEq(deployment.staked_asset.hasRole(CAP_ADJUSTER_ROLE, config.get("cap_adjuster_role").toAddress()), true);
        assertEq(deployment.staked_asset.hasRole(INSTANT_UNSTAKER_ROLE, address(deployment.controller)), true);

        // check multicall roles
        assertEq(deployment.multicall.hasRole(MULTICALLER_ROLE, config.get("multicaller_role").toAddress()), true);

        // check revenue manager roles
        assertEq(
            deployment.revenue_module.hasRole(DEFAULT_ADMIN_ROLE, config.get("default_admin_role").toAddress()), true
        );
        assertEq(
            deployment.revenue_module.hasRole(REVENUE_KEEPER_ROLE, config.get("revenue_keeper_role").toAddress()), true
        );

        // check custodian module roles
        assertEq(
            deployment.custodian_module.hasRole(CUSTODIAN_KEEPER_ROLE, config.get("custodian_keeper_role").toAddress()),
            true
        );

        // ensure roles are renounced by deployer (except local dev)
        if (block.chainid != 31337) {
            assertNotEq(deployment.asset.owner(), config.get("default_admin_role").toAddress());
            assertFalse(deployment.controller.hasRole(DEFAULT_ADMIN_ROLE, config.get("deployer").toAddress()));
            assertFalse(deployment.manager.hasRole(DEFAULT_ADMIN_ROLE, config.get("deployer").toAddress()));
            assertFalse(deployment.multicall.hasRole(DEFAULT_ADMIN_ROLE, config.get("deployer").toAddress()));
            assertFalse(deployment.staked_asset.hasRole(DEFAULT_ADMIN_ROLE, config.get("deployer").toAddress()));
            assertFalse(deployment.manager.hasRole(ADMIN_ROLE, config.get("deployer").toAddress()));
            assertFalse(deployment.manager.hasRole(CURATOR_ROLE, config.get("deployer").toAddress()));
            assertFalse(deployment.manager.hasRole(REBALANCER_ROLE, config.get("deployer").toAddress()));
            assertFalse(deployment.manager.hasRole(GATEKEEPER_ROLE, config.get("deployer").toAddress()));
            assertFalse(deployment.manager.hasRole(CAP_ADJUSTER_ROLE, config.get("deployer").toAddress()));
            assertFalse(deployment.staked_asset.hasRole(REWARDER_ROLE, config.get("deployer").toAddress()));
            assertFalse(deployment.staked_asset.hasRole(ADMIN_ROLE, config.get("deployer").toAddress()));
            assertFalse(deployment.multicall.hasRole(MULTICALLER_ROLE, config.get("deployer").toAddress()));
            assertFalse(deployment.revenue_module.hasRole(DEFAULT_ADMIN_ROLE, config.get("deployer").toAddress()));
            assertFalse(deployment.revenue_module.hasRole(REVENUE_KEEPER_ROLE, config.get("deployer").toAddress()));
            assertFalse(deployment.custodian_module.hasRole(DEFAULT_ADMIN_ROLE, config.get("deployer").toAddress()));
        }

        // check controller is correctly configured
        assertEq(deployment.controller.ratio(), config.get("ratio").toUint256());
        assertEq(deployment.controller.custodian(), address(deployment.custodian_module));
        assertEq(deployment.controller.manager(), address(deployment.manager));
        assertEq(deployment.controller.blockMintLimit(), uint128(vm.parseUint(config.get("mint_limit").toString())));
        assertEq(deployment.controller.blockRedeemLimit(), uint128(vm.parseUint(config.get("redeem_limit").toString())));

        // check manager is correctly configured
        assertEq(deployment.manager.controller(), address(deployment.controller));
        assertEq(deployment.manager.swapModule(), address(deployment.swap_module));

        // check swap module is correctly configured
        assertEq(deployment.swap_module.manager(), address(deployment.manager));
        assertEq(deployment.swap_module.router(), address(deployment.one_inch_router));

        // check staking is correctly configured
        (
            uint128 length,
            /*uint128 time*/, /*uint256 amount*/
        ) = deployment.staked_asset.vesting();
        assertEq(length, config.get("vesting_period").toUint128());
        assertEq(deployment.staked_asset.cooldownPeriod(), config.get("cooldown_period").toUint256());
        assertEq(
            deployment.staked_asset.instantUnstakeCap(), vm.parseUint(config.get("instant_unstake_cap").toString())
        );

        // check revenue module is correctly configured
        assertEq(deployment.revenue_module.manager(), address(deployment.manager));
        assertEq(deployment.revenue_module.staking(), address(deployment.staked_asset));
        assertEq(deployment.revenue_module.asset(), address(deployment.asset));
        assertEq(deployment.revenue_module.controller(), address(deployment.controller));
    }

    function test_Revert_Collateral_DeployMock() public {
        vm.chainId(11155111);

        string memory dir = "./config/test/tmxn.toml";

        vm.expectRevert("invalid collateral");
        deployer.runCoreOnly(dir, true);
    }
}

/// @notice The local config's three adapters, two GENERIC and one MARKET, run through
/// Deploy.s.sol on every integration run. Assert each landed at its configured index.
contract DeployVaultAdapterSetTest is Test {
    function test_DeployVault_AdapterSet() public {
        (, Deploy.VaultDeploymentResult memory result) = new Deploy().run("", "", true);

        assertEq(result.adapters.length, 3, "expected three adapters");
        assertAdapter(result, 0, "Steakhouse Prime USDC", "GENERIC");
        assertAdapter(result, 1, "Static Aave Ethereum USDC", "GENERIC");
        assertAdapter(result, 2, "stGLD/USDC", "MARKET");

        assertEq(address(result.liquidity_adapter), address(result.adapters[0].adapter), "wrong liquidity adapter");
        assertEq(result.vault.liquidityAdapter(), address(result.liquidity_adapter), "liquidity adapter not set");
        assertEq(result.vault.liquidityData(), abi.encode(uint256(0)), "Prime liquidity data");
    }

    function assertAdapter(
        Deploy.VaultDeploymentResult memory result,
        uint256 index,
        string memory name,
        string memory adapterType
    ) internal view {
        Deploy.DeployedAdapter memory adapter = result.adapters[index];
        assertEq(adapter.name, name, "wrong adapter name");
        assertEq(adapter.adapter_type, adapterType, "wrong adapter type");
        assertTrue(result.vault.isAdapter(address(adapter.adapter)), "adapter not registered");
    }
}

/// @notice Vault deploy with a MARKET adapter and a configured market, driven by temp TOML
/// fixtures: morpho blue and its IRM are deployed locally, the market is created, seeded, and
/// capped on all three ids, and a live allocate lands supply in it.
contract DeployMarketAdapterMockTest is Test {
    address internal constant LOCAL_ROLE = 0x635ECB1700d52a1FbC395c5C92b845A00AF56a38;
    /// @dev Distinct from LOCAL_ROLE: the deploy revokes the broadcaster's allocator role at the end.
    address internal constant ALLOCATOR = address(0xA110);
    string internal constant FIXTURE_BASE = "cache/test/market_vault/";

    function test_DeployVault_WithMarketAdapter() public {
        writeFixtures();
        Deploy deployer = new Deploy();
        (, Deploy.VaultDeploymentResult memory vault) =
            deployer.run("", string.concat(FIXTURE_BASE, "vaults/market_vault.toml"), true);

        assertEq(vault.adapters.length, 2, "expected two adapters");
        assertEq(vault.adapters[1].adapter_type, "MARKET", "expected a market adapter");
        address marketAdapter = address(vault.adapters[1].adapter);

        // registered and capped like any other adapter, at its own config's caps rather than index 0's
        assertTrue(vault.vault.isAdapter(marketAdapter), "market adapter not registered");
        bytes32 id = keccak256(abi.encode("this", marketAdapter));
        assertEq(vault.vault.absoluteCap(id), 70_000_000_000000, "wrong absolute cap");
        assertEq(vault.vault.relativeCap(id), 700000000000000000, "wrong relative cap");

        bytes32 liquidityId = keccak256(abi.encode("this", address(vault.adapters[0].adapter)));
        assertEq(vault.vault.absoluteCap(liquidityId), 100_000_000_000000, "wrong liquidity absolute cap");
        assertEq(vault.vault.relativeCap(liquidityId), 1_000000000000000000, "wrong liquidity relative cap");

        // deployed against a live local morpho blue + IRM and starts with no allocations
        IMorphoMarketV1AdapterV2 adapter = IMorphoMarketV1AdapterV2(marketAdapter);
        assertEq(adapter.parentVault(), address(vault.vault), "wrong parent vault");
        assertGt(adapter.morpho().code.length, 0, "morpho blue not deployed");
        assertGt(adapter.adaptiveCurveIrm().code.length, 0, "irm not deployed");
        assertEq(adapter.marketIdsLength(), 0, "market adapter should start empty");

        // the configured market was created, seeded, and capped on both market-derived ids
        assertEq(vault.markets.length, 1, "expected one market");
        MarketParams memory marketParams = vault.markets[0].params;
        assertEq(marketParams.loanToken, vault.vault.asset(), "wrong loan token");
        assertEq(marketParams.irm, adapter.adaptiveCurveIrm(), "wrong irm");
        bytes32 collateralId = keccak256(abi.encode("collateralToken", marketParams.collateralToken));
        bytes32 marketCapId = keccak256(abi.encode("this/marketParams", marketAdapter, marketParams));
        assertEq(vault.vault.absoluteCap(collateralId), 500_000_000000, "wrong collateral absolute cap");
        assertEq(vault.vault.relativeCap(collateralId), 900000000000000000, "wrong collateral relative cap");
        assertEq(vault.vault.absoluteCap(marketCapId), 500_000_000000, "wrong market absolute cap");
        assertEq(vault.vault.relativeCap(marketCapId), 900000000000000000, "wrong market relative cap");
        bytes32 marketId = Id.unwrap(MarketParamsLib.id(marketParams));
        (uint128 totalSupplyAssets,,,,,) = IMorphoStaticTyping(adapter.morpho()).market(Id.wrap(marketId));
        assertEq(totalSupplyAssets, 1e6, "market not seeded");

        // a live allocate from the liquidity adapter's dead deposit lands supply in the market
        vm.startPrank(ALLOCATOR);
        vault.vault.deallocate(address(vault.liquidity_adapter), hex"", 500000);
        vault.vault.allocate(marketAdapter, abi.encode(marketParams), 500000);
        vm.stopPrank();
        assertEq(adapter.marketIdsLength(), 1, "market not tracked after allocate");
        assertGe(adapter.expectedSupplyAssets(marketId), 500000, "supply not landed in market");
        assertEq(vault.vault.allocation(marketCapId), 500000, "market allocation not accounted");

        // the VAULT-type entry is the liquidity adapter and got a seeded mock target
        assertEq(address(vault.liquidity_adapter), address(vault.adapters[0].adapter), "wrong liquidity adapter");
        assertEq(vault.vault.liquidityAdapter(), address(vault.liquidity_adapter), "liquidity adapter not set");
        address mockTarget = IMorphoVaultV1Adapter(address(vault.adapters[0].adapter)).morphoVaultV1();
        assertGt(mockTarget.code.length, 0, "mock target not deployed");
    }

    /// @notice Write the fixture config tree: <base>/vaults/<vault>.toml + <base>/adapters/<name>.toml
    /// + <base>/markets/<name>.toml, matching the layout the config path helpers expect.
    function writeFixtures() internal {
        vm.createDir(string.concat(FIXTURE_BASE, "vaults"), true);
        vm.createDir(string.concat(FIXTURE_BASE, "adapters"), true);
        vm.createDir(string.concat(FIXTURE_BASE, "markets"), true);
        vm.writeFile(string.concat(FIXTURE_BASE, "vaults/market_vault.toml"), vaultToml());
        // distinct caps per adapter: identical ones would hide an index mix-up in the caps loop
        vm.writeFile(
            string.concat(FIXTURE_BASE, "adapters/fixture_steakhouse_adapter.toml"),
            adapterToml("VAULT", "Fixture Steakhouse", 100_000_000_000000, 1_000000000000000000)
        );
        vm.writeFile(
            string.concat(FIXTURE_BASE, "adapters/fixture_market_adapter.toml"),
            adapterToml("MARKET", "Fixture Market", 70_000_000_000000, 700000000000000000)
        );
        vm.writeFile(string.concat(FIXTURE_BASE, "markets/fixture_market.toml"), marketToml());
    }

    function marketToml() internal pure returns (string memory) {
        return string.concat(
            "[31337]\n",
            "endpoint_url = \"http://localhost:8545\"\n\n",
            "[31337.string]\n",
            "name = \"Fixture stAsset/USDC\"\n\n",
            "[31337.address]\n",
            addressLine("collateral_token", address(0)),
            addressLine("oracle", address(0)),
            addressLine("irm", address(0)),
            "\n[31337.uint]\n",
            "lltv = 860000000000000000\n",
            "absolute_cap = 500_000_000000\n",
            "relative_cap = 900000000000000000\n"
        );
    }

    function vaultToml() internal pure returns (string memory) {
        return string.concat(
            "[31337]\n",
            "endpoint_url = \"http://localhost:8545\"\n\n",
            "[31337.string]\n",
            "name = \"Market Fixture Vault\"\n",
            "symbol = \"tMKTv-USDC\"\n",
            "adapters = [\"fixture_steakhouse_adapter\", \"fixture_market_adapter\"]\n",
            "liquidity_adapter = \"fixture_steakhouse_adapter\"\n",
            "markets = [\"fixture_market\"]\n\n",
            "[31337.address]\n",
            addressLine("allocator", ALLOCATOR),
            addressLine("asset", address(0)),
            addressLine("curator", LOCAL_ROLE),
            addressLine("owner", LOCAL_ROLE),
            addressLine("sentinel", LOCAL_ROLE),
            "\n[31337.uint]\n",
            "dead_deposit = 1_000000\n",
            "max_rate = 63419583967\n",
            "timelock_duration = 0\n"
        );
    }

    function adapterToml(string memory adapterType, string memory name, uint256 absoluteCap, uint256 relativeCap)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            "[31337]\n",
            "endpoint_url = \"http://localhost:8545\"\n\n",
            "[31337.string]\n",
            "adapter_type = \"",
            adapterType,
            "\"\n",
            "name = \"",
            name,
            "\"\n\n",
            "[31337.address]\n",
            addressLine("asset", address(0)),
            addressLine("vault", address(0)),
            addressLine("owner", LOCAL_ROLE),
            addressLine("parent", address(0)),
            "\n[31337.uint]\n",
            "absolute_cap = ",
            vm.toString(absoluteCap),
            "\n",
            "relative_cap = ",
            vm.toString(relativeCap),
            "\n\n",
            "[31337.bool]\n",
            "is_new_adapter = true\n"
        );
    }

    function addressLine(string memory key, address value) internal pure returns (string memory) {
        return string.concat(key, " = \"", vm.toString(value), "\"\n");
    }
}
