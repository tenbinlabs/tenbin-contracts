// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "../BaseTest.sol";
import {ControllerHandler} from "../invariant/handlers/ControllerHandler.sol";
import {IController} from "../../src/Controller.sol";

// forge test --mc ControllerInvariantTest -vvvv
contract ControllerInvariantTest is BaseTest {
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
                controller: controller,
                asset: asset,
                collateral: collateral
            })
        );

        initialManagerBalance = collateral.balanceOf(controller.manager());
        initialCustodianBalance = collateral.balanceOf(controller.custodian());

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
        assertTrue(!paused || collateral.totalSupply() == controllerHandler.lastCollateralSupply());
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
        assertLe(collateral.balanceOf(controller.manager()), collAmount);
    }

    // Collateral token `totalSupply` must not change after calling mint or redeem
    function invariant_CollateralSupply() public view {
        assertEq(controllerHandler.lastCollateralSupply(), collateral.totalSupply());
    }

    // Asset token `totalSupply` must decrease after redeeming
    function invariant_AssetDecreasesOnRedeem() public view {
        assertLe(asset.totalSupply(), controllerHandler.totalAssetSupplyMint());
    }

    // Sum of manager and custodian holdings always equals total collateral amount of the order.
    function invariant_CollateralConservation() public view {
        uint256 collAmount = controllerHandler.totalMintCollateral() - controllerHandler.totalRedeemCollateral();
        uint256 managerIncrease = collateral.balanceOf(controller.manager()) - initialManagerBalance;

        uint256 custodianIncrease = collateral.balanceOf(controller.custodian()) - initialCustodianBalance;
        uint256 total = managerIncrease + custodianIncrease;

        assertEq(total, collAmount);
    }
}
