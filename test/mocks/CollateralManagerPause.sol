// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
    AccessControlUpgradeable
} from "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ICollateralManager} from "../../src/interface/ICollateralManager.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol";

/// @dev Paused version of collateral manager
contract CollateralManagerPause is ICollateralManager, UUPSUpgradeable, AccessControlUpgradeable {
    /// @notice Emitted when contract is in a paused state
    error ContractPaused();

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function getRevenue(address) external pure returns (uint256) {
        revert ContractPaused();
    }

    function getVaultAssets(address) external pure returns (uint256) {
        revert ContractPaused();
    }

    function deposit(address, uint256, uint256) external pure {
        revert ContractPaused();
    }

    function withdraw(address, uint256, uint256) external pure {
        revert ContractPaused();
    }

    function withdrawRevenue(address, uint256) external pure {
        revert ContractPaused();
    }

    function rebalance(address, uint256) external pure {
        revert ContractPaused();
    }

    function swap(bytes calldata, bytes calldata) external pure {
        revert ContractPaused();
    }

    function setMinSwapPrice(address, address, uint256) external pure {
        revert ContractPaused();
    }

    function setSwapCap(address, uint256) external pure {
        revert ContractPaused();
    }

    function claimMorphoRewards(address, address, uint256, bytes32[] calldata) external pure {
        revert ContractPaused();
    }

    function revenueModule(address) external pure returns (address) {
        revert ContractPaused();
    }

    function convertRevenue(address, uint256) external pure {
        revert ContractPaused();
    }

    // mark this as a test contract
    function test() public {}
}
