// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ForkBaseTest} from "./ForkBaseTest.sol";
import {BuildSafeBatch} from "../../script/BuildSafeBatch.s.sol";
import {Controller} from "../../src/Controller.sol";
import {SafeMock} from "../mocks/SafeMock.sol";

contract BuildSafeBatchFork is ForkBaseTest {
    address controllerAddress = 0x5e631388b24ec493619DAEEAef6fc34B33d97Dcd; //tGLD controller
    BuildSafeBatch builder;
    SafeMock safe;

    function setUp() public override {
        super.setUp();
        restricter = 0xE6Eb534f33A635e8d867414Af32F766D221F30d1; // admin multisig
        builder = new BuildSafeBatch();
        safe = new SafeMock();
    }

    function test_Execute_RestrictBatch() public {
        // 1) Create 10 addresses + CSV string and set env ADDRS
        address[] memory addrs = new address[](10);
        string memory csv;

        for (uint256 i = 0; i < addrs.length; i++) {
            address a = makeAddr(string.concat("user", vm.toString(i)));
            addrs[i] = a;
            csv = (i == 0) ? vm.toString(a) : string.concat(csv, ",", vm.toString(a));
        }

        // 2) Run script builder to get safeData
        bytes[] memory safeData = builder.run(controllerAddress, true, csv, "");

        // 3) Execute the Safe tx
        // Replaced the Safe/multisig code with mock code to avoid needing the extra signatures
        vm.etch(restricter, address(safe).code);
        vm.startPrank(restricter);
        for (uint256 i = 0; i < addrs.length; i++) {
            (bool ok,) = SafeMock(restricter).exec(controllerAddress, 0, safeData[i], 0);
            assertTrue(ok);
        }

        // 4) Assert all addresses are restricted
        for (uint256 i = 0; i < addrs.length; i++) {
            assertTrue(Controller(controllerAddress).isRestricted(addrs[i]));
        }
    }
}
