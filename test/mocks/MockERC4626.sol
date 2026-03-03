// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC4626} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";

contract MockERC4626 is ERC4626, ERC20Permit {
    constructor(string memory name, string memory symbol, IERC20 asset_)
        ERC20(name, symbol)
        ERC20Permit(name)
        ERC4626(asset_)
    {}

    function decimals() public view virtual override(ERC20, ERC4626) returns (uint8) {
        return super.decimals();
    }

    // mark this as a test contract
    function test() public {}
}
