// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IOracleAdapter} from "../../src/interface/IOracleAdapter.sol";

/// @title Mock oracle adapter with a directly settable price
/// @notice Stands in for the per-asset Chainlink adapters wherever there is no Chainlink feed.
///
/// The real adapters (`GoldOracleAdapter`, `BRLOracleAdapter`, `MXNOracleAdapter`) each hardcode a
/// mainnet aggregator address as a `constant`, so on a fresh Anvil they read a non-contract and
/// `getPrice` reverts on every call. The deploy script's answer was to leave `oracle_adapter` at
/// the zero address under `useMockIntegrations`, which made the engine report a chain-state price
/// of zero for every local and e2e run (ENG-2664).
///
/// Settable rather than fixed so a scenario can move the price and assert what the engine does
/// with it; `MockAggregator` is not reused because the adapters wrap a *constant* feed address,
/// leaving nothing to point at a mock.
contract MockOracleAdapter is IOracleAdapter {
    /// @notice Price with 18 decimals, as `IOracleAdapter` requires.
    uint256 private price_;

    /// @inheritdoc IOracleAdapter
    /// @dev Zero: there is no underlying feed. The real adapters return their Chainlink
    /// aggregator; nothing reads this off a mock beyond the deploy-time `oracle()` sanity check,
    /// which is skipped on the mock branch.
    address public constant oracle = address(0);

    /// @param initialPrice Price with 18 decimals. Must be non-zero — a mock that starts at zero
    /// reproduces the exact defect this contract exists to remove.
    constructor(uint256 initialPrice) {
        if (initialPrice == 0) revert InvalidOraclePrice();
        price_ = initialPrice;
    }

    /// @inheritdoc IOracleAdapter
    function getPrice() external view returns (uint256) {
        return price_;
    }

    /// @notice Moves the price. Test-only, and deliberately without access control.
    ///
    /// The guard that matters is narrower than "nobody can reach this": `Deploy.s.sol` refuses
    /// mocks on **mainnet only** (`block.chainid == 1`), and a mock deploy to sepolia is an
    /// intended path — it is the documented dev deploy (`contracts/README.md`). So an unguarded
    /// `setPrice` can and does sit on a public testnet.
    ///
    /// That is acceptable rather than overlooked. Under `useMockIntegrations` the controller is
    /// never armed with this adapter (`setOracleAdapter` is skipped), so `verifyOrder`'s
    /// price-delta check stays dormant and moving the price changes nothing an order depends on —
    /// only the chain-state figure the engine records, which is write-only. Arming the controller
    /// with a mock adapter on a shared chain is what would need access control here.
    /// @param newPrice Price with 18 decimals, non-zero.
    function setPrice(uint256 newPrice) external {
        if (newPrice == 0) revert InvalidOraclePrice();
        price_ = newPrice;
    }
}
