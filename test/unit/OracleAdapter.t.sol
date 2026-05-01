// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ChainlinkOracleAdapter} from "../../src/oracle/ChainlinkOracleAdapter.sol";
import {IOracleAdapter} from "../../src/interface/IOracleAdapter.sol";
import {MockAggregator} from "../mocks/MockAggregator.sol";
import {Test} from "forge-std/Test.sol";

contract OracleAdapterTest is Test {
    uint256 internal constant ADAPTER_PRECISION = 1e10;

    MockAggregator internal aggregator;
    ChainlinkOracleAdapter internal adapter;

    function setUp() public {
        aggregator = new MockAggregator();
        aggregator.setDecimals(18);
        adapter = new ChainlinkOracleAdapter(address(aggregator), 1 days);
    }

    function test_Revert_Deploy_OracleAdapter() public {
        aggregator.setDecimals(19);
        vm.expectRevert(IOracleAdapter.InvalidOracleDecimals.selector);
        new ChainlinkOracleAdapter(address(aggregator), 1 days);

        aggregator.setDecimals(5);
        vm.expectRevert(IOracleAdapter.InvalidOracleDecimals.selector);
        new ChainlinkOracleAdapter(address(aggregator), 1 days);
    }

    function test_Revert_getPrice() public {
        // rounds freshness
        vm.warp(block.timestamp + 3 days);
        aggregator.switchIsFresh();
        vm.expectRevert(IOracleAdapter.OraclePriceStale.selector);
        adapter.getPrice();

        aggregator.switchIsFresh();
        aggregator.setRoundId(1);

        // invalid price
        aggregator.setAnswer(0);
        vm.expectRevert(IOracleAdapter.InvalidOraclePrice.selector);
        adapter.getPrice();
    }

    function test_fuzz_OracleAdapter_decimals(uint8 decimals) public {
        decimals = uint8(bound(decimals, 6, 18));
        aggregator.setDecimals(decimals);
        adapter = new ChainlinkOracleAdapter(address(aggregator), decimals);
        aggregator.setAnswer(1 * 10 ** decimals);
        assertEq(adapter.getPrice(), 1e18);
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
