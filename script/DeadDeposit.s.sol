// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseScript} from "./Base.s.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

/// @notice Script to perform a dead deposit
/// 1) update constants to reflect vault, collateral, and dead deposit
/// forge script ./script/DeadDeposit.s.sol --rpc-url {rpc_url_here} --private-key $BROADCASTER_KEY --broadcast
contract DeadDeposit is BaseScript {
    address internal constant VAULT_ADDRESS = 0xEC287F7F1799Ef2D6F6430572515c8D31AD751d3;
    address internal constant COLLATERAL = 0x847DB2D7c07dbA2bE28E9F236B74134d6897BB0A;
    uint256 internal constant DEAD_DEPOSIT_AMOUNT = 1e6;

    /// @notice Execute a mint on sepolia. Must be called using minter key
    function run() public broadcast {
        IERC20(COLLATERAL).approve(VAULT_ADDRESS, DEAD_DEPOSIT_AMOUNT);
        IERC4626(VAULT_ADDRESS).deposit(DEAD_DEPOSIT_AMOUNT, address(0xDEAD));
    }
    // mark this as a test contract
    function test() public {}
}
