// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {CustodianModule} from "src/CustodianModule.sol";
import {EchidnaBase} from "./EchidnaBase.sol";

// echidna test/echidna/CustodianModuleEchidna.sol --contract CustodianModuleEchidna --config echidna.yaml
contract CustodianModuleEchidna is EchidnaBase {
    CustodianModule custodianModule;

    constructor() {
        custodianModule = new CustodianModule(address(this));

        custodianModule.grantRole(ADMIN_ROLE, address(this));
        custodianModule.grantRole(custodianModule.CUSTODIAN_KEEPER_ROLE(), address(this));
    }

    // Custodian is never the zero address
    function echidna_zero_address_never_custodian() public view returns (bool) {
        return !custodianModule.custodians(address(0));
    }
}
