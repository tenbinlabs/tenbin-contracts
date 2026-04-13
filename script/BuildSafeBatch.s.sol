// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseScript} from "./Base.s.sol";
import {console2} from "forge-std/console2.sol";
import {IRestrictedRegistry} from "../src/interface/IRestrictedRegistry.sol";

/// @notice Script to build a batch safe transaction to restrict or remove the restriction from a set of addresses
/// 1) Ensure CSV_ADDRESSES is set as environment variable.
/// 2) Run the following command including the correct target contract and restricted status`forge script script/BuildSafeBatch.s.sol:BuildSafeBatch --sig "run(address,bool,string)" <target_contract_address> <bool_status> $CSV_ADDRESSES `
contract BuildSafeBatch is BaseScript {
    // MultiSendCallOnly ABI: function multiSend(bytes transactions)
    bytes4 constant MULTISEND_SELECTOR = bytes4(keccak256("multiSend(bytes)"));

    /// @dev Build Safe MultiSend calldata to batch `setIsRestricted` calls for multiple accounts
    /// @param target The contract that implements setIsRestricted (final call destination)
    /// @param newStatus The restriction status to set for every account
    /// @param accounts Comma-separated list of Ethereum addresses
    /// @return safeData Calldata to be executed by the Safe against MultiSendCallOnly
    function run(address target, bool newStatus, string calldata accounts)
        external
        pure
        returns (bytes memory safeData)
    {
        // Provide addresses as comma-separated string in env
        address[] memory addrs = _parseCsvAddresses(accounts);

        // Build packed transactions
        bytes memory packed;
        for (uint256 i = 0; i < addrs.length; i++) {
            bytes memory callData = abi.encodeCall(IRestrictedRegistry.setIsRestricted, (addrs[i], newStatus));
            packed = bytes.concat(packed, _packOne(target, 0, callData));
        }

        // calldata that Safe must execute (to MultiSendCallOnly)
        safeData = abi.encodeWithSelector(MULTISEND_SELECTOR, packed);

        console2.log("\n\n=== SAFE TX FIELDS ===");
        console2.log("to (MultiSendCallOnly): 0x9641d764fc13c8B624c04430C7356C1C7C8102e2");
        console2.log("value:", uint256(0));
        console2.log("operation:", uint256(1), "(DELEGATECALL)");
        console2.logBytes(safeData);
        console2.log("data (hex above) length:", safeData.length);
    }

    // Helpers

    /// @dev Safe MultiSend encoding:
    /// transactions = concat of:
    ///   operation (1 byte) 0=CALL, 1=DELEGATECALL
    ///   to        (20 bytes)
    ///   value     (32 bytes)
    ///   dataLen   (32 bytes)
    ///   data      (dataLen bytes)
    function _packOne(address to, uint256 value, bytes memory data) internal pure returns (bytes memory) {
        // operation inside multisend should be CALL (0) so that when this code runs in Safe context,
        // each inner call is a CALL from the Safe to the target contract.
        uint8 op = 0;

        return abi.encodePacked(bytes1(op), bytes20(to), bytes32(value), bytes32(uint256(data.length)), data);
    }

    /// @dev Parse a csv string to an array of addresses
    /// @param s containing a csv with the addresses
    /// @return array of addresses
    function _parseCsvAddresses(string memory s) internal pure returns (address[] memory) {
        bytes memory b = bytes(s);
        // Count commas to size array
        uint256 count = 1;
        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] == ",") count++;
        }

        address[] memory out = new address[](count);

        uint256 idx = 0;
        uint256 start = 0;
        for (uint256 i = 0; i <= b.length; i++) {
            if (i == b.length || b[i] == ",") {
                out[idx++] = _parseAddress(slice(b, start, i - start));
                start = i + 1;
            }
        }
        return out;
    }

    /// @dev Return a slice of bytes as a string
    /// @param b Bytes value to slice
    /// @param start start index
    /// @param len length of slice
    /// @return new slice as string
    function slice(bytes memory b, uint256 start, uint256 len) internal pure returns (string memory) {
        bytes memory out = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            out[i] = b[start + i];
        }
        return string(out);
    }

    /// @dev Parse a hexadecimal Ethereum address string into an address
    /// @param a The address string to parse (e.g. "0x1234...")
    /// @return The parsed address
    function _parseAddress(string memory a) internal pure returns (address) {
        bytes memory tmp = bytes(_trim(a));
        require(tmp.length == 42, "bad addr");
        uint160 acc = 0;
        for (uint256 i = 2; i < 42; i++) {
            acc <<= 4;
            uint8 c = uint8(tmp[i]);
            if (c >= 48 && c <= 57) acc |= uint160(c - 48);
            else if (c >= 65 && c <= 70) acc |= uint160(c - 55);
            else if (c >= 97 && c <= 102) acc |= uint160(c - 87);
            else revert("bad hex");
        }
        return address(acc);
    }

    /// @dev Trim leading and trailing ASCII whitespace from a string
    /// @param str string to be trimmed
    /// @return New string without whitespaces
    function _trim(string memory str) internal pure returns (string memory) {
        bytes memory b = bytes(str);
        uint256 start = 0;
        while (start < b.length && (b[start] == 0x20 || b[start] == 0x09)) start++;
        uint256 end = b.length;
        while (end > start && (b[end - 1] == 0x20 || b[end - 1] == 0x09)) end--;
        bytes memory out = new bytes(end - start);
        for (uint256 i = 0; i < out.length; i++) {
            out[i] = b[start + i];
        }
        return string(out);
    }
}
