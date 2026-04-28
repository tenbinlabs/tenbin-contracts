// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {CustodianHandler} from "./handlers/CustodianHandler.sol";
import {InvariantBase} from "./InvariantBase.sol";

// echidna: echidna test/invariant/CustodianInvariant.t.sol --contract CustodianModuleInvariantTest --config echidna.yaml
// foundry: forge test --mc CustodianModuleInvariantTest -vvvv
contract CustodianModuleInvariantTest is InvariantBase {
    CustodianHandler custodianHandler;

    function setUp() public virtual override {
        super.setUp();
        custodianHandler = new CustodianHandler(custodianModule, owner, custodianKeeper);
        targetContract(address(custodianHandler));
    }

    // Custodian is never the zero address
    function invariant_zero_address_never_custodian() public view returns (bool) {
        return !custodianModule.custodians(address(0));
    }
}
