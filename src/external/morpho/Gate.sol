// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
    IReceiveSharesGate,
    ISendSharesGate,
    IReceiveAssetsGate,
    ISendAssetsGate
} from "lib/vault-v2/src/interfaces/IGate.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";

/// @notice Gate used to restrict vault deposits/withdrawals to a single manager account
/// https://docs.morpho.org/curate/concepts/gates/#gates-in-vault-v2
contract Gate is IReceiveSharesGate, ISendSharesGate, IReceiveAssetsGate, ISendAssetsGate, Ownable {
    /// @notice Manager can receive/send shares and receive/send assets
    address manager;

    constructor(address owner_) Ownable(owner_) {}

    function setManager(address newManager) external onlyOwner {
        manager = newManager;
    }

    function canReceiveShares(address account) external view returns (bool) {
        return account == manager;
    }

    function canSendShares(address account) external view returns (bool) {
        return account == manager;
    }

    function canReceiveAssets(address account) external view returns (bool) {
        return account == manager;
    }

    function canSendAssets(address account) external view returns (bool) {
        return account == manager;
    }
}
