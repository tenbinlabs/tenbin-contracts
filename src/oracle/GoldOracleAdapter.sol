// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AggregatorV3Interface} from "chainlink-local/src/data-feeds/interfaces/AggregatorV3Interface.sol";
import {IOracleAdapter} from "../interface/IOracleAdapter.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

/// @title Gold Oracle Adapter
/// @notice Normalize oracle data from a Chainlink aggregator into a standard representation
contract GoldOracleAdapter is IOracleAdapter {
    using SafeCast for int256;

    /// @dev Difference between oracle decimals and 1e18
    uint256 internal constant DECIMALS_OFFSET = 1e10;

    /// @notice Stale price threshold (e.g., 24 hours for XAU/USD)
    uint256 public constant PRICE_STALENESS_THRESHOLD = 1 days;

    /// @notice Chainlink oracle
    AggregatorV3Interface public immutable oracle;

    /// @param oracle_ Address of chainlink oracle
    constructor(address oracle_) {
        oracle = AggregatorV3Interface(oracle_);
        if (oracle.decimals() != 8) revert InvalidOracleDecimals();
    }

    /// @inheritdoc IOracleAdapter
    /// @dev Return price in USD with 18 decimals
    function getPrice() external view returns (uint256) {
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = oracle.latestRoundData();

        // valid round
        if (answeredInRound != roundId) revert IncorrectOracleRound();

        // Check for stale price
        if (block.timestamp - updatedAt > PRICE_STALENESS_THRESHOLD) revert OraclePriceStale();

        // Check for invalid price
        if (answer <= 0) revert InvalidOraclePrice();

        return answer.toUint256() * DECIMALS_OFFSET;
    }
}
