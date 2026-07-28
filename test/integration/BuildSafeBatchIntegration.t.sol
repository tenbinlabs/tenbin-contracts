// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "../BaseTest.sol";
import {BuildSafeBatchHarness} from "../harness/BuildSafeBatchHarness.sol";
import {SafeMock} from "../mocks/SafeMock.sol";

contract BuildSafeBatchHarnessIntegration is BaseTest {
    SafeMock safe;
    BuildSafeBatchHarness builder;

    function setUp() public override {
        super.setUp();
        // Deploy Safe + script
        safe = new SafeMock();
        builder = new BuildSafeBatchHarness();
    }

    function test_RunBuildSafeBatchHarness_Addresses_RestrictsAll() external {
        // Set safe as RESTRICTER
        vm.prank(owner);
        controller.grantRole(RESTRICTER_ROLE, address(safe));

        // 1) Create 80 addresses + CSV string and set env ADDRS
        address[] memory addrs = new address[](10);
        string memory csv;

        for (uint256 i = 0; i < 10; i++) {
            address a = makeAddr(string.concat("user", vm.toString(i)));
            addrs[i] = a;
            csv = (i == 0) ? vm.toString(a) : string.concat(csv, ",", vm.toString(a));
        }

        // 2) Run script builder to get safeData
        bytes[] memory safeData = builder.run(address(controller), true, csv, "");

        // 3) Execute the Safe tx
        for (uint256 i = 0; i < addrs.length; i++) {
            (bool ok,) = safe.exec(address(controller), 0, safeData[i], 0);
            assertTrue(ok);
        }

        // 4) Assert all addresses are restricted
        for (uint256 i = 0; i < addrs.length; i++) {
            assertTrue(controller.isRestricted(addrs[i]));
        }
    }

    function test_Revert_ParseAddressOnLength() external {
        vm.expectRevert("bad addr");
        builder.exposedParseAddress("0x1234");
    }

    function test_Revert_ParseAddressOnInvalidHex() external {
        vm.expectRevert("bad hex");
        builder.exposedParseAddress("0x123456789012345678901234567890123456789g");
    }

    function test_parseAddressParsesNumeric() external view {
        assertEq(
            builder.exposedParseAddress("0x1234567890123456789012345678901234567890"),
            0x1234567890123456789012345678901234567890
        );
    }

    function test_parseAddressParsesUppercas() external view {
        assertEq(
            builder.exposedParseAddress("0xABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD"),
            0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD
        );
    }

    function test_parseAddressParsesLowercase() external view {
        assertEq(
            builder.exposedParseAddress("0xabcdefabcdefabcdefabcdefabcdefabcdefabcd"),
            0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD
        );
    }
}
