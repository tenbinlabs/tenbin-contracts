// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
    AccessControlUpgradeable
} from "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {IStakedAsset} from "../../src/interface/IStakedAsset.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol";

/// @dev Paused version of staked asset
contract StakedAssetPause is IERC20, IERC4626, IStakedAsset, UUPSUpgradeable, AccessControlUpgradeable {
    /// @notice Emitted when contract is in a paused state
    error ContractPaused();

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function decimals() external pure override returns (uint8) {
        revert ContractPaused();
    }

    function name() external pure override returns (string memory) {
        revert ContractPaused();
    }

    function symbol() external pure override returns (string memory) {
        revert ContractPaused();
    }

    function totalSupply() external pure override returns (uint256) {
        revert ContractPaused();
    }

    function balanceOf(
        address /*account*/
    )
        external
        pure
        override
        returns (uint256)
    {
        revert ContractPaused();
    }

    function transfer(
        address,
        /*to*/
        uint256 /*shares*/
    )
        external
        pure
        override
        returns (
            bool /*success*/
        )
    {
        revert ContractPaused();
    }

    function transferFrom(
        address,
        /*from*/
        address,
        /*to*/
        uint256 /*shares*/
    )
        external
        pure
        override
        returns (
            bool /*success*/
        )
    {
        revert ContractPaused();
    }

    function approve(
        address,
        /*spender*/
        uint256 /*shares*/
    )
        external
        pure
        override
        returns (
            bool /*success*/
        )
    {
        revert ContractPaused();
    }

    function allowance(
        address,
        /*owner*/
        address /*spender*/
    )
        external
        pure
        override
        returns (uint256)
    {
        revert ContractPaused();
    }

    function asset() external pure override returns (address) {
        revert ContractPaused();
    }

    function totalAssets() external pure override returns (uint256) {
        revert ContractPaused();
    }

    function convertToAssets(
        uint256 /*shares*/
    )
        external
        pure
        override
        returns (
            uint256 /*assets*/
        )
    {
        revert ContractPaused();
    }

    function convertToShares(
        uint256 /*assets*/
    )
        external
        pure
        override
        returns (
            uint256 /*shares*/
        )
    {
        revert ContractPaused();
    }

    function deposit(
        uint256,
        /*assets*/
        address /*onBehalf*/
    )
        external
        pure
        override
        returns (
            uint256 /*shares*/
        )
    {
        revert ContractPaused();
    }

    function mint(
        uint256,
        /*shares*/
        address /*onBehalf*/
    )
        external
        pure
        override
        returns (
            uint256 /*assets*/
        )
    {
        revert ContractPaused();
    }

    function withdraw(
        uint256,
        /*assets*/
        address,
        /*onBehalf*/
        address /*receiver*/
    )
        external
        pure
        override
        returns (
            uint256 /*shares*/
        )
    {
        revert ContractPaused();
    }

    function redeem(
        uint256,
        /*shares*/
        address,
        /*onBehalf*/
        address /*receiver*/
    )
        external
        pure
        override
        returns (
            uint256 /*assets*/
        )
    {
        revert ContractPaused();
    }

    function previewDeposit(
        uint256 /*assets*/
    )
        external
        pure
        override
        returns (
            uint256 /*shares*/
        )
    {
        revert ContractPaused();
    }

    function previewMint(
        uint256 /*shares*/
    )
        external
        pure
        override
        returns (
            uint256 /*assets*/
        )
    {
        revert ContractPaused();
    }

    function previewWithdraw(
        uint256 /*assets*/
    )
        external
        pure
        override
        returns (
            uint256 /*shares*/
        )
    {
        revert ContractPaused();
    }

    function previewRedeem(
        uint256 /*shares*/
    )
        external
        pure
        override
        returns (
            uint256 /*assets*/
        )
    {
        revert ContractPaused();
    }

    function maxDeposit(
        address /*onBehalf*/
    )
        external
        pure
        override
        returns (
            uint256 /*assets*/
        )
    {
        revert ContractPaused();
    }

    function maxMint(
        address /*onBehalf*/
    )
        external
        pure
        override
        returns (
            uint256 /*shares*/
        )
    {
        revert ContractPaused();
    }

    function maxWithdraw(
        address /*onBehalf*/
    )
        external
        pure
        override
        returns (
            uint256 /*assets*/
        )
    {
        revert ContractPaused();
    }

    function maxRedeem(
        address /*onBehalf*/
    )
        external
        pure
        override
        returns (
            uint256 /*shares*/
        )
    {
        revert ContractPaused();
    }

    function pendingRewards()
        external
        pure
        override
        returns (
            uint256 /*pending*/
        )
    {
        revert ContractPaused();
    }

    function reward(
        uint256 /*assets*/
    )
        external
        pure
        override
    {
        revert ContractPaused();
    }

    function cooldownShares(
        address, /*owner*/
        uint256 /*shares*/
    )
        external
        pure
        override
        returns (
            uint256 /*assets*/
        )
    {
        revert ContractPaused();
    }

    function cooldownAssets(
        address, /*owner*/
        uint256 /*assets*/
    )
        external
        pure
        override
        returns (
            uint256 /*shares*/
        )
    {
        revert ContractPaused();
    }

    function unstake(
        address /*to*/
    )
        external
        pure
        override
    {
        revert ContractPaused();
    }
}
