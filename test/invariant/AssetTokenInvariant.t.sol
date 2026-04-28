// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetTokenHandler} from "./handlers/AssetTokenHandler.sol";
import {InvariantBase} from "./InvariantBase.sol";

// echidna: echidna test/invariant/AssetTokenInvariant.t.sol --contract AssetTokenInvariantTest --config echidna.yaml
// foundry: forge test --mc AssetTokenInvariantsTest -vvvv
contract AssetTokenInvariantTest is InvariantBase {
    AssetTokenHandler tokenHandler;

    function setUp() public virtual override {
        super.setUp();
        tokenHandler = new AssetTokenHandler(asset, minter);
        targetContract(address(tokenHandler));
    }

    // Total supply equals sum of all balances
    function invariant_totalSupplyConsistency() public view {
        assertEq(asset.totalSupply(), tokenHandler.getHoldersBalances());
    }

    // Owner can never be `address(0)`
    function invariant_OwnerValidAddress() public view {
        assertNotEq(asset.owner(), address(0));
    }

    // Minting increases both total supply and recipient balance by `amount`
    // Burning always decreases both total supply and burner balance by `amount`
    function invariant_MintBurnSymmetric() public view {
        assertEq(tokenHandler.getHoldersBalances(), tokenHandler.totalMinted() - tokenHandler.totalBurned());
    }

    // Permit and transferFrom preserve total supply
    function invariant_totalSupplyPersistence() public view {
        assertEq(tokenHandler.totalBeforeTransfer(), tokenHandler.totalAfterTransfer());
    }

    //-------------------- Access Control Invariants-----------------------------------

    // setMinter always revert when caller is not authorized
    function invariant_setMinter_only_owner_callable() public {
        try asset.setMinter(address(1)) {
            assertTrue(false);
        } catch {
            assertTrue(true);
        }
    }
}
