// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title OracleAdapter
/// @notice Normalize price data from an external source into a standard representation
interface IOracleAdapter {
    /// @notice Thrown when adding an oracle with incompatible decimals
    error InvalidOracleDecimals();
    /// @notice Returned data from oracle fails to pass verifications
    error InvalidOraclePrice();
    /// @dev Oracle price is stale based on staleness threshold
    error OraclePriceStale();

    /// @notice Returns price with 18 decimals of precision
    /// @return price Price with 18 decimals of precision
    function getPrice() external view returns (uint256 price);

    /// @notice Address of oracle used by this adapter
    /// @return oracleAddress Oracle address
    function oracle() external view returns (address oracleAddress);
}
