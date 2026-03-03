// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {ICollateralManager} from "../../src/interface/ICollateralManager.sol";

contract MockReentrantERC20 is ERC20 {
    uint8 private immutable _decimals;
    bool triggerReentrancy;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        if (triggerReentrancy) {
            address manager = msg.sender;
            ICollateralManager(manager).withdrawRevenue(address(2), 1);
        } else {
            address owner = _msgSender();
            _transfer(owner, to, value);
        }

        return true;
    }

    function setTriggerReentrancy(bool newStatus) external {
        triggerReentrancy = newStatus;
    }
}
