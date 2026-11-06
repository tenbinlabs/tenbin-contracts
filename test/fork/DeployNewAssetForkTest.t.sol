// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ForkBaseTest} from "./ForkBaseTest.sol";
import {PyriteFixtures} from "../helpers/PyriteFixtures.sol";
import {Deploy} from "../../script/Deploy.s.sol";
import {NewAssetDeployer} from "../helpers/NewAssetDeployer.sol";
import {ChainlinkOracleAdapter} from "deploy-target/src/oracle/ChainlinkOracleAdapter.sol";
import {IOracleAdapter} from "deploy-target/src/interface/IOracleAdapter.sol";
import {LibVariable} from "forge-std/LibVariable.sol";
import {MarketParams, IMorpho, IMorphoBase} from "vault-v2/lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "vault-v2/lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {IMorphoMarketV1AdapterV2} from "vault-v2/src/adapters/interfaces/IMorphoMarketV1AdapterV2.sol";
import {IMorphoChainlinkOracleV2} from "../external/morpho/IMorphoChainlinkOracleV2.sol";
import {AggregatorV3Interface} from "chainlink-local/src/data-feeds/interfaces/AggregatorV3Interface.sol";
import {IMorphoMarketV1AdapterV2Factory} from "vault-v2/src/adapters/interfaces/IMorphoMarketV1AdapterV2Factory.sol";

/// forge-config: default.isolate = false
contract DeployNewAssetForkTest is ForkBaseTest, PyriteFixtures {
    using MarketParamsLib for MarketParams;

    function setUp() public override {
        forkBlock = 26049813;
        super.setUp();
        broadcaster = vm.addr(0x3456);
    }

    function test_fork_PyriteMainnet() public {
        deal(address(usdc), broadcaster, 100e6);
        string memory fixtureDirectory = string.concat("cache/test/pyrite-fork/", vm.toString(bytes32(msg.sig)), "/");
        (string memory asset, string memory config) = writePyriteFixtures("mainnet", fixtureDirectory, "mainnet");
        (Deploy.CoreDeploymentResult memory core, Deploy.VaultDeploymentResult memory vault) =
            (new NewAssetDeployer(broadcaster, string.concat(fixtureDirectory, "output"))).run(asset, config, false);
        assertDeployment(core, vault);
        assertTrue(core.controller.signers(0xa24250395f048933Db981c04c7856317B4B4d99f));
        assertTrue(core.controller.delegates(address(core.revenue_module), 0xa24250395f048933Db981c04c7856317B4B4d99f));
        assertTrue(core.controller.signers(0x6418055600d6D5a66d51daA92a2eE990A085f3F7));
        assertEq(core.oracle_adapter.oracle(), 0x369C67E8b026CC4Ef98350f332D7Dd52b85b7674);
        assertEq(ChainlinkOracleAdapter(address(core.oracle_adapter)).stalenessThreshold(), 1 days);
        (address protocolOracle,) = core.controller.oracle();
        assertEq(protocolOracle, address(core.oracle_adapter));
        assertEq(vault.vault.owner(), 0x698c6d3726846C4AD4Dc9331862b92Cd80D2fb99);
        IMorphoChainlinkOracleV2 oracle = IMorphoChainlinkOracleV2(vault.markets[0].params.oracle);
        (, int256 goldPrice,,,) = AggregatorV3Interface(core.oracle_adapter.oracle()).latestRoundData();
        (, int256 usdcPrice,,,) = AggregatorV3Interface(address(oracle.QUOTE_FEED_1())).latestRoundData();
        assertGt(goldPrice, 0);
        assertGt(usdcPrice, 0);
        // safe: both feed answers are asserted positive above.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 expected =
            core.staked_asset.convertToAssets(1e18) * uint256(goldPrice) / 1e18 * 1e14 / uint256(usdcPrice);
        assertApproxEqRel(oracle.price(), expected, 1e10);
    }

    function test_fork_PyriteSepolia() public {
        createSelectLiveFork("sepolia");
        string memory fixtureDirectory = string.concat("cache/test/pyrite-fork/", vm.toString(bytes32(msg.sig)), "/");
        (string memory asset, string memory config) = writePyriteFixtures("sepolia", fixtureDirectory, "sepolia");
        (Deploy.CoreDeploymentResult memory core, Deploy.VaultDeploymentResult memory vault) =
            (new NewAssetDeployer(broadcaster, string.concat(fixtureDirectory, "output"))).run(asset, config, true);
        assertDeployment(core, vault);
        assertTrue(core.controller.signers(0xE0314BC955477fE95C406DB18a885A3d8C0612AC));
        assertTrue(core.controller.delegates(address(core.revenue_module), 0xE0314BC955477fE95C406DB18a885A3d8C0612AC));
        assertTrue(core.controller.signers(0xDBC08aad7C82d6e09acCD043c5f968eeD7980495));
        assertEq(IMorphoChainlinkOracleV2(vault.markets[0].params.oracle).price(), 3500e24);
    }

    function test_fork_RejectsFundingWithoutStakingSeed() public {
        deal(address(usdc), broadcaster, 2e6);
        string memory directory =
            string.concat("cache/test/new-asset-seed-funding/", vm.toString(bytes32(msg.sig)), "/");
        (string memory asset, string memory config) = writePyriteFixtures("mainnet", directory, "mainnet");
        NewAssetDeployer deployer = new NewAssetDeployer(broadcaster, string.concat(directory, "output"));
        vm.expectRevert("insufficient USDC for deployment seeds");
        deployer.run(asset, config, false);
    }

    function test_fork_NewSymbolUsesConfiguredFeedAndStaleness() public {
        deal(address(usdc), broadcaster, 100e6);
        string memory directory = string.concat("cache/test/new-asset-feed/", vm.toString(bytes32(msg.sig)), "/");
        (string memory asset, string memory config) = writePyriteFixtures("mainnet", directory, "mainnet");
        vm.writeToml('"tNEW"', asset, ".mainnet.string.asset_symbol");
        vm.writeToml("777", asset, ".mainnet.uint.oracle_staleness_threshold");
        address feed = 0x369C67E8b026CC4Ef98350f332D7Dd52b85b7674;
        vm.mockCall(feed, abi.encodeCall(AggregatorV3Interface.decimals, ()), abi.encode(uint8(8)));
        vm.mockCall(
            feed,
            abi.encodeCall(AggregatorV3Interface.latestRoundData, ()),
            abi.encode(uint80(1), int256(200e8), block.timestamp, block.timestamp, uint80(1))
        );
        vm.mockCall(
            0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6,
            abi.encodeCall(AggregatorV3Interface.latestRoundData, ()),
            abi.encode(uint80(1), int256(1e8), block.timestamp, block.timestamp, uint80(1))
        );
        (Deploy.CoreDeploymentResult memory core, Deploy.VaultDeploymentResult memory vault) =
            (new NewAssetDeployer(broadcaster, string.concat(directory, "output"))).run(asset, config, false);
        assertEq(core.asset.symbol(), "tNEW");
        assertEq(core.oracle_adapter.oracle(), feed);
        assertEq(core.oracle_adapter.getPrice(), 200e18);
        assertEq(ChainlinkOracleAdapter(address(core.oracle_adapter)).stalenessThreshold(), 777);
        assertEq(IMorphoChainlinkOracleV2(vault.markets[0].params.oracle).price(), 200e24);
        vm.mockCall(
            feed,
            abi.encodeCall(AggregatorV3Interface.latestRoundData, ()),
            abi.encode(uint80(1), int256(200e8), block.timestamp - 778, block.timestamp - 778, uint80(1))
        );
        vm.expectRevert(IOracleAdapter.OraclePriceStale.selector);
        core.oracle_adapter.getPrice();
    }

    function test_fork_RejectsUnsupportedDecimals() public {
        string memory directory = string.concat("cache/test/new-asset-decimals/", vm.toString(bytes32(msg.sig)), "/");
        (string memory asset, string memory config) = writePyriteFixtures("mainnet", directory, "mainnet");
        NewAssetDeployer deployer = new NewAssetDeployer(broadcaster, string.concat(directory, "output"));
        address[2] memory feeds =
            [address(0x369C67E8b026CC4Ef98350f332D7Dd52b85b7674), 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6];
        for (uint256 i; i < feeds.length; i++) {
            for (uint8 decimals = 7; decimals <= 19; decimals += 12) {
                vm.mockCall(feeds[i], abi.encodeCall(AggregatorV3Interface.decimals, ()), abi.encode(decimals));
                vm.expectRevert(
                    i == 0 ? bytes("unsupported base feed decimals") : bytes("unsupported quote feed decimals")
                );
                deployer.run(asset, config, false);
                vm.clearMockedCalls();
            }
        }
        vm.mockCall(address(usdc), abi.encodeWithSignature("decimals()"), abi.encode(uint8(18)));
        vm.expectRevert("collateral must have 6 decimals");
        deployer.run(asset, config, false);
    }

    function test_fork_RejectsInvalidOrMissingStaleness() public {
        string memory directory = string.concat("cache/test/new-asset-staleness/", vm.toString(bytes32(msg.sig)), "/");
        (string memory asset, string memory config) = writePyriteFixtures("mainnet", directory, "mainnet");
        NewAssetDeployer deployer = new NewAssetDeployer(broadcaster, string.concat(directory, "output"));
        vm.writeToml("0", asset, ".mainnet.uint.oracle_staleness_threshold");
        vm.expectRevert("staleness threshold not set");
        deployer.run(asset, config, false);
        vm.writeFile(asset, vm.replace(vm.readFile(asset), "oracle_staleness_threshold", "unused_threshold"));
        vm.expectRevert(LibVariable.NotInitialized.selector);
        deployer.run(asset, config, false);
    }

    function assertDeployment(Deploy.CoreDeploymentResult memory core, Deploy.VaultDeploymentResult memory vault)
        internal
    {
        assertEq(core.asset.name(), "Tenbin Pyrite");
        assertEq(core.staked_asset.symbol(), "stPYR");
        assertEq(core.staked_asset.balanceOf(address(0xDEAD)), 1e15);
        assertEq(core.staked_asset.totalAssets(), 1e15);
        assertEq(core.staked_asset.convertToAssets(1e18), 1e18);
        assertFalse(core.controller.hasRole(keccak256("MINTER_ROLE"), core.broadcaster));
        assertFalse(core.controller.signers(core.broadcaster));
        assertFalse(core.controller.recipients(core.broadcaster, core.broadcaster));
        assertEq(core.asset.allowance(core.broadcaster, address(core.staked_asset)), 0);
        assertEq(core.collateral.allowance(core.broadcaster, address(core.controller)), 0);
        assertEq(vault.adapters.length, 4);
        assertEq(vault.markets.length, 1);
        MarketParams memory params = vault.markets[0].params;
        assertEq(params.collateralToken, address(core.staked_asset));
        assertEq(params.loanToken, address(core.collateral));
        address adapter = address(vault.adapters[0].adapter);
        IMorpho morpho = IMorpho(IMorphoMarketV1AdapterV2(adapter).morpho());
        assertEq(core.collateral.allowance(core.broadcaster, address(morpho)), 0);
        assertEq(abi.encode(morpho.idToMarketParams(params.id())), abi.encode(params));
        assertEq(morpho.market(params.id()).totalSupplyAssets, 1e6);
        assertGt(morpho.position(params.id(), address(0xDEAD)).supplyShares, 0);
        assertEq(address(IMorphoChainlinkOracleV2(params.oracle).BASE_VAULT()), address(core.staked_asset));
        assertTrue(vault.gate.canReceiveShares(address(core.manager)));
        assertFalse(vault.gate.canReceiveShares(core.broadcaster));
        assertFalse(vault.vault.isAllocator(core.broadcaster));
        assertFalse(core.controller.hasRole(DEFAULT_ADMIN_ROLE, core.broadcaster));
        assertFalse(core.controller.hasRole(SIGNER_MANAGER_ROLE, core.broadcaster));
        assertFalse(core.manager.hasRole(DEFAULT_ADMIN_ROLE, core.broadcaster));
        assertFalse(core.revenue_module.hasRole(ADMIN_ROLE, core.broadcaster));
        vm.expectRevert();
        vm.prank(core.broadcaster);
        core.controller.setSignerStatus(address(this), true);
        vm.expectRevert();
        vm.prank(core.broadcaster);
        vault.gate.setManager(address(this));
        assertEq(vault.vault.absoluteCap(keccak256(abi.encode("this/marketParams", adapter, params))), 1_000_000e6);
        assertEq(vault.vault.relativeCap(keccak256(abi.encode("this/marketParams", adapter, params))), 0.2e18);
    }

    function test_fork_RejectsInvalidMainnetFeeds() public {
        string memory directory = string.concat("cache/test/pyrite-feed-guards/", vm.toString(bytes32(msg.sig)), "/");
        (string memory asset, string memory config) = writePyriteFixtures("mainnet", directory, "mainnet");
        string memory market = string.concat(directory, "markets/tpyr_stpyr_usdc_market.toml");
        NewAssetDeployer deployer = new NewAssetDeployer(broadcaster, string.concat(directory, "output"));
        string memory original = vm.readFile(market);
        resetPyriteAddress(market, "mainnet", "base_feed");
        vm.expectRevert("feeds not set");
        deployer.run(asset, config, false);
        vm.writeFile(market, original);
        vm.writeToml('"0x0000000000000000000000000000000000000001"', market, ".mainnet.address.base_feed");
        vm.expectRevert("base feed must match protocol oracle");
        deployer.run(asset, config, false);
        vm.writeFile(market, original);
        vm.writeToml('"0x0000000000000000000000000000000000000001"', market, ".mainnet.address.quote_feed");
        vm.expectRevert("feeds not deployed");
        deployer.run(asset, config, false);
        vm.writeFile(market, original);
        vm.etch(0x3A7bB36Ee3f3eE32A60e9f2b33c1e5f2E83ad766, hex"");
        vm.expectRevert("oracle factory not deployed");
        deployer.run(asset, config, false);
    }

    function test_fork_RejectsInvalidMarketIrmAndLltv() public {
        string memory directory = string.concat("cache/test/pyrite-market-guards/", vm.toString(bytes32(msg.sig)), "/");
        (string memory asset, string memory config) = writePyriteFixtures("mainnet", directory, "mainnet");
        string memory market = string.concat(directory, "markets/tpyr_stpyr_usdc_market.toml");
        NewAssetDeployer deployer = new NewAssetDeployer(broadcaster, string.concat(directory, "output"));
        string memory original = vm.readFile(market);
        vm.writeToml('"0x0000000000000000000000000000000000000001"', market, ".mainnet.address.irm");
        vm.expectRevert("incorrect market irm");
        deployer.run(asset, config, false);
        vm.writeFile(market, original);
        IMorphoMarketV1AdapterV2Factory factory =
            IMorphoMarketV1AdapterV2Factory(0x32BB1c0D48D8b1B3363e86eeB9A0300BAd61ccc1);
        address morpho = factory.morpho();
        address irm = factory.adaptiveCurveIrm();
        vm.mockCall(morpho, abi.encodeCall(IMorphoBase.isIrmEnabled, (irm)), abi.encode(false));
        vm.expectRevert("irm not enabled");
        deployer.run(asset, config, false);
        vm.clearMockedCalls();
        vm.writeToml("1", market, ".mainnet.uint.lltv");
        vm.expectRevert("lltv not enabled");
        deployer.run(asset, config, false);
    }
}
