// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC4626} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {ICollateralManager} from "../../src/interface/ICollateralManager.sol";

contract MockReentrantERC4626 is ERC4626 {
    bool triggerReentrancy;
    constructor(string memory name, string memory symbol, IERC20 asset_) ERC20(name, symbol) ERC4626(asset_) {}

    function decimals() public view virtual override returns (uint8) {
        return super.decimals();
    }

    function deposit(uint256 assets, address to) public override returns (uint256) {
        // Assume the CM is calling
        address manager = msg.sender;
        if (triggerReentrancy) {
            ICollateralManager(manager).deposit(address(this), 0, 0); // We just want to test reentrancy is not possible
            return 0;
        } else {
            return super.deposit(assets, to);
        }
    }

    function withdraw(uint256 amount, address recipient, address owner) public override returns (uint256) {
        address manager = msg.sender;
        if (triggerReentrancy) {
            ICollateralManager(manager).withdraw(address(2), 1, type(uint256).max); // We just want to test reentrancy is not possible
            return 0;
        } else {
            return super.withdraw(amount, recipient, owner);
        }
    }

    function setTriggerReentrancy(bool newStatus) external {
        triggerReentrancy = newStatus;
    }
}
