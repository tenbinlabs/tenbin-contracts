// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetToken} from "../../../src/AssetToken.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Handler to interact with the asset token and save snapshots for invariant testing
contract AssetTokenHandler is Test {
    AssetToken asset;
    address[] holders = new address[](4);
    address minter;
    uint256 public totalMinted;
    uint256 public totalBurned;
    uint256 public totalBeforeTransfer;
    uint256 public totalAfterTransfer;

    constructor(AssetToken _asset, address _minter) {
        asset = _asset;
        holders[0] = address(0xB00);
        holders[1] = address(0xB01);
        holders[2] = address(0xB02);
        holders[3] = address(0xB03);
        minter = _minter;

        vm.prank(asset.owner());
        asset.setMinter(minter);
    }

    function mint(address to, uint256 amount) public {
        amount = bound(amount, 100, 1e40);
        to = isHolder(to) ? to : getHolder();

        vm.prank(minter);
        asset.mint(to, amount);

        totalMinted += amount;
    }

    function burn(address account, uint256 amount) public {
        vm.assume(account != address(0));
        amount = bound(amount, 100, 1e40);
        // ensure there is something to burn
        address from = getHolder();
        mint(from, amount);

        vm.prank(from);
        asset.approve(account, amount);
        vm.prank(account);
        asset.burn(from, amount);

        totalBurned += amount;
    }

    function transfer(uint256 value) public {
        value = bound(value, 100, 1e40);
        address from = getHolder();
        address to = getHolder();

        mint(from, value);
        totalBeforeTransfer = asset.totalSupply();

        vm.prank(from);
        require(asset.transfer(to, value));
        totalAfterTransfer = asset.totalSupply();
    }

    function transferFrom(uint256 value) public {
        value = bound(value, 100, 1e40);
        address from = getHolder();
        address to = getHolder();

        mint(from, value);

        vm.prank(from);
        asset.approve(address(this), value);

        totalBeforeTransfer = asset.totalSupply();
        require(asset.transferFrom(from, to, value));
        totalAfterTransfer = asset.totalSupply();
    }

    // helper
    function getHolder() public view returns (address) {
        uint256 random = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender)));

        uint256 index = random % holders.length;
        return holders[index];
    }

    function isHolder(address target) public view returns (bool) {
        for (uint256 i = 0; i < holders.length; i++) {
            if (holders[i] == target) {
                return true;
            }
        }
        return false;
    }

    function getHoldersBalances() external view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < holders.length; i++) {
            total += asset.balanceOf(holders[i]);
        }

        return total;
    }
}
