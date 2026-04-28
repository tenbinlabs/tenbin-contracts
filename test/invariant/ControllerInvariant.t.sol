// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ControllerHandler} from "./handlers/ControllerHandler.sol";
import {IController} from "../../src/interface/IController.sol";
import {InvariantBase} from "./InvariantBase.sol";

// echidna: echidna test/invariant/ControllerInvariant.t.sol --contract ControllerInvariantTest --config echidna.yaml
// foundry: forge test --mc ControllerInvariantTest -vvvv
contract ControllerInvariantTest is InvariantBase {
    ControllerHandler controllerHandler;

    uint256 initialManagerBalance;
    uint256 initialCustodianBalance;

    function setUp() public virtual override {
        super.setUp();
        controllerHandler = new ControllerHandler(
            ControllerHandler.Config({
                payer: payer,
                recipient: recipient,
                minter: minter,
                signerManager: signerManager,
                gatekeeper: gatekeeper,
                admin: admin,
                payerKey: payerKey,
                minterKey: minterKey,
                controller: controller,
                asset: asset,
                collateral: collateral,
                staking: staking,
                vault: vault
            })
        );

        initialManagerBalance = collateral.balanceOf(controller.manager());
        initialCustodianBalance = collateral.balanceOf(controller.custodian());
        vm.prank(capAdjuster);
        staking.setInstantUnstakeCap(type(uint256).max);

        targetContract(address(controllerHandler));
    }

    // `ratio` must be less or equal to `RATIO_PRECISION`
    function invariant_Ratio() public view {
        assertTrue(controller.ratio() <= RATIO_PRECISION);
    }

    // `custodian` must never be `address(0)`
    function invariant_CustodianAddress() public view {
        assertNotEq(controller.custodian(), address(0));
    }

    // `manager` must never be `address(0)`
    function invariant_ManagerAddress() public view {
        assertNotEq(controller.manager(), address(0));
    }

    // `asset` must never be `address(0)`
    function invariant_AssetAddress() public view {
        assertNotEq(controller.asset(), address(0));
    }

    // No token `totalSupply` can change if `ControllerPauseStatus` ≠ `None`
    function invariant_pausedImpliesConstantSupply() public view {
        bool paused = controller.pauseStatus() != IController.ControllerPauseStatus.None;
        assertTrue(!paused || asset.totalSupply() == controllerHandler.lastAssetSupply());
    }

    // In all states, if ratio == 0, custodian balance equals its previous value
    function invariant_RatioZeroNoChange() public view {
        if (controller.ratio() == 0) {
            assertTrue(controllerHandler.lastCustodianBalance() == collateral.balanceOf(custodian));
        }
    }

    // For all states resulting from a successful mint, custodian balance ≥ previous custodian balance.
    function invariant_RatioPositiveIncreasesCollateral() public view {
        if (controller.ratio() > 0 && controllerHandler.totalMintCollateral() > 0) {
            //In some random sequences setPause is called and no minting happens afterwards
            assertLe(controllerHandler.lastCustodianBalance(), collateral.balanceOf(custodian));
        }
    }

    // Manager never receives more than the minted collateral amount
    function invariant_ManagerBalance() public view {
        uint256 collAmount = controllerHandler.totalMintCollateral() - controllerHandler.totalRedeemCollateral();
        assertLe(controllerHandler.sentToManager(), collAmount);
    }

    // Collateral token `totalSupply` must not change after calling mint or redeem
    function invariant_CollateralSupply() public view {
        assertFalse(controllerHandler.didSupplyChanged());
    }

    // Asset token `totalSupply` must decrease after redeeming
    function invariant_AssetDecreasesOnRedeem() public view {
        assertLe(asset.totalSupply(), controllerHandler.totalAssetSupplyMint());
    }

    // Sum of manager + custodian + vault holdings always equals total collateral amount of the order.
    function invariant_CollateralConservation() public view {
        uint256 collAmount = collateral.totalSupply();
        uint256 managerIncrease = collateral.balanceOf(controller.manager()) - initialManagerBalance;

        uint256 custodianIncrease = collateral.balanceOf(controller.custodian()) - initialCustodianBalance;
        uint256 total = managerIncrease + custodianIncrease + collateral.balanceOf(address(vault));

        assertGe(collAmount, total);
    }

    // Asset token address doesn't change
    function invariant_asset_value() public view {
        assertEq(controller.asset(), address(asset));
    }

    // oracle tolerance always less than MAX_ORACLE_TOLERANCE
    function invariant_oracleTolerance_bound() public view {
        (address adapter, uint96 tolerance) = controller.oracle();
        assertTrue(adapter == address(0) || tolerance < MAX_ORACLE_TOLERANCE);
    }

    //-------------------- Access Control Invariants-----------------------------------

    // setSignerStatus always revert for non signer manager role
    function invariant_setSignerStatus_only_signerManager_callable() public {
        try controller.setSignerStatus(address(1), true) {
            assertTrue(false);
        } catch {
            assertTrue(true);
        }
    }

    // setPauseStatus always revert non gatekeeper role
    function invariant_setPauseStatus_only_gatekeeper_callable() public {
        try controller.setPauseStatus(IController.ControllerPauseStatus.None) {
            assertTrue(false);
        } catch {
            assertTrue(true);
        }
    }

    // setIsRestricted always revert non restricter
    function invariant_setIsRestricted_only_restricter_callable() public {
        try controller.setIsRestricted(address(1), true) {
            assertTrue(false);
        } catch {
            assertTrue(true);
        }
    }
}
