// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DeployMorphoAdapter} from "../../script/DeployMorphoAdapter.s.sol";
import {IMorphoMarketV1AdapterV2Factory} from "vault-v2/src/adapters/interfaces/IMorphoMarketV1AdapterV2Factory.sol";
import {IVaultV2} from "vault-v2/src/interfaces/IVaultV2.sol";
import {MarketParams} from "vault-v2/lib/morpho-blue/src/interfaces/IMorpho.sol";

interface IPayloadCheck {
    function check(address target, bytes calldata executionPayload) external view;
}

contract DeployMorphoAdapterPayloadsHarness is DeployMorphoAdapter {
    function printVaultOperation(string memory label, bytes memory executionPayload) internal view override {
        IPayloadCheck(address(0xCA11)).check(adapterParams.parent, executionPayload);
        super.printVaultOperation(label, executionPayload);
    }
}

contract DeployMorphoAdapterPayloadsTest is Test {
    address constant PARENT = 0x7290245b3e564f0Ae2dA5af0690eF4842CF13c75;
    address constant ASSET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant FACTORY = 0x32BB1c0D48D8b1B3363e86eeB9A0300BAd61ccc1;
    address constant ADAPTER = address(0xAD);
    string internal adapterConfig;
    string internal vaultConfig;
    string internal marketConfig;
    DeployMorphoAdapter deployer;

    function setUp() public {
        vm.chainId(1);
        vm.mockCall(PARENT, abi.encodeWithSignature("asset()"), abi.encode(ASSET));
        vm.mockCall(
            FACTORY,
            abi.encodeCall(IMorphoMarketV1AdapterV2Factory.createMorphoMarketV1AdapterV2, (PARENT)),
            abi.encode(ADAPTER)
        );
        vm.mockCall(address(0xCA11), bytes(""), bytes(""));
        deployer = new DeployMorphoAdapterPayloadsHarness();
    }

    function prepareConfigs(string memory name) internal {
        string memory root = string.concat("cache/test/payloads/", name, "/");
        adapterConfig = string.concat(root, "adapters/tgld_usdc_market_adapter.toml");
        vaultConfig = string.concat(root, "vaults/vault.toml");
        marketConfig = string.concat(root, "markets/tgld_stgld_usdc_market.toml");
        vm.createDir(string.concat(root, "adapters"), true);
        vm.createDir(string.concat(root, "vaults"), true);
        vm.createDir(string.concat(root, "markets"), true);
        string memory adapter = vm.readFile("config/mainnet/tgld/adapters/tgld_usdc_market_adapter.toml");
        vm.writeFile(adapterConfig, vm.replace(adapter, "is_new_adapter = false", "is_new_adapter = true"));
        vm.writeFile(vaultConfig, vm.readFile("config/mainnet/tgld/vaults/tgld_usdc_vault.toml"));
        string memory market = vm.readFile("config/mainnet/tgld/markets/tgld_stgld_usdc_market.toml");
        market = vm.replace(market, "1_000_000_000000", "500_000_000000");
        vm.writeFile(marketConfig, vm.replace(market, "200000000000000000", "100000000000000000"));
    }

    function test_PrintsRegistrationAndAllCapPayloads() public {
        prepareConfigs("test_PrintsRegistrationAndAllCapPayloads");
        MarketParams memory market = MarketParams(
            ASSET,
            0x8d301801d899dC81fEabBDE69407A53b82bdBF19,
            0x150dB979573A2344dFC2Ee0D635194d0a71CEA19,
            0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC,
            860000000000000000
        );
        expectOperation(abi.encodeCall(IVaultV2.addAdapter, (ADAPTER)));
        expectCaps(abi.encode("this", ADAPTER), 1_000_000e6, 0.2e18);
        expectCaps(abi.encode("collateralToken", market.collateralToken), 500_000e6, 0.1e18);
        expectCaps(abi.encode("this/marketParams", ADAPTER, market), 500_000e6, 0.1e18);

        DeployMorphoAdapter.DeploymentResult memory result = deployer.run(adapterConfig, vaultConfig);
        assertEq(result.adapter, ADAPTER);
    }

    function test_RevertWhenMarketVaultConfigMissing() public {
        prepareConfigs("test_RevertWhenMarketVaultConfigMissing");
        vm.expectRevert("MARKET deployment requires run(string,string) with vault config");
        deployer.run(adapterConfig);
    }

    function test_RevertWhenVaultAssetDiffers() public {
        prepareConfigs("test_RevertWhenVaultAssetDiffers");
        vm.writeFile(vaultConfig, vm.replace(vm.readFile(vaultConfig), vm.toString(ASSET), vm.toString(address(1))));
        vm.expectRevert("vault asset does not match adapter config");
        deployer.run(adapterConfig, vaultConfig);
    }

    function test_RevertWhenAdapterNotDeclaredByVault() public {
        prepareConfigs("test_RevertWhenAdapterNotDeclaredByVault");
        vm.writeFile(vaultConfig, vm.replace(vm.readFile(vaultConfig), "tgld_usdc_market_adapter", "another_adapter"));
        vm.expectRevert("adapter config not declared by vault");
        deployer.run(adapterConfig, vaultConfig);
    }

    function test_RevertWhenNoMarketDeclared() public {
        prepareConfigs("test_RevertWhenNoMarketDeclared");
        vm.writeFile(vaultConfig, vm.replace(vm.readFile(vaultConfig), "[\"tgld_stgld_usdc_market\"]", "[]"));
        vm.expectRevert("exactly one market required for the MARKET adapter");
        deployer.run(adapterConfig, vaultConfig);
    }

    function expectCaps(bytes memory id, uint256 absoluteCap, uint256 relativeCap) internal {
        expectOperation(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (id, absoluteCap)));
        expectOperation(abi.encodeCall(IVaultV2.increaseRelativeCap, (id, relativeCap)));
    }

    function expectOperation(bytes memory execution) internal {
        vm.expectCall(address(0xCA11), abi.encodeCall(IPayloadCheck.check, (PARENT, execution)), 1);
    }
}
