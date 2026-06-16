// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AggregatorV3Interface} from "chainlink-local/src/data-feeds/interfaces/AggregatorV3Interface.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

/// @title Chainlink Oracle Wrapper
/// @notice Oracle Wrapper for Morpho Markets which converts a Chainlink price feed to 8 decimals
/// Normalizes response from Chainlink aggregator to int256 with 8 decimals
/// Only works for oracles with decimals >= 8
contract ChainlinkOracleWrapper is AggregatorV3Interface {
    using SafeCast for int256;
    using SafeCast for uint256;

    /// @notice Decimals must be >= 8
    error InvalidOracleDecimals();

    /// @notice Decimals for this Aggregator
    uint8 internal constant DECIMALS = 8;

    /// @notice Offset for this Aggregator (precision removed from answer)
    uint8 public immutable offset;

    /// @notice Chainlink Oracle: tGLD/USD - 24/7 Blended Price
    // Uses 1e18 decimal precision
    AggregatorV3Interface public immutable oracle;

    /// @dev Calculate decimals offset given a chainlink oracle
    constructor(AggregatorV3Interface oracle_) {
        oracle = oracle_;
        uint8 oracleDecimals = oracle.decimals();
        if (oracleDecimals < 8) revert InvalidOracleDecimals();
        offset = oracleDecimals - DECIMALS;
    }

    /// @inheritdoc AggregatorV3Interface
    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }

    /// @inheritdoc AggregatorV3Interface
    function description() external view returns (string memory) {
        return oracle.description();
    }

    /// @inheritdoc AggregatorV3Interface
    function version() external view returns (uint256) {
        return oracle.version();
    }

    /// @inheritdoc AggregatorV3Interface
    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = oracle.getRoundData(_roundId);
        answer = answer / (10 ** offset).toInt256();
    }

    /// @inheritdoc AggregatorV3Interface
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = oracle.latestRoundData();
        answer = answer / (10 ** offset).toInt256();
    }
}
