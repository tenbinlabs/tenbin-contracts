// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AggregatorV3Interface} from "chainlink-local/src/data-feeds/interfaces/AggregatorV3Interface.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

/// @title Mock chainlink oracle which allows setting price directly
contract MockAggregator is AggregatorV3Interface {
    using SafeCast for uint256;

    /// @dev Mock answer
    int256 mockAnswer;

    /// @dev Mock decimals
    uint8 public decimals = 8;

    /// @dev Mock round id
    uint80 latestRoundId = 1;

    /// @dev indicates whether updatedAt will be fresh or not
    bool isFresh;

    /// @dev Get answer
    function latestAnswer() external view returns (int256) {
        return mockAnswer;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (latestRoundId, mockAnswer, block.timestamp, isFresh ? 0 : block.timestamp, 1);
    }

    /// @dev Set answer by converting uint256 with 18 decimals to int256 with 8 decimals
    function setAnswer(uint256 newAnswer) external {
        mockAnswer = (newAnswer / 1e10).toInt256();
    }

    /// @dev Set decimals amount
    function setDecimals(uint8 newDecimals) external {
        decimals = newDecimals;
    }

    /// @dev Set round id
    function setRoundId(uint80 newId) external {
        latestRoundId = newId;
    }

    /// @dev Switch failUpdate value
    function switchIsFresh() public {
        isFresh = !isFresh;
    }

    function description() external view returns (string memory) {}

    function version() external view returns (uint256) {}

    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {}
}
