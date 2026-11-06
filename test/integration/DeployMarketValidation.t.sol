// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../../script/Deploy.s.sol";
import {IMorpho, MarketParams} from "vault-v2/lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "vault-v2/lib/morpho-blue/src/libraries/MarketParamsLib.sol";

import {IMorphoMarketV1AdapterV2} from "vault-v2/src/adapters/interfaces/IMorphoMarketV1AdapterV2.sol";
import {IVaultV2} from "vault-v2/src/interfaces/IVaultV2.sol";
import {IAdapter} from "vault-v2/src/interfaces/IAdapter.sol";

contract DeployMarketValidationHarness is Deploy {
    function configureMarket(address vault, address adapter, MarketParams memory market) external {
        vaultParams.asset = market.loanToken;
        delete marketConfigList;
        marketConfigList.push(
            MarketParameters("test", market.collateralToken, market.oracle, market.irm, market.lltv, 100e6, 1e18)
        );
        VaultDeploymentResult memory deployment;
        deployment.vault = IVaultV2(vault);
        deployment.adapters = new DeployedAdapter[](1);
        deployment.adapters[0] = DeployedAdapter(IAdapter(adapter), "MARKET", "test");
        capMarkets(deployment);
    }

    function validateMarket(IMorpho morpho, MarketParams memory expected) external view {
        requireMarketExists(morpho, expected);
    }
}

contract DeployMarketValidationTest is Test {
    using MarketParamsLib for MarketParams;

    address constant MORPHO = address(0xBEEF);
    DeployMarketValidationHarness harness = new DeployMarketValidationHarness();

    function test_ValidateExistingMarket() public {
        MarketParams memory market = marketParams();
        vm.mockCall(MORPHO, abi.encodeCall(IMorpho.idToMarketParams, (market.id())), abi.encode(market));

        harness.validateMarket(IMorpho(MORPHO), market);
    }

    function test_RevertWhen_MarketDoesNotExist() public {
        MarketParams memory market = marketParams();
        vm.mockCall(
            MORPHO,
            abi.encodeCall(IMorpho.idToMarketParams, (market.id())),
            abi.encode(MarketParams(address(0), address(0), address(0), address(0), 0))
        );

        vm.expectRevert("configured Morpho market does not exist");
        harness.validateMarket(IMorpho(MORPHO), market);
    }

    function test_ConfigureCompatibleMarketCaps() public {
        MarketParams memory market = marketParams();
        address adapter = address(0xAD);
        address vault = address(0xCA9);
        vm.mockCall(adapter, abi.encodeCall(IMorphoMarketV1AdapterV2.morpho, ()), abi.encode(MORPHO));
        vm.mockCall(adapter, abi.encodeCall(IMorphoMarketV1AdapterV2.adaptiveCurveIrm, ()), abi.encode(market.irm));
        vm.mockCall(MORPHO, abi.encodeCall(IMorpho.idToMarketParams, (market.id())), abi.encode(market));
        vm.mockCall(vault, bytes(""), bytes(""));
        bytes memory collateralId = abi.encode("collateralToken", market.collateralToken);
        bytes memory marketId = abi.encode("this/marketParams", adapter, market);
        vm.expectCall(vault, abi.encodeCall(IVaultV2.increaseAbsoluteCap, (collateralId, 100e6)));
        vm.expectCall(vault, abi.encodeCall(IVaultV2.increaseRelativeCap, (collateralId, 1e18)));
        vm.expectCall(vault, abi.encodeCall(IVaultV2.increaseAbsoluteCap, (marketId, 100e6)));
        vm.expectCall(vault, abi.encodeCall(IVaultV2.increaseRelativeCap, (marketId, 1e18)));

        harness.configureMarket(vault, adapter, market);
    }

    function test_RevertBeforeCapsWhenExistingMarketIrmDiffers() public {
        MarketParams memory market = marketParams();
        address adapter = address(0xAD);
        address vault = address(0xCA9);
        vm.mockCall(adapter, abi.encodeCall(IMorphoMarketV1AdapterV2.morpho, ()), abi.encode(MORPHO));
        vm.mockCall(adapter, abi.encodeCall(IMorphoMarketV1AdapterV2.adaptiveCurveIrm, ()), abi.encode(address(0xBAD)));
        vm.mockCall(MORPHO, abi.encodeCall(IMorpho.idToMarketParams, (market.id())), abi.encode(market));
        vm.mockCallRevert(vault, bytes(""), abi.encodeWithSignature("Error(string)", "cap operation reached"));

        vm.expectRevert("market irm does not match adapter");
        harness.configureMarket(vault, adapter, market);
    }

    function marketParams() internal pure returns (MarketParams memory) {
        return MarketParams(address(1), address(2), address(3), address(4), 5);
    }
}
