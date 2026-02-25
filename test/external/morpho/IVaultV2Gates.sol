// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IVaultV2Gates {
    function receiveSharesGate() external view returns (address);
    function sendSharesGate() external view returns (address);
    function receiveAssetsGate() external view returns (address);
    function sendAssetsGate() external view returns (address);
}
