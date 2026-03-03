// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "../BaseTest.sol";
import {CollateralManagerHandler} from "../invariant/handlers/CollateralManagerHandler.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

// forge test --mc CollateralManagerInvariantTest -vvvv
contract CollateralManagerInvariantTest is BaseTest {
    CollateralManagerHandler handler;

    function setUp() public override {
        super.setUp();

        handler = new CollateralManagerHandler(
            manager, collateral, swapModule, router, admin, curator, capAdjuster, rebalancer, owner
        );

        targetContract(address(handler));
    }

    // - For every supported collateral its assigned vault must have it as the underlying asset, `IERC4626(vault).asset() == collateral`
    function invariant_VaultCollateralAddress() public view {
        if (handler.counter() > 0) {
            for (uint256 i = 0; i < handler.counter(); i++) {
                address coll = handler.addedCollaterals(i);
                IERC4626 currentVault = manager.vaults(coll);
                assertEq(currentVault.asset(), coll);
            }
        }
    }

    // - Collaterals vaults are immutable, meaning once the vault is assigned there is no possible migration
    function invariant_ImmutableVaults() public view {
        for (uint256 i = 0; i < handler.counter(); i++) {
            assertEq(address(manager.vaults(handler.addedCollaterals(i))), handler.addedVaults(i));
        }
    }

    // - `controller` can never be the zero address
    function invariant_ControllerAddress() public view {
        assertNotEq(manager.controller(), address(0));
    }

    // - `swapModule` can never be the zero address
    function invariant_SwapModuleAddress() public view {
        assertNotEq(manager.swapModule(), address(0));
    }

    // - The sum of all assets in vaults + pending revenue should always equal total managed collateral (minus withdrawals).
    function invariant_BalanceSymmetry() public view {
        uint256 actual = vault.totalAssets(); // default vault
        for (uint256 i = 0; i < handler.counter(); i++) {
            address coll = handler.addedCollaterals(i);
            IERC4626 currentVault = manager.vaults(coll);
            actual += currentVault.totalAssets();
        }

        uint256 totalCollateral = handler.totalCollateral();
        uint256 totalWithdraw = handler.totalWithdraw();
        uint256 expected = totalCollateral - totalWithdraw;

        assertApproxEqAbs(actual, expected, 1e6);
    }
}
