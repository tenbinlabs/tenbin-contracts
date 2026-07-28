// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {
    IAssetTokenLike,
    ICollateralManagerLike,
    IControllerLike,
    IStakedAssetLike
} from "../interfaces/IMainnetTargets.sol";
import {MainnetAddresses} from "../MainnetAddresses.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Fuzzes the live tGLD deployment as an unprivileged actor.
///
/// State comes from Echidna's fork mode (`rpcUrl` / `rpcBlock`), not cheatcodes:
/// hevm has no `vm.createSelectFork`, so `setUp` only binds interfaces to the
/// already-fetched mainnet addresses.
///
/// Actions live on this contract rather than a separate handler so the run can
/// use `allContracts: false` -- in fork mode `allContracts: true` would make every
/// fetched mainnet contract a fuzz target.
///
/// Two families of action:
///  - `do*` perform *legitimate* permissionless operations (stake, cooldown,
///    unstake, transfer) and must leave the accounting invariants intact.
///  - `try*` attempt *privileged* operations and must revert with the specific
///    access-control error -- a revert for any other reason fails the test.
contract TGLDPermissionless is Test {
    IAssetTokenLike internal asset;
    IStakedAssetLike internal staked;
    IControllerLike internal controller;
    ICollateralManagerLike internal manager;
    address internal silo;

    /// @dev Fixed unprivileged actor set. Echidna's default senders are used as
    /// callers; these are the accounts the harness funds and tracks.
    address[3] internal actors = [address(0xA11CE), address(0xB0B), address(0xCA401)];

    // ---- ghost accounting ----
    /// @dev Outstanding cooldown assets this harness created, per actor.
    mapping(address => uint256) internal ghostCooldownAssets;
    uint256 internal ghostTotalCooldownAssets;
    /// @dev Highest share price seen, scaled by 1e18. Permissionless ops must never lower it.
    uint256 internal ghostMaxSharePrice;
    /// @dev Silo balance at setUp, before the harness created any cooldowns.
    uint256 internal snapSiloBalance;
    /// @dev Set when a `try*` action observes a privilege-escalation violation.
    /// Echidna's foundry test mode only evaluates `invariant_*` functions -- assertions
    /// raised inside action functions are silently ignored -- so violations must be
    /// recorded here and asserted by invariant_noPrivilegeEscalation().
    string internal violation;

    // ---- config snapshots: no permissionless action may change any of these ----
    address internal snapMinter;
    address internal snapOwner;
    address internal snapController;
    address internal snapSwapModule;
    address internal snapRevenueModule;
    address internal snapCustodian;
    address internal snapManagerAddr;
    uint256 internal snapRatio;
    uint128 internal snapBlockMintLimit;
    uint128 internal snapBlockRedeemLimit;
    uint8 internal snapManagerPauseStatus;
    uint8 internal snapControllerPauseStatus;

    modifier trackSharePrice() {
        _;
        uint256 sharePrice = _sharePrice();
        if (sharePrice > ghostMaxSharePrice) ghostMaxSharePrice = sharePrice;
    }

    function setUp() public virtual {
        asset = IAssetTokenLike(MainnetAddresses.TGLD_ASSET_TOKEN);
        staked = IStakedAssetLike(MainnetAddresses.TGLD_STAKED_ASSET);
        controller = IControllerLike(MainnetAddresses.TGLD_CONTROLLER);
        manager = ICollateralManagerLike(MainnetAddresses.TGLD_COLLATERAL_MANAGER);
        silo = MainnetAddresses.TGLD_SILO;

        snapMinter = asset.minter();
        snapOwner = asset.owner();

        snapController = manager.controller();
        snapSwapModule = manager.swapModule();
        snapRevenueModule = manager.revenueModule();
        snapManagerPauseStatus = manager.pauseStatus();

        snapCustodian = controller.custodian();
        snapManagerAddr = controller.manager();
        snapRatio = controller.ratio();
        snapBlockMintLimit = controller.blockMintLimit();
        snapBlockRedeemLimit = controller.blockRedeemLimit();
        snapControllerPauseStatus = controller.pauseStatus();

        snapSiloBalance = asset.balanceOf(silo);
        ghostMaxSharePrice = _sharePrice();

        // Fund actors so the legitimate actions can actually execute. Amounts are
        // sized against live supply (~258e18 tGLD), not the 1e40 the local handlers
        // use -- at real magnitudes oversized inputs just revert and waste budget.
        for (uint256 i = 0; i < actors.length; i++) {
            _fund(actors[i], 10e18);
        }
    }

    // --------------------------------------------------------------------
    // Legitimate permissionless actions
    // --------------------------------------------------------------------

    function doStake(uint256 actorSeed, uint256 assets) public trackSharePrice {
        address actor = _actor(actorSeed);
        uint256 balance = asset.balanceOf(actor);
        if (balance == 0) return;
        assets = bound(assets, 1, balance);

        vm.startPrank(actor);
        asset.approve(address(staked), assets);
        try staked.deposit(assets, actor) {} catch {}
        vm.stopPrank();
    }

    function doCooldownShares(uint256 actorSeed, uint256 shares) public trackSharePrice {
        address actor = _actor(actorSeed);
        uint256 maxShares = staked.maxRedeem(actor);
        if (maxShares == 0) return;
        shares = bound(shares, 1, maxShares);

        vm.prank(actor);
        try staked.cooldownShares(shares) returns (uint256 assets, uint256) {
            ghostCooldownAssets[actor] += assets;
            ghostTotalCooldownAssets += assets;
        } catch {}
    }

    function doCooldownAssets(uint256 actorSeed, uint256 assets) public trackSharePrice {
        address actor = _actor(actorSeed);
        uint256 maxAssets = staked.maxWithdraw(actor);
        if (maxAssets == 0) return;
        assets = bound(assets, 1, maxAssets);

        vm.prank(actor);
        try staked.cooldownAssets(assets) returns (uint256, uint256) {
            ghostCooldownAssets[actor] += assets;
            ghostTotalCooldownAssets += assets;
        } catch {}
    }

    function doCancelCooldown(uint256 actorSeed, uint256 id) public trackSharePrice {
        address actor = _actor(actorSeed);
        uint256 count = staked.cooldownIds(actor);
        if (count == 0) return;
        id = bound(id, 0, count - 1);
        (uint160 cooldownAssets,) = staked.cooldowns(actor, id);
        if (cooldownAssets == 0) return;

        vm.prank(actor);
        try staked.cancelCooldown(id) {
            ghostCooldownAssets[actor] -= cooldownAssets;
            ghostTotalCooldownAssets -= cooldownAssets;
        } catch {}
    }

    function doUnstake(uint256 actorSeed, uint256 id) public trackSharePrice {
        address actor = _actor(actorSeed);
        uint256 count = staked.cooldownIds(actor);
        if (count == 0) return;
        id = bound(id, 0, count - 1);
        (uint160 cooldownAssets,) = staked.cooldowns(actor, id);
        if (cooldownAssets == 0) return;

        vm.prank(actor);
        try staked.unstake(actor, id) {
            ghostCooldownAssets[actor] -= cooldownAssets;
            ghostTotalCooldownAssets -= cooldownAssets;
        } catch {}
    }

    function doTransferAsset(uint256 fromSeed, uint256 toSeed, uint256 amount) public trackSharePrice {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 balance = asset.balanceOf(from);
        if (balance == 0) return;
        amount = bound(amount, 1, balance);

        vm.prank(from);
        try asset.transfer(to, amount) {} catch {}
    }

    function doTransferStaked(uint256 fromSeed, uint256 toSeed, uint256 amount) public trackSharePrice {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 balance = staked.balanceOf(from);
        if (balance == 0) return;
        amount = bound(amount, 1, balance);

        vm.prank(from);
        try staked.transfer(to, amount) {} catch {}
    }

    function doBurnAsset(uint256 actorSeed, uint256 amount) public trackSharePrice {
        address actor = _actor(actorSeed);
        uint256 balance = asset.balanceOf(actor);
        if (balance == 0) return;
        amount = bound(amount, 1, balance);

        vm.prank(actor);
        try asset.burn(amount) {} catch {}
    }

    function doInvalidateNonce(uint256 actorSeed, uint256 nonce) public trackSharePrice {
        address actor = _actor(actorSeed);
        vm.prank(actor);
        controller.invalidateNonce(nonce);
        if (!controller.nonces(actor, nonce)) _recordViolation("invalidateNonce did not take effect");
    }

    function doRevokeDelegate(uint256 actorSeed, address signer) public trackSharePrice {
        address actor = _actor(actorSeed);
        // Revoking (status=false) is unconditionally permissionless.
        vm.prank(actor);
        controller.setDelegateStatus(signer, false);
        if (controller.delegates(actor, signer)) _recordViolation("delegate not revoked");
    }

    function doWarp(uint256 secondsAhead) public trackSharePrice {
        // Cooldowns are 7 days on-chain; without time travel `unstake` is unreachable.
        vm.warp(block.timestamp + bound(secondsAhead, 1, 10 days));
    }

    // --------------------------------------------------------------------
    // Privileged actions -- must revert with the specific error
    // --------------------------------------------------------------------

    function tryMint(address to, uint256 amount) public trackSharePrice {
        vm.prank(msg.sender);
        try asset.mint(to, amount) {
            _recordViolation("mint: unprivileged call succeeded");
        } catch (bytes memory err) {
            _expectSelector(err, IAssetTokenLike.OnlyMinter.selector, "mint");
        }
    }

    function trySetMinter(address newMinter) public trackSharePrice {
        vm.prank(msg.sender);
        try asset.setMinter(newMinter) {
            _recordViolation("setMinter: unprivileged call succeeded");
        } catch (bytes memory err) {
            _expectSelector(err, Ownable.OwnableUnauthorizedAccount.selector, "setMinter");
        }
    }

    function trySetRebalanceCap(address collateral, uint256 amount) public trackSharePrice {
        vm.prank(msg.sender);
        try manager.setRebalanceCap(collateral, amount) {
            _recordViolation("setRebalanceCap: unprivileged call succeeded");
        } catch (bytes memory err) {
            _expectAccessControl(err, "setRebalanceCap");
        }
    }

    function trySetSwapCap(address collateral, uint256 amount) public trackSharePrice {
        vm.prank(msg.sender);
        try manager.setSwapCap(collateral, amount) {
            _recordViolation("setSwapCap: unprivileged call succeeded");
        } catch (bytes memory err) {
            _expectAccessControl(err, "setSwapCap");
        }
    }

    /// @dev `withdraw` is the one privileged target whose modifier order is
    /// `nonReentrant notPaused onlyRole(CURATOR_ROLE)` -- during an FML pause the
    /// access-control error is unreachable, so both selectors are accepted.
    function tryManagerWithdraw(address collateral, uint256 amount, uint256 maxShares) public trackSharePrice {
        vm.prank(msg.sender);
        try manager.withdraw(collateral, amount, maxShares) {
            _recordViolation("withdraw: unprivileged call succeeded");
        } catch (bytes memory err) {
            _expectOneOf(
                err,
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                ICollateralManagerLike.FMLPause.selector,
                "withdraw"
            );
        }
    }

    function tryRescueToken(address token, address to) public trackSharePrice {
        vm.prank(msg.sender);
        try manager.rescueToken(token, to) {
            _recordViolation("rescueToken: unprivileged call succeeded");
        } catch (bytes memory err) {
            _expectAccessControl(err, "rescueToken");
        }
    }

    function trySetIsRestricted(address account, bool status) public trackSharePrice {
        vm.prank(msg.sender);
        try controller.setIsRestricted(account, status) {
            _recordViolation("setIsRestricted: unprivileged call succeeded");
        } catch (bytes memory err) {
            _expectAccessControl(err, "setIsRestricted");
        }
    }

    function trySetRatio(uint256 newRatio) public trackSharePrice {
        vm.prank(msg.sender);
        try controller.setRatio(newRatio) {
            _recordViolation("setRatio: unprivileged call succeeded");
        } catch (bytes memory err) {
            _expectAccessControl(err, "setRatio");
        }
    }

    function trySetOracleAdapter(address adapter) public trackSharePrice {
        vm.prank(msg.sender);
        try controller.setOracleAdapter(adapter) {
            _recordViolation("setOracleAdapter: unprivileged call succeeded");
        } catch (bytes memory err) {
            _expectAccessControl(err, "setOracleAdapter");
        }
    }

    function trySetCustodian(address custodian) public trackSharePrice {
        vm.prank(msg.sender);
        try controller.setCustodian(custodian) {
            _recordViolation("setCustodian: unprivileged call succeeded");
        } catch (bytes memory err) {
            _expectAccessControl(err, "setCustodian");
        }
    }

    // --------------------------------------------------------------------
    // Invariants
    // --------------------------------------------------------------------

    /// @notice Guard: the fuzz senders must never hold a privileged role, or every
    /// access-control invariant above would pass vacuously.
    function invariant_sendersAreUnprivileged() public view {
        address[] memory admins = MainnetAddresses.tGLD_defaultAdminRole();
        for (uint256 i = 0; i < admins.length; i++) {
            assertNotEq(msg.sender, admins[i]);
        }
        assertNotEq(msg.sender, snapOwner);
        assertNotEq(msg.sender, snapMinter);
    }

    /// @notice The silo must always hold at least the assets owed to outstanding cooldowns.
    /// @notice No `try*` action may ever have succeeded or reverted for the wrong reason.
    function invariant_noPrivilegeEscalation() public view {
        assertEq(bytes(violation).length, 0, violation);
    }

    function invariant_siloSolvency() public view {
        assertGe(asset.balanceOf(silo), snapSiloBalance + ghostTotalCooldownAssets);
    }

    /// @notice Ghost per-actor cooldown accounting must match the contract's own.
    function invariant_cooldownAccounting() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            address actor = actors[i];
            uint256 onChain;
            uint256 count = staked.cooldownIds(actor);
            for (uint256 id = 0; id < count; id++) {
                (uint160 assets,) = staked.cooldowns(actor, id);
                onChain += assets;
            }
            assertEq(onChain, ghostCooldownAssets[actor]);
        }
    }

    /// @notice No permissionless operation may reduce the share price.
    function invariant_sharePriceNonDecreasing() public view {
        assertGe(_sharePrice(), ghostMaxSharePrice);
    }

    function invariant_assetTokenConfigUnchanged() public view {
        assertEq(asset.minter(), snapMinter);
        assertEq(asset.owner(), snapOwner);
    }

    function invariant_managerConfigUnchanged() public view {
        assertEq(manager.controller(), snapController);
        assertEq(manager.swapModule(), snapSwapModule);
        assertEq(manager.revenueModule(), snapRevenueModule);
        assertEq(uint256(manager.pauseStatus()), uint256(snapManagerPauseStatus));
    }

    function invariant_controllerConfigUnchanged() public view {
        assertEq(controller.custodian(), snapCustodian);
        assertEq(controller.manager(), snapManagerAddr);
        assertEq(controller.ratio(), snapRatio);
        assertEq(uint256(controller.blockMintLimit()), uint256(snapBlockMintLimit));
        assertEq(uint256(controller.blockRedeemLimit()), uint256(snapBlockRedeemLimit));
        assertEq(uint256(controller.pauseStatus()), uint256(snapControllerPauseStatus));
    }

    // --------------------------------------------------------------------
    // Helpers
    // --------------------------------------------------------------------

    /// @dev AssetToken storage layout, verified against mainnet: OZ v5 non-upgradeable
    /// ERC20 puts `_balances` at slot 0 and `_totalSupply` at slot 2.
    uint256 internal constant ERC20_BALANCES_SLOT = 0;
    uint256 internal constant ERC20_TOTAL_SUPPLY_SLOT = 2;

    /// @dev forge-std `deal` is unusable here: it goes through `stdstore`, which
    /// calls `vm.record()`, and hevm rejects that cheatcode. Write the slots
    /// directly instead, adjusting totalSupply so the token stays self-consistent,
    /// and assert the result so a layout change fails loudly rather than silently
    /// leaving actors unfunded (which would make every action a no-op).
    function _fund(address account, uint256 amount) internal {
        uint256 current = asset.balanceOf(account);
        bytes32 slot = keccak256(abi.encode(account, ERC20_BALANCES_SLOT));
        vm.store(address(asset), slot, bytes32(amount));

        uint256 supply = uint256(vm.load(address(asset), bytes32(ERC20_TOTAL_SUPPLY_SLOT)));
        vm.store(address(asset), bytes32(ERC20_TOTAL_SUPPLY_SLOT), bytes32(supply + amount - current));

        assertEq(asset.balanceOf(account), amount, "funding failed: ERC20 balances slot moved");
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    /// @dev Assets per 1e18 shares. Constant when supply is zero.
    function _sharePrice() internal view returns (uint256) {
        uint256 supply = staked.totalSupply();
        if (supply == 0) return 1e18;
        return (staked.totalAssets() * 1e18) / supply;
    }

    function _recordViolation(string memory reason) internal {
        if (bytes(violation).length == 0) violation = reason;
    }

    /// @dev A privileged call must revert with its specific access-control error.
    /// Reverting for any other reason means the access check was never reached, so
    /// the test would otherwise pass vacuously.
    function _expectSelector(bytes memory err, bytes4 expected, string memory what) internal {
        _expectOneOf(err, expected, expected, what);
    }

    /// @dev As `_expectSelector`, but for a target whose access check can be preempted by
    /// another modifier -- either selector is acceptable.
    function _expectOneOf(bytes memory err, bytes4 expectedA, bytes4 expectedB, string memory what) internal {
        if (err.length < 4) {
            _recordViolation(string.concat(what, ": empty revert, expected typed error"));
            return;
        }
        bytes4 got = bytes4(err);
        if (got != expectedA && got != expectedB) {
            _recordViolation(string.concat(what, ": wrong revert selector"));
        }
    }

    function _expectAccessControl(bytes memory err, string memory what) internal {
        _expectSelector(err, IAccessControl.AccessControlUnauthorizedAccount.selector, what);
    }
}
