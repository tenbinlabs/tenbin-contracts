// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {MockAggregator} from "test/mocks/MockAggregator.sol";
import {IOracleAdapter} from "src/interface/IOracleAdapter.sol";
import {GoldOracleAdapter} from "src/oracle/GoldOracleAdapter.sol";
import {Test} from "forge-std/Test.sol";

contract OracleAdapterTest is Test {
    uint256 internal constant ADAPTER_PRECISION = 1e10;

    MockAggregator internal aggregator;
    GoldOracleAdapter internal adapter;

    function setUp() public {
        aggregator = new MockAggregator();
        adapter = new GoldOracleAdapter(address(aggregator));
    }

    function test_Revert_Deploy() public {
        aggregator.setDecimals(2);
        vm.expectRevert(IOracleAdapter.InvalidOracleDecimals.selector);
        new GoldOracleAdapter(address(aggregator));
    }

    function test_Revert_getPrice() public {
        // rounds freshness
        vm.warp(block.timestamp + 3 days);
        aggregator.switchIsFresh();
        vm.expectRevert(IOracleAdapter.OraclePriceStale.selector);
        adapter.getPrice();

        aggregator.switchIsFresh();

        // round correctness
        aggregator.setRoundId(2);
        vm.expectRevert(IOracleAdapter.IncorrectOracleRound.selector);
        adapter.getPrice();

        aggregator.setRoundId(1);

        // invalid price
        aggregator.setAnswer(0);
        vm.expectRevert(IOracleAdapter.InvalidOraclePrice.selector);
        adapter.getPrice();
    }

    function test_OracleAdapter() public {
        aggregator.setAnswer(1e18);
        assertEq(adapter.getPrice(), 1e18);
    }

    function test_fuzz_OracleAdapter(uint256 price) public {
        price = bound(price, ADAPTER_PRECISION, 1e48);
        aggregator.setAnswer(price);
        assertApproxEqAbs(adapter.getPrice(), price, ADAPTER_PRECISION);
    }
}
