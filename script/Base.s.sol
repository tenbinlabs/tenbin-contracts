// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "lib/forge-std/src/console2.sol";
import {Script} from "lib/forge-std/src/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @notice Base script from which other scripts inherit
contract BaseScript is Script {
    using Strings for uint256;

    /// @dev Included to enable compilation of the script without a $MNEMONIC environment variable.
    string internal constant TEST_MNEMONIC = "ten ten ten ten ten ten ten ten ten ten ten test";

    /// @dev The salt used for deterministic deployments.
    bytes32 internal immutable SALT;

    /// @notice Account which will broadcast the transaction
    address internal broadcaster;

    /// @dev Used to derive the broadcaster's address if $EOA is not defined.
    string internal mnemonic;

    /// @notice Set broadcaster. Can be specified via $EOA or $MNEMONIC, otherwise uses test mnemonic
    constructor() {
        console2.log("running script...");
        address from = vm.envOr({name: "BROADCASTER_ADDRESS", defaultValue: address(0)});
        if (from != address(0)) {
            broadcaster = from;
        } else {
            mnemonic = vm.envOr({name: "MNEMONIC", defaultValue: TEST_MNEMONIC});
            (broadcaster,) = deriveRememberKey({mnemonic: mnemonic, index: 0});
        }

        // Construct the salt for deterministic deployments.
        SALT = constructCreate2Salt();
    }

    /// @notice Broadcast transaction
    modifier broadcast() {
        vm.startBroadcast(broadcaster);
        _;
        vm.stopBroadcast();
    }

    /// @dev The presence of the salt instructs Forge to deploy contracts via this deterministic CREATE2 factory:
    /// https://github.com/Arachnid/deterministic-deployment-proxy
    ///
    /// Notes:
    /// - The salt format is "ChainID <chainid>, Version <version>".
    function constructCreate2Salt() public view returns (bytes32) {
        string memory chainId = block.chainid.toString();
        string memory version = getVersion();
        string memory create2Salt = string.concat("ChainID ", chainId, ", Version ", version);
        console2.log("The CREATE2 salt is \"%s\"", create2Salt);
        return bytes32(abi.encodePacked(create2Salt));
    }

    /// @dev The version for this deployment
    function getVersion() internal pure returns (string memory) {
        return "1.1.0";
    }

    // mark this as a test contract
    function test_base() public {}
}
