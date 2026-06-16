// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Minimal version of Merkl's rewards distributor contract at 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae
interface IDistributor {
    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external;
    function claimWithRecipient(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs,
        address[] calldata recipients,
        bytes[] memory datas
    ) external;
    function setClaimRecipient(address recipient, address token) external;
    function toggleOperator(address user, address operator) external;
    function claimRecipient(address user, address token) external returns (address);
}
