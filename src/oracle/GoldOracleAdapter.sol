// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AggregatorV3Interface} from "chainlink-local/src/data-feeds/interfaces/AggregatorV3Interface.sol";
import {IOracleAdapter} from "../interface/IOracleAdapter.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

/// @title Gold Oracle Adapter
/// @notice Oracle Adapter for Chainlink tGLD/USD oracle
/// Normalizes response from Chainlink aggregator to uint256 with 18 decimals
/// https://etherscan.io/address/0x369C67E8b026CC4Ef98350f332D7Dd52b85b7674
contract GoldOracleAdapter is IOracleAdapter {
    using SafeCast for int256;

    /// @notice Stale price threshold (e.g., 24 hours for XAU/USD)
    uint256 public constant PRICE_STALENESS_THRESHOLD = 1 days;

    /// @notice Chainlink Oracle: tGLD/USD - 24/7 Blended Price
    // Uses 1e18 decimal precision
    address public constant oracle = 0x369C67E8b026CC4Ef98350f332D7Dd52b85b7674;

    /// @inheritdoc IOracleAdapter
    /// @dev Return price in USD with 18 decimals
    function getPrice() external view returns (uint256) {
        (, int256 answer,, uint256 updatedAt,) = AggregatorV3Interface(oracle).latestRoundData();

        // Check for stale price
        if (block.timestamp - updatedAt > PRICE_STALENESS_THRESHOLD) revert OraclePriceStale();

        // Check for invalid price
        if (answer <= 0) revert InvalidOraclePrice();

        // already normalized to 1e18, so return uint256
        return answer.toUint256();
    }
}
