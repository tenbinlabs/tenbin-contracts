// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IUniversalRewardsDistributor} from "../../src/external/morpho/IUniversalRewardsDistributor.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract UniversalRewardsDistributor is IUniversalRewardsDistributor {
    using SafeERC20 for IERC20;

    function claim(address account, address reward, uint256 claimable, bytes32[] calldata)
        external
        returns (uint256 amount)
    {
        amount = claimable;
        IERC20(reward).safeTransfer(account, amount);
    }
}
