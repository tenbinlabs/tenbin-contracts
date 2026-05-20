// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IDistributor} from "../../src/external/merkl/IDistributor.sol";

contract MockDistributor is IDistributor {
    address[] public lastUsers;
    address[] public lastTokens;
    uint256[] public lastAmounts;
    address[] public lastRecipients;

    mapping(address => mapping(address => address)) public claimRecipient;
    mapping(address => mapping(address => uint256)) public operators;

    bytes32[][] internal lastProofs;

    function claim(address[] memory, address[] memory, uint256[] memory, bytes32[][] memory) public pure {
        revert();
    }

    function claimWithRecipient(
        address[] memory users,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes32[][] memory proofs,
        address[] memory recipients,
        bytes[] memory
    ) public {
        if (!_isAuthorized(users[0])) revert();

        delete lastUsers;
        delete lastTokens;
        delete lastAmounts;
        delete lastRecipients;
        delete lastProofs;

        _copyClaimInputs(users, tokens, amounts, recipients);
        _copyProofs(proofs);
    }

    function _copyClaimInputs(
        address[] memory users,
        address[] memory tokens,
        uint256[] memory amounts,
        address[] memory recipients
    ) internal {
        for (uint256 i; i < users.length; ++i) {
            lastUsers.push(users[i]);
            lastTokens.push(tokens[i]);
            lastAmounts.push(amounts[i]);
            lastRecipients.push(recipients[i]);
        }
    }

    function _copyProofs(bytes32[][] memory proofs) internal {
        for (uint256 i; i < proofs.length; ++i) {
            lastProofs.push();

            for (uint256 j; j < proofs[i].length; ++j) {
                lastProofs[i].push(proofs[i][j]);
            }
        }
    }

    function _isAuthorized(address user) internal view returns (bool) {
        return
            msg.sender == user || tx.origin == user || operators[user][msg.sender] == 1
                || operators[user][address(0)] == 1;
    }

    function getProof(uint256 i) external view returns (bytes32[] memory) {
        return lastProofs[i];
    }

    function setClaimRecipient(address recipient, address token) external {
        claimRecipient[msg.sender][token] = recipient;
    }

    function toggleOperator(address user, address operator) external {
        operators[user][operator] = operators[user][operator] == 1 ? 0 : 1;
    }
}
