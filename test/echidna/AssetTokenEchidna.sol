// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetToken} from "src/AssetToken.sol";
import {EchidnaBase} from "./EchidnaBase.sol";

// echidna test/echidna/AssetTokenEchidna.sol --contract AssetTokenEchidna --config echidna.yaml
contract AssetTokenEchidna is EchidnaBase {
    // setMinter always revert when caller is not authorized
    function echidna_setMinter_only_owner_callable() public returns (bool) {
        try asset.setMinter(address(1)) {
            return false;
        } catch {
            return true;
        }
    }

    // Sum of users balance must not exceed total supply
    function echidna_asset_usersBalancesNotHigherThanSupply() public view returns (bool) {
        uint256 balance = asset.balanceOf(USER1) + asset.balanceOf(USER2) + asset.balanceOf(USER3);
        return balance <= asset.totalSupply();
    }
}
