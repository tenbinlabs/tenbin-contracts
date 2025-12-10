// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {CollateralManager} from "src/CollateralManager.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {ISwapModule} from "src/interface/ISwapModule.sol";

contract CollateralManagerHarness is CollateralManager {
    constructor() CollateralManager() {}

    function exposedVerifySlippage(ISwapModule.SwapParameters memory params) external view {
        _verifySlippage(params);
    }

    function exposedNormalizeTo18(uint256 amount, uint8 decimals) external pure returns (uint256) {
        return _normalizeTo18(amount, decimals);
    }

    function exposedRealizeRevenue(address collateral, IERC4626 vault) external {
        _realizeRevenue(collateral, vault);
    }

    function exposedComputeNewRevenue(address collateral, IERC4626 vault) external view returns (uint256) {
        return _computeNewRevenue(collateral, vault);
    }
}
