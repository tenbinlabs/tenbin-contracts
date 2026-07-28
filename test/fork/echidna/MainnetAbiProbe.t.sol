// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ForkBaseTest} from "../ForkBaseTest.sol";
import {MainnetAddresses} from "../../echidna/mainnet/MainnetAddresses.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/// @notice Guards the mainnet Echidna harnesses against deployed-ABI drift.
///
/// The harnesses bind narrow interfaces (test/echidna/mainnet/interfaces/IMainnetTargets.sol)
/// to live addresses. If a redeploy removes a member -- or someone adds a selector
/// to those interfaces that the deployed bytecode does not implement -- the Echidna
/// run dies mid-campaign with an opaque "Calling the setUp() function failed".
///
/// This runs in normal fork CI (where vm.parseJson etc. are available) and fails
/// with the exact missing selector instead.
///
/// Live tGLD is v1.4.0 while tBRL/tMXN are v1.4.3, so the asset ABIs are NOT
/// identical -- notably CollateralManager.distributor() exists only on the newer
/// deployments and is deliberately absent from the probe below.
contract MainnetAbiProbeTest is ForkBaseTest {
    bytes4 internal constant FML_PAUSE = bytes4(keccak256("FMLPause()"));
    bytes4 internal constant INVALID_COOLDOWN_AMOUNT = bytes4(keccak256("InvalidCooldownAmount()"));
    bytes4 internal constant NONEXISTENT_COOLDOWN = bytes4(keccak256("NonexistentCooldown()"));
    bytes4 internal constant ONLY_MINTER = bytes4(keccak256("OnlyMinter()"));
    bytes4 internal constant REQUIRES_COOLDOWN = bytes4(keccak256("RequiresCooldown()"));
    bytes4 internal constant ZERO_COOLDOWN_ASSETS = bytes4(keccak256("ZeroCooldownAssets()"));

    function setUp() public override {
        super.setUp();
    }

    function test_fork_assetTokenSelectorsExist() public view {
        address token = MainnetAddresses.TGLD_ASSET_TOKEN;
        _probeView(token, abi.encodeWithSignature("minter()"), 32, "minter()");
        _probeView(token, abi.encodeWithSignature("owner()"), 32, "owner()");
        _probeView(token, abi.encodeWithSignature("totalSupply()"), 32, "totalSupply()");
        _probeView(token, abi.encodeWithSignature("balanceOf(address)", address(this)), 32, "balanceOf(address)");
        _probeView(
            token,
            abi.encodeWithSignature("allowance(address,address)", address(this), address(this)),
            32,
            "allowance()"
        );
    }

    function test_fork_assetTokenMutatingSelectorsExist() public {
        address token = MainnetAddresses.TGLD_ASSET_TOKEN;
        _probeCall(token, abi.encodeWithSignature("transfer(address,uint256)", address(this), 0), 32, "transfer()");
        _probeCall(token, abi.encodeWithSignature("approve(address,uint256)", address(this), 0), 32, "approve()");
        _probeCall(token, abi.encodeWithSignature("burn(uint256)", 0), 0, "burn()");
        _probeRevert(token, abi.encodeWithSignature("mint(address,uint256)", address(this), 0), ONLY_MINTER, "mint()");
        _probeRevert(
            token,
            abi.encodeWithSignature("setMinter(address)", address(this)),
            Ownable.OwnableUnauthorizedAccount.selector,
            "setMinter()"
        );
    }

    function test_fork_stakedAssetSelectorsExist() public view {
        address s = MainnetAddresses.TGLD_STAKED_ASSET;
        _probeView(s, abi.encodeWithSignature("asset()"), 32, "asset()");
        _probeView(s, abi.encodeWithSignature("silo()"), 32, "silo()");
        _probeView(s, abi.encodeWithSignature("totalSupply()"), 32, "totalSupply()");
        _probeView(s, abi.encodeWithSignature("totalAssets()"), 32, "totalAssets()");
        _probeView(s, abi.encodeWithSignature("balanceOf(address)", address(this)), 32, "balanceOf(address)");
        _probeView(s, abi.encodeWithSignature("cooldownPeriod()"), 32, "cooldownPeriod()");
        _probeView(s, abi.encodeWithSignature("cooldownIds(address)", address(this)), 32, "cooldownIds(address)");
        _probeView(s, abi.encodeWithSignature("cooldowns(address,uint256)", address(this), 0), 64, "cooldowns()");
        _probeView(s, abi.encodeWithSignature("previewRedeem(uint256)", 1e18), 32, "previewRedeem(uint256)");
        _probeView(s, abi.encodeWithSignature("maxRedeem(address)", address(this)), 32, "maxRedeem(address)");
        _probeView(s, abi.encodeWithSignature("maxWithdraw(address)", address(this)), 32, "maxWithdraw(address)");
    }

    function test_fork_stakedAssetMutatingSelectorsExist() public {
        address s = MainnetAddresses.TGLD_STAKED_ASSET;
        _probeCall(s, abi.encodeWithSignature("deposit(uint256,address)", 0, address(this)), 32, "deposit()");
        _probeRevert(
            s,
            abi.encodeWithSignature("redeem(uint256,address,address)", 0, address(this), address(this)),
            REQUIRES_COOLDOWN,
            "redeem()"
        );
        _probeCall(s, abi.encodeWithSignature("transfer(address,uint256)", address(this), 0), 32, "transfer()");
        _probeRevert(
            s, abi.encodeWithSignature("cooldownShares(uint256)", 0), INVALID_COOLDOWN_AMOUNT, "cooldownShares()"
        );
        _probeRevert(
            s, abi.encodeWithSignature("cooldownAssets(uint256)", 0), INVALID_COOLDOWN_AMOUNT, "cooldownAssets()"
        );
        _probeRevert(s, abi.encodeWithSignature("cancelCooldown(uint256)", 0), NONEXISTENT_COOLDOWN, "cancelCooldown()");
        _probeRevert(
            s, abi.encodeWithSignature("unstake(address,uint256)", address(this), 0), ZERO_COOLDOWN_ASSETS, "unstake()"
        );
    }

    function test_fork_controllerSelectorsExist() public view {
        address c = MainnetAddresses.TGLD_CONTROLLER;
        _probeView(c, abi.encodeWithSignature("pauseStatus()"), 32, "pauseStatus()");
        _probeView(c, abi.encodeWithSignature("custodian()"), 32, "custodian()");
        _probeView(c, abi.encodeWithSignature("manager()"), 32, "manager()");
        _probeView(c, abi.encodeWithSignature("ratio()"), 32, "ratio()");
        _probeView(c, abi.encodeWithSignature("blockMintLimit()"), 32, "blockMintLimit()");
        _probeView(c, abi.encodeWithSignature("blockRedeemLimit()"), 32, "blockRedeemLimit()");
        _probeView(
            c, abi.encodeWithSignature("delegates(address,address)", address(this), address(this)), 32, "delegates()"
        );
        _probeView(c, abi.encodeWithSignature("nonces(address,uint256)", address(this), 0), 32, "nonces()");
    }

    function test_fork_controllerMutatingSelectorsExist() public {
        address c = MainnetAddresses.TGLD_CONTROLLER;
        _probeCall(c, abi.encodeWithSignature("invalidateNonce(uint256)", 0), 0, "invalidateNonce()");
        _probeCall(
            c,
            abi.encodeWithSignature("setDelegateStatus(address,bool)", address(this), false),
            0,
            "setDelegateStatus()"
        );
        _probeAccessControlRevert(
            c, abi.encodeWithSignature("setIsRestricted(address,bool)", address(this), false), "setIsRestricted()"
        );
        _probeAccessControlRevert(c, abi.encodeWithSignature("setRatio(uint256)", 0), "setRatio()");
        _probeAccessControlRevert(
            c, abi.encodeWithSignature("setOracleAdapter(address)", address(0)), "setOracleAdapter()"
        );
        _probeAccessControlRevert(c, abi.encodeWithSignature("setCustodian(address)", address(this)), "setCustodian()");
        _probeAccessControlRevert(c, abi.encodeWithSignature("setBlockMintLimit(uint128)", 0), "setBlockMintLimit()");
    }

    function test_fork_collateralManagerSelectorsExist() public view {
        address m = MainnetAddresses.TGLD_COLLATERAL_MANAGER;
        _probeView(m, abi.encodeWithSignature("controller()"), 32, "controller()");
        _probeView(m, abi.encodeWithSignature("swapModule()"), 32, "swapModule()");
        _probeView(m, abi.encodeWithSignature("revenueModule()"), 32, "revenueModule()");
        _probeView(m, abi.encodeWithSignature("pauseStatus()"), 32, "pauseStatus()");
    }

    function test_fork_collateralManagerMutatingSelectorsExist() public {
        address m = MainnetAddresses.TGLD_COLLATERAL_MANAGER;
        _probeAccessControlRevert(
            m,
            abi.encodeWithSignature("addCollateral(address,address)", address(this), address(this)),
            "addCollateral()"
        );
        _probeAccessControlRevert(
            m, abi.encodeWithSignature("removeCollateral(address)", address(this)), "removeCollateral()"
        );
        _probeAccessControlRevert(
            m, abi.encodeWithSignature("setRebalanceCap(address,uint256)", address(this), 0), "setRebalanceCap()"
        );
        _probeAccessControlRevert(
            m, abi.encodeWithSignature("setSwapCap(address,uint256)", address(this), 0), "setSwapCap()"
        );
        // `withdraw` is modified `nonReentrant notPaused onlyRole(CURATOR_ROLE)` -- during an
        // FML pause the access-control error is unreachable, so both selectors are accepted.
        _probeRevertOneOf(
            m,
            abi.encodeWithSignature("withdraw(address,uint256,uint256)", address(this), 0, 0),
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            FML_PAUSE,
            "withdraw()"
        );
        _probeAccessControlRevert(
            m, abi.encodeWithSignature("rescueToken(address,address)", address(this), address(this)), "rescueToken()"
        );
        _probeAccessControlRevert(m, abi.encodeWithSignature("setPauseStatus(uint8)", 0), "setPauseStatus()");
    }

    /// @dev Documents the known skew: the harnesses must not call this on tGLD.
    function test_fork_distributorAbsentOnTGLD() public view {
        _assertHasCode(MainnetAddresses.TGLD_COLLATERAL_MANAGER, "CollateralManager");
        (bool ok,) = MainnetAddresses.TGLD_COLLATERAL_MANAGER.staticcall(abi.encodeWithSignature("distributor()"));
        assertFalse(ok, "distributor() now exists on tGLD -- harness interfaces can be widened");
    }

    function _probeView(address target, bytes memory payload, uint256 expectedLength, string memory label)
        internal
        view
    {
        _assertHasCode(target, label);
        (bool ok, bytes memory result) = target.staticcall(payload);
        assertTrue(ok, string.concat("missing selector on deployed bytecode: ", label));
        assertEq(result.length, expectedLength, string.concat("unexpected return data length: ", label));
    }

    function _probeCall(address target, bytes memory payload, uint256 expectedLength, string memory label) internal {
        _assertHasCode(target, label);
        (bool ok, bytes memory result) = target.call(payload);
        assertTrue(ok, string.concat("missing or reverting selector on deployed bytecode: ", label));
        assertEq(result.length, expectedLength, string.concat("unexpected return data length: ", label));
    }

    function _probeRevert(address target, bytes memory payload, bytes4 expected, string memory label) internal {
        _probeRevertOneOf(target, payload, expected, expected, label);
    }

    /// @dev As `_probeRevert`, but for a target whose access check can be preempted by
    /// another modifier -- either selector is acceptable.
    function _probeRevertOneOf(
        address target,
        bytes memory payload,
        bytes4 expectedA,
        bytes4 expectedB,
        string memory label
    ) internal {
        _assertHasCode(target, label);
        (bool ok, bytes memory result) = target.call(payload);
        assertFalse(ok, string.concat("expected probe call to revert: ", label));
        assertGe(result.length, 4, string.concat("empty revert data: ", label));
        // truncation is the point: only the leading error selector is compared, and the
        // assertGe above guarantees there are 4 bytes to read
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes4 got = bytes4(result);
        assertTrue(got == expectedA || got == expectedB, string.concat("unexpected revert selector: ", label));
    }

    function _probeAccessControlRevert(address target, bytes memory payload, string memory label) internal {
        _probeRevert(target, payload, IAccessControl.AccessControlUnauthorizedAccount.selector, label);
    }

    function _assertHasCode(address target, string memory label) internal view {
        assertGt(target.code.length, 0, string.concat("no deployed code at target: ", label));
    }
}
