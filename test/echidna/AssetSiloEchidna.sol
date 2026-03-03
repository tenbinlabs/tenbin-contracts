// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetSilo} from "../../src/AssetSilo.sol";
import {EchidnaBase} from "./EchidnaBase.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockERC4626} from "../mocks/MockERC4626.sol";

// echidna test/echidna/AssetSiloEchidna.sol --contract AssetSiloEchidna --config echidna.yaml
contract AssetSiloEchidna is EchidnaBase {
    AssetSilo silo;
    MockERC4626 staking;

    constructor() {
        staking = new MockERC4626("Staking vault", "STK", asset);
        silo = new AssetSilo(address(staking), address(asset));
    }

    // Allowance for staking is constant
    function echidna_asset_allowance_is_uint_max() public view returns (bool) {
        return asset.allowance(address(silo), address(staking)) == type(uint256).max;
    }
}
