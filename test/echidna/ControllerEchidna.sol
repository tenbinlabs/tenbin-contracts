// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetToken} from "../../src/AssetToken.sol";
import {Controller} from "../../src/Controller.sol";
import {EchidnaBase} from "./EchidnaBase.sol";
import {IController} from "../../src/interface/IController.sol";

// echidna test/echidna/ControllerEchidna.sol --contract ControllerEchidna --config echidna.yaml
contract ControllerEchidna is EchidnaBase {
    uint256 internal constant RATIO_PRECISION = 1e18;
    uint96 internal constant MAX_ORACLE_TOLERANCE = 1e18;

    // Asset token address doesn't change
    function echidna_asset_value() public view returns (bool) {
        return controller.asset() == address(asset);
    }

    // Ratio always less than 1e18 the ratio precision
    function echidna_ratio_bound() public view returns (bool) {
        return controller.ratio() < RATIO_PRECISION;
    }

    // setSignerStatus always revert for non signer manager role
    function echidna_setSignerStatus_only_signerManager_callable() public returns (bool) {
        try controller.setSignerStatus(address(1), true) {
            return false;
        } catch {
            return true;
        }
    }

    // setPauseStatus always revert non gatekeeper role
    function echidna_setPauseStatus_only_gatekeeper_callable() public returns (bool) {
        try controller.setPauseStatus(IController.ControllerPauseStatus.None) {
            return false;
        } catch {
            return true;
        }
    }

    // setIsRestricted always revert non restricter
    function echidna_setIsRestricted_only_restricter_callable() public returns (bool) {
        try controller.setIsRestricted(address(1), true) {
            return false;
        } catch {
            return true;
        }
    }

    // custodian is never zero address
    function echidna_custodian_never_zero_address() public view returns (bool) {
        return controller.custodian() != address(0);
    }

    // manager is never zero address
    function echidna_manager_never_zero_address() public view returns (bool) {
        return controller.manager() != address(0);
    }

    // oracle tolerance always less than MAX_ORACLE_TOLERANCE
    function echidna_oracleTolerance_bound() public view returns (bool) {
        (address adapter, uint96 tolerance) = controller.oracle();
        return adapter == address(0) || tolerance < MAX_ORACLE_TOLERANCE;
    }
}
