// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {MorphoVaultV1AdapterFactory} from "vault-v2/src/adapters/MorphoVaultV1AdapterFactory.sol";
import {Script} from "forge-std/Script.sol";

/// @notice Script to deploy MorphoVaultV1AdapterFactory factory
/// Only needs to be run one time per testnet to support deployment of mock morpho v2 vaults
/// forge script ./script/DeployFactory.s.sol --rpc-url $SEPOLIA_RPC_URL --private-key $BROADCASTER_KEY --verify --verifier etherscan --broadcast
contract DeployFactory is Script {
    /// @notice Execute a mint on sepolia. Must be called using minter key
    /// @notice Set broadcaster. Can be specified via $EOA or $MNEMONIC, otherwise uses test mnemonic
    function run() public {
        vm.startBroadcast();
        MorphoVaultV1AdapterFactory factory = new MorphoVaultV1AdapterFactory();
        vm.stopBroadcast();
        console2.log("factory: ", address(factory));
    }
    // mark this as a test contract
    function test() public {}
}
