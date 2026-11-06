// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../../script/Deploy.s.sol";
import {IMorpho, MarketParams} from "vault-v2/lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "vault-v2/lib/morpho-blue/src/libraries/MarketParamsLib.sol";

contract DeployMarketValidationHarness is Deploy {
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

    function marketParams() internal pure returns (MarketParams memory) {
        return MarketParams(address(1), address(2), address(3), address(4), 5);
    }
}
