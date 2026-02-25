// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetToken} from "src/AssetToken.sol";
import {Controller} from "src/Controller.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockERC4626} from "test/mocks/MockERC4626.sol";

/// Base echidna contract containing commonly reuse data
contract EchidnaBase {
    // addresses used by echidna
    address internal constant USER1 = address(0x10000);
    address internal constant USER2 = address(0x20000);
    address internal constant USER3 = address(0x30000);
    // common roles
    bytes32 internal constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 internal constant RESTRICTER_ROLE = keccak256("RESTRICTER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant GATEKEEPER_ROLE = keccak256("GATEKEEPER_ROLE");
    bytes32 public constant SIGNER_MANAGER_ROLE = keccak256("SIGNER_MANAGER_ROLE");

    // constants
    uint256 internal constant DEFAULT_RATIO = 1e17;

    // ERC20 to be used
    MockERC20 internal collateral;
    MockERC20 internal collateral2;
    IERC4626 internal vault;

    // contracts
    AssetToken asset;
    Controller controller;

    constructor() {
        asset = new AssetToken("AssetToken", "SYN", address(this));
        controller = new Controller(address(asset), DEFAULT_RATIO, address(this), address(this));
        collateral = new MockERC20("CollateralToken", "CLT", 6);
        collateral2 = new MockERC20("CollateralToken2", "CLT2", 18);
        vault = new MockERC4626("Collateral Vault", "vCLT", collateral);

        fundUsers();
        asset.setMinter(address(controller));
        grantRole(ADMIN_ROLE, address(controller));
        grantRole(MINTER_ROLE, address(controller));
        grantRole(GATEKEEPER_ROLE, address(controller));
        grantRole(SIGNER_MANAGER_ROLE, address(controller));
        grantRole(RESTRICTER_ROLE, address(controller));
        controller.setManager(address(this));
        // make sure caller is not owner when we check properties
        asset.renounceOwnership();
    }

    // helper to grant given role to the 3 addresses used by echidna
    function grantRole(bytes32 role, address target) internal {
        IAccessControl(target).grantRole(role, USER1);
        IAccessControl(target).grantRole(role, USER2);
        IAccessControl(target).grantRole(role, USER3);
    }

    // helper to ensure initial funds for all users
    function fundUsers() internal {
        collateral.mint(USER1, 1000e18);
        collateral.mint(USER2, 1000e18);
        collateral.mint(USER3, 1000e18);
    }
}
