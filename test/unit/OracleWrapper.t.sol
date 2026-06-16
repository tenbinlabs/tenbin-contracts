// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AggregatorV3Interface} from "chainlink-local/src/data-feeds/interfaces/AggregatorV3Interface.sol";
import {ChainlinkOracleWrapper} from "../../src/oracle/ChainlinkOracleWrapper.sol";
import {MockAggregator} from "../mocks/MockAggregator.sol";
import {Test} from "forge-std/Test.sol";

contract OracleWrapperTest is Test {
    uint256 internal constant WRAPPER_OFFSET = 1e10;

    MockAggregator internal aggregator;
    ChainlinkOracleWrapper internal wrapper;

    function setUp() public {
        aggregator = new MockAggregator();
        aggregator.setDecimals(18);
        wrapper = new ChainlinkOracleWrapper(aggregator);
    }

    function test_SetUp() public view {
        assertEq(wrapper.description(), aggregator.description());
        assertEq(wrapper.version(), aggregator.version());
    }

    function test_GetRoundData() public {
        aggregator.setAnswer(1e18);
        (, int256 answer,,,) = wrapper.getRoundData(1);
        assertEq(answer, 1e8);
    }

    function test_Revert_Deploy_OracleWrapper() public {
        aggregator.setDecimals(5);
        vm.expectRevert(ChainlinkOracleWrapper.InvalidOracleDecimals.selector);
        new ChainlinkOracleWrapper(aggregator);
    }

    function test_fuzz_OracleWrapper_decimals(uint8 decimals) public {
        decimals = uint8(bound(decimals, 8, 18));
        aggregator.setDecimals(decimals);
        wrapper = new ChainlinkOracleWrapper(aggregator);
        aggregator.setAnswer(10 ** decimals);
        assertEq(getAnswer(wrapper), 1e8);
    }

    function test_OracleWrapper() public {
        aggregator.setAnswer(1e18);
        assertEq(getAnswer(wrapper), 1e8);
    }

    function test_fuzz_OracleWrapper(uint256 price) public {
        price = bound(price, WRAPPER_OFFSET, 1e40);
        aggregator.setAnswer(price);
        assertApproxEqAbs(uint256(getAnswer(wrapper)) * WRAPPER_OFFSET, price, WRAPPER_OFFSET);
    }

    // helper to get answer from a chainlink aggregator
    function getAnswer(AggregatorV3Interface oracle) internal view returns (int256 answer) {
        (, answer,,,) = oracle.latestRoundData();
    }
}
