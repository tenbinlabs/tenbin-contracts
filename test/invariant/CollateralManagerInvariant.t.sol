// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {CollateralManagerHandler} from "./handlers/CollateralManagerHandler.sol";
import {ICollateralManager} from "../../src/interface/ICollateralManager.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {InvariantBase} from "./InvariantBase.sol";

// echidna: echidna test/invariant/CollateralManagerInvariant.t.sol --contract CollateralManagerInvariantTest --config echidna.yaml
// foundry: forge test --mc CollateralManagerInvariantTest -vvvv
contract CollateralManagerInvariantTest is InvariantBase {
    CollateralManagerHandler handler;

    function setUp() public override {
        super.setUp();

        handler = new CollateralManagerHandler(
            manager, collateral, swapModule, router, admin, curator, capAdjuster, rebalancer, owner
        );

        targetContract(address(handler));
    }

    // For every supported collateral its assigned vault must have it as the underlying asset, `IERC4626(vault).asset() == collateral`
    function invariant_VaultCollateralAddress() public view {
        if (handler.counter() > 0) {
            for (uint256 i = 0; i < handler.counter(); i++) {
                address coll = handler.addedCollaterals(i);
                IERC4626 currentVault = manager.vaults(coll);
                assertEq(currentVault.asset(), coll);
            }
        }
    }

    // Collaterals vaults are immutable, meaning once the vault is assigned there is no possible migration
    function invariant_ImmutableVaults() public view {
        for (uint256 i = 0; i < handler.counter(); i++) {
            assertEq(address(manager.vaults(handler.addedCollaterals(i))), handler.addedVaults(i));
        }
    }

    // `controller` can never be the zero address
    function invariant_ControllerAddress() public view {
        assertNotEq(manager.controller(), address(0));
    }

    // `swapModule` can never be the zero address
    function invariant_SwapModuleAddress() public view {
        assertNotEq(manager.swapModule(), address(0));
    }

    // The sum of all assets in vaults + pending revenue should never be less than total managed collateral (minus withdrawals).
    function invariant_BalanceCoversManagedCollateral() public view {
        uint256 actual = vault.totalAssets();

        for (uint256 i = 0; i < handler.counter(); i++) {
            address coll = handler.addedCollaterals(i);
            IERC4626 currentVault = manager.vaults(coll);
            actual += currentVault.totalAssets();
        }

        uint256 expected = handler.totalCollateral() - handler.totalWithdraw();

        assertGe(actual + 1e6, expected);
    }

    // Revenue module is never the zero address
    function invariant_revenueModule_never_zero_address() public view {
        assertNotEq(manager.revenueModule(), address(0));
    }

    // Zero address is never a valid collateral
    function invariant_zero_address_is_never_collateral() public view {
        assertEq(address(manager.vaults(address(0))), address(0));
    }

    //-------------------- Access Control Invariants-----------------------------------

    // setPauseStatus always revert unauthorized callers
    function invariant_setPauseStatus_only_gatekeeper_callable() public {
        try manager.setPauseStatus(ICollateralManager.ManagerPauseStatus.FMLPause) {
            assertTrue(false);
        } catch {
            assertTrue(true);
        }
    }

    // setRebalanceCap always revert unauthorized callers
    function invariant_setRebalanceCap_only_capadjuster_callable() public {
        try manager.setRebalanceCap(address(asset), 1e18) {
            assertTrue(false);
        } catch {
            assertTrue(true);
        }
    }

    // setSwapCap always revert unauthorized callers
    function invariant_setSwapCap_only_capadjuster_callable() public {
        try manager.setSwapCap(address(asset), 1e18) {
            assertTrue(false);
        } catch {
            assertTrue(true);
        }
    }

    // setMinSwapPrice always revert unauthorized callers
    function invariant_setMinSwapPrice_only_capadjuster_callable() public {
        try manager.setMinSwapPrice(address(asset), address(asset), 1e18) {
            assertTrue(false);
        } catch {
            assertTrue(true);
        }
    }

    // getRevenue only returns existing collaterals
    function invariant_getRevenue_always_revert_non_collateral() public view {
        try manager.getRevenue(address(asset)) {
            assertTrue(false);
        } catch {
            assertTrue(true);
        }
    }

    // getVaultAssets always revert when trying to verify non collateral
    function invariant_getVaultAssets_always_revert_non_collateral() public view {
        try manager.getVaultAssets(address(asset)) {
            assertTrue(false);
        } catch {
            assertTrue(true);
        }
    }

    // Deposits only accepts collateral tokens
    function invariant_deposit_always_revert_non_collateral() public {
        try manager.deposit(address(asset), 1e18, 1e18) {
            assertTrue(false);
        } catch {
            assertTrue(true);
        }
    }

    // Withdraw only accepts collateral tokens
    function invariant_withdraw_always_revert_non_collateral() public {
        try manager.withdraw(address(asset), 1e18, 1e18) {
            assertTrue(false);
        } catch {
            assertTrue(true);
        }
    }

    // withdrawRevenue always revert unauthorized callers
    function invariant_withdrawRevenue_reverts_for_every_non_revenueModule_caller() public {
        try manager.withdrawRevenue(address(asset), 1e18) {
            assertTrue(false);
        } catch {
            assertTrue(true);
        }
    }

    // Only collateral balances can be converted to revenue
    function invariant_convertRevenue_always_revert_non_collateral() public {
        try manager.convertRevenue(address(asset), 1e18) {
            assertTrue(false);
        } catch {
            assertTrue(true);
        }
    }
}
