// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AggregatorV3Interface} from "chainlink-local/src/data-feeds/interfaces/AggregatorV3Interface.sol";
import {IOracleAdapter} from "../interface/IOracleAdapter.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

/// @title Chainlink Oracle Adapter
/// @notice Normalize oracle data from a Chainlink aggregator into a standard representation
contract ChainlinkOracleAdapter is IOracleAdapter {
    using SafeCast for int256;

    /// @dev Amount to offset the answer by.
    /// ex. If an oracle has 8 decimals precision, multiple the answer by 1e18 to normalize to 18 decimals
    uint256 public immutable offset;

    /// @notice Stale price threshold (e.g., 24 hours for XAU/USD)
    uint256 public immutable stalenessThreshold;

    /// @notice Chainlink oracle
    address public immutable oracle;

    /// @notice Constructor for a generic Chainlink Oracle Adapters
    /// @param oracle_ Address of chainlink oracle
    /// @param stalenessThreshold_ Staleness threshold of this oracle in seconds
    constructor(address oracle_, uint256 stalenessThreshold_) {
        oracle = oracle_;
        uint8 decimals = AggregatorV3Interface(oracle).decimals();
        if (decimals > 18 || decimals < 6) revert InvalidOracleDecimals();
        offset = decimals == 18 ? 1 : 10 ** (18 - decimals);
        stalenessThreshold = stalenessThreshold_;
    }

    /// @inheritdoc IOracleAdapter
    /// @dev Return price in USD with 18 decimals
    function getPrice() external view returns (uint256) {
        (, int256 answer,, uint256 updatedAt,) = AggregatorV3Interface(oracle).latestRoundData();

        // Check for stale price
        if (block.timestamp - updatedAt > stalenessThreshold) revert OraclePriceStale();

        // Check for invalid price
        if (answer <= 0) revert InvalidOraclePrice();

        return answer.toUint256() * offset;
    }
}
