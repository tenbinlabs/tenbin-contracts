// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AggregatorV3Interface} from "chainlink-local/src/data-feeds/interfaces/AggregatorV3Interface.sol";
import {IOracleAdapter} from "../interface/IOracleAdapter.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

/// @title MXN Oracle Adapter
/// @notice Oracle Adapter for Chainlink MXN/USD oracle
/// hhttps://data.chain.link/feeds/ethereum/mainnet/mxn-usd
///
/// Normalizes response from Chainlink aggregator to uint256 with 18 decimals
/// https://etherscan.io/address/0xdb4881Ab0ad6b8423f76dd8C9d65542749a1dB77
contract MXNOracleAdapter is IOracleAdapter {
    using SafeCast for int256;

    /// @notice Stale price threshold for this oracle
    uint256 public constant PRICE_STALENESS_THRESHOLD = 86400 seconds;

    /// @notice Difference between the target precicion (1e18) and the oracle precision
    /// For MXN/USD, the precision is 1e8
    uint256 public constant OFFSET = 1e10;

    /// @notice Chainlink Oracle: MXN/USD
    // Uses 1e8 decimal precision
    address public constant oracle = 0xdb4881Ab0ad6b8423f76dd8C9d65542749a1dB77;

    /// @inheritdoc IOracleAdapter
    /// @dev Return price in USD with 18 decimals
    function getPrice() external view returns (uint256) {
        (, int256 answer,, uint256 updatedAt,) = AggregatorV3Interface(oracle).latestRoundData();

        // Check for stale price
        if (block.timestamp - updatedAt > PRICE_STALENESS_THRESHOLD) revert OraclePriceStale();

        // Check for invalid price
        if (answer <= 0) revert InvalidOraclePrice();

        // normalize to 18 decimals based on offset
        return answer.toUint256() * OFFSET;
    }
}
