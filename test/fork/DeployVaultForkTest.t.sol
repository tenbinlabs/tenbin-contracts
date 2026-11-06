// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Config} from "forge-std/Config.sol";
import {Deploy} from "../../script/Deploy.s.sol";
import {DeployBase} from "../../script/DeployBase.s.sol";
import {ForkBaseTest} from "./ForkBaseTest.sol";
import {Gate} from "deploy-target/src/external/morpho/Gate.sol";
import {IAdapter} from "vault-v2/src/interfaces/IAdapter.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Id, MarketParams} from "vault-v2/lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "vault-v2/lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {IMorphoMarketV1AdapterV2} from "vault-v2/src/adapters/interfaces/IMorphoMarketV1AdapterV2.sol";
import {IVaultV2} from "vault-v2/src/interfaces/IVaultV2.sol";
import {IVaultV2Gates} from "../external/morpho/IVaultV2Gates.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

// test deployment script
// this requires .env is set up correctly
contract DeployVaultForkTest is ForkBaseTest, Config {
    using SafeERC20 for IERC20;
    using MarketParamsLib for MarketParams;
    string constant ASSET_CONFIG_DIR = "./config/mainnet/tgld/tgld.toml";
    string constant CONFIG_DIR = "./config/mainnet/tgld/vaults/tgld_usdc_vault.toml";
    address constant REBALANCER = 0xD1a89086428E2b208414201712cbE0952DabEA03;

    /// @dev VaultDeploymentResult minus the adapters array, which the legacy pipeline cannot copy to storage
    struct StoredDeployment {
        Gate gate;
        IVaultV2 vault;
        IAdapter liquidity_adapter;
        uint256 adapter_count;
    }

    StoredDeployment deployment;
    DeployBase.VaultParameters params;
    address marketAdapter;
    string marketAdapterType;
    string marketName;
    MarketParams marketParams;
    uint256 marketCount;

    function setUp() public override {
        forkBlock = 26049813;
        super.setUp();
        dealTo(usdc, broadcaster, 1e6);
        Deploy deployer = new Deploy();
        Deploy.VaultDeploymentResult memory result = deployer.runVaultOnly(ASSET_CONFIG_DIR, CONFIG_DIR);
        deployment = StoredDeployment(result.gate, result.vault, result.liquidity_adapter, result.adapters.length);
        for (uint256 i = 0; i < result.adapters.length; i++) {
            assertTrue(result.vault.isAdapter(address(result.adapters[i].adapter)), "adapter registered");
        }
        marketAdapter = address(result.adapters[0].adapter);
        marketAdapterType = result.adapters[0].adapter_type;
        marketCount = result.markets.length;
        marketName = result.markets[0].name;
        marketParams = result.markets[0].params;
    }

    function test_fork_DeployVault() public {
        _loadConfig("./config/mainnet/tgld/vaults/tgld_usdc_vault.toml", false);
        // hard coded for redundancy
        params.name = "tGLD USDC Vault";
        params.symbol = "tGLDv-USDC";
        params.allocator = 0x48Fa008bD2660974d55Ee9b7A9ECA1cE61347614;
        params.asset = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        params.curator = 0xE6Eb534f33A635e8d867414Af32F766D221F30d1;
        params.owner = 0x698c6d3726846C4AD4Dc9331862b92Cd80D2fb99;
        params.sentinel = 0x44C24D0937A829B3057be462b0e069516f1D9D45;
        params.dead_deposit = 1_000000;
        params.max_rate = 63419583967;
        params.timelock_duration = 172800;
        uint256 absolute_cap = 100_000_000_000000;
        uint256 relative_cap = 1_000000000000000000;
        bytes32 adapter_id = keccak256(abi.encode("this", address(deployment.liquidity_adapter)));
        uint256 asset_decimals = 6;

        // test config
        assertEq(deployment.vault.asset(), params.asset);
        assertEq(deployment.vault.name(), params.name);
        assertEq(deployment.vault.symbol(), params.symbol);
        assertEq(deployment.vault.owner(), params.owner);
        assertEq(deployment.vault.curator(), params.curator);
        assertEq(deployment.vault.isAllocator(params.allocator), true);
        assertEq(deployment.vault.isAllocator(REBALANCER), true);
        assertEq(deployment.vault.isSentinel(params.sentinel), true);
        assertEq(deployment.adapter_count, 4);
        assertEq(deployment.vault.adaptersLength(), 4);
        assertEq(deployment.vault.liquidityAdapter(), address(deployment.liquidity_adapter));
        assertEq(deployment.vault.liquidityData(), abi.encode(uint256(0)));
        assertEq(deployment.vault.absoluteCap(adapter_id), absolute_cap);
        assertEq(deployment.vault.relativeCap(adapter_id), relative_cap);
        assertEq(deployment.vault.maxRate(), params.max_rate);
        assertEq(deployment.gate.owner(), params.curator);
        assertEq(IVaultV2Gates(address(deployment.vault)).receiveSharesGate(), address(deployment.gate));
        assertEq(IVaultV2Gates(address(deployment.vault)).sendSharesGate(), address(deployment.gate));
        assertEq(IVaultV2Gates(address(deployment.vault)).receiveAssetsGate(), address(deployment.gate));
        assertEq(IVaultV2Gates(address(deployment.vault)).sendAssetsGate(), address(deployment.gate));

        assertEq(marketAdapterType, "MARKET", "first adapter type");
        assertEq(marketCount, 1, "market count");
        assertEq(marketName, "stGLD/USDC", "market name");
        IMorphoMarketV1AdapterV2 adapter = IMorphoMarketV1AdapterV2(marketAdapter);
        assertEq(adapter.parentVault(), address(deployment.vault), "market adapter parent");
        assertEq(adapter.asset(), params.asset, "market adapter asset");
        assertEq(adapter.adaptiveCurveIrm(), marketParams.irm, "market adapter irm");
        assertEq(Id.unwrap(marketParams.id()), 0x3c2ce083d3ac6329ae69fd68bf23d4fada5587271860d987788dfd4f0ac3b5f0);
        bytes32 marketAdapterId = keccak256(abi.encode("this", marketAdapter));
        bytes32 collateralCapId = keccak256(abi.encode("collateralToken", marketParams.collateralToken));
        bytes32 marketCapId = keccak256(abi.encode("this/marketParams", marketAdapter, marketParams));
        assertEq(deployment.vault.absoluteCap(marketAdapterId), 1_000_000_000000, "market adapter absolute cap");
        assertEq(deployment.vault.relativeCap(marketAdapterId), 200000000000000000, "market adapter relative cap");
        assertEq(deployment.vault.absoluteCap(collateralCapId), 1_000_000_000000, "collateral absolute cap");
        assertEq(deployment.vault.relativeCap(collateralCapId), 200000000000000000, "collateral relative cap");
        assertEq(deployment.vault.absoluteCap(marketCapId), 1_000_000_000000, "market absolute cap");
        assertEq(deployment.vault.relativeCap(marketCapId), 200000000000000000, "market relative cap");

        // ensure 1 share = 1 asset and dead deposit
        assertApproxEqAbs(deployment.vault.convertToAssets(1e18), 10 ** asset_decimals, 1);
        assertApproxEqAbs(deployment.vault.totalAssets(), params.dead_deposit, 1);

        // test timelock
        bytes4[] memory timelockedSelectors = new bytes4[](10);
        timelockedSelectors[0] = IVaultV2.setReceiveSharesGate.selector;
        timelockedSelectors[1] = IVaultV2.setSendSharesGate.selector;
        timelockedSelectors[2] = IVaultV2.setReceiveAssetsGate.selector;
        timelockedSelectors[3] = IVaultV2.addAdapter.selector;
        timelockedSelectors[4] = IVaultV2.increaseAbsoluteCap.selector;
        timelockedSelectors[5] = IVaultV2.increaseRelativeCap.selector;
        timelockedSelectors[6] = IVaultV2.setForceDeallocatePenalty.selector;
        timelockedSelectors[7] = IVaultV2.abdicate.selector;
        timelockedSelectors[8] = IVaultV2.removeAdapter.selector;
        timelockedSelectors[9] = IVaultV2.increaseTimelock.selector;

        // Submit timelock increases for all selectors
        for (uint256 i = 0; i < timelockedSelectors.length; i++) {
            assertEq(deployment.vault.timelock(timelockedSelectors[i]), params.timelock_duration);
        }
    }
}
