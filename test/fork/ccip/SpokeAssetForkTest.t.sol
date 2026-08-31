// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetToken} from "../../../src/AssetToken.sol";
import {CCIPForkBase} from "./CCIPForkBase.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SpokeERC20} from "../../../src/external/chainlink/SpokeERC20.sol";

contract SpokeAssetForkTest is CCIPForkBase {
    function deployContracts() internal override {
        createForks();
        vm.selectFork(destinationFork);
        destinationCCIPBnMToken = new SpokeERC20("AssetToken2", "STK", owner);

        vm.selectFork(sourceFork, 11590237);
        asset = AssetToken(ASSET_ADDRESS);
        sourceCCIPBnMToken = IERC20(ASSET_ADDRESS);
    }

    function mintTokens(uint256 amount) internal override {
        vm.selectFork(sourceFork);
        vm.prank(asset.minter());
        asset.mint(alice, amount);
    }
}
