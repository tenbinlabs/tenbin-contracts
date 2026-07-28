// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseScript} from "./Base.s.sol";
import {console2} from "forge-std/console2.sol";
import {IRestrictedRegistry} from "../src/interface/IRestrictedRegistry.sol";

/// @notice Script to build a batch json safe transaction to restrict or remove the restriction from a set of addresses
/// 1) Ensure CSV_ADDRESSES is set as environment variable.
/// 2) Run the following command including the correct target contract and restricted status`forge script script/BuildSafeBatch.s.sol:BuildSafeBatch --sig "run(address,bool,string,string)" <target_contract_address> <bool_status> $CSV_ADDRESSES <context_string>
contract BuildSafeBatch is BaseScript {
    /// @dev Build Safe json to batch `setIsRestricted` calls for multiple accounts.
    /// The printed json can be uploaded directly to the Safe Transaction Builder UI
    /// @param target The contract that implements setIsRestricted (final call destination)
    /// @param newStatus The restriction status to set for every account
    /// @param accounts Comma-separated list of Ethereum addresses
    /// @param context Description to add context when signers see the transaction
    /// @return txData Calldata to be executed by the Safe
    function run(address target, bool newStatus, string calldata accounts, string calldata context)
        external
        pure
        returns (bytes[] memory txData)
    {
        address[] memory addrs = _parseCsvAddresses(accounts);

        txData = new bytes[](addrs.length);

        console2.log("{");
        console2.log('"version":"1.0",');
        console2.log('"chainId":"1",');
        console2.log(string.concat('"meta":{"name":"Restrict batch for ', context, '"},'));
        console2.log('"transactions":[');

        for (uint256 i; i < addrs.length; ++i) {
            bytes memory callData = abi.encodeCall(IRestrictedRegistry.setIsRestricted, (addrs[i], newStatus));

            txData[i] = callData;

            console2.log("{");
            console2.log(string.concat('"to":"', vm.toString(target), '",'));
            console2.log('"value":"0",');
            console2.log(string.concat('"data":"', vm.toString(callData), '",'));
            console2.log('"operation":0');
            console2.log(i == addrs.length - 1 ? "}" : "},");
        }

        console2.log("]}");
    }

    // Helpers
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
