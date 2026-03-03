// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {CollateralManager} from "../../src/CollateralManager.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

contract CollateralManagerHarness is CollateralManager {
    constructor() CollateralManager() {}

    function exposedGetRevenue(address collateral, IERC4626 vault) external view returns (uint256) {
        return _getRevenue(collateral, vault);
    }

    function exposedTotalAssets(IERC4626 vault) external view returns (uint256) {
        return _totalAssets(vault);
    }
}
