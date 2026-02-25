// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {CollateralManager} from "src/CollateralManager.sol";
import {Controller} from "src/Controller.sol";
import {EchidnaBase} from "./EchidnaBase.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ICollateralManager} from "src/interface/ICollateralManager.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {SwapModule} from "src/SwapModule.sol";

// echidna test/echidna/CollateralManagerEchidna.sol --contract CollateralManagerEchidna --config echidna.yaml
contract CollateralManagerEchidna is EchidnaBase {
    CollateralManager manager;
    address revenueModule;
    SwapModule swapModule;
    address router;
    address executor;

    constructor() {
        revenueModule = address(0x4); // Non used by echidna as function caller
        executor = address(0x5);
        router = address(0x6);

        address managerImplementation = address(new CollateralManager());
        bytes memory data =
            abi.encodeWithSelector(CollateralManager.initialize.selector, address(controller), address(this));
        ERC1967Proxy proxy = new ERC1967Proxy(managerImplementation, data);
        manager = CollateralManager(address(proxy));
        swapModule = new SwapModule(address(manager), router, address(this));

        // set up
        manager.grantRole(ADMIN_ROLE, address(this));
        manager.grantRole(manager.CURATOR_ROLE(), address(this));
        grantRole(manager.REBALANCER_ROLE(), address(manager));
        grantRole(manager.CURATOR_ROLE(), address(manager));
        manager.setSwapModule(address(swapModule));
        manager.setRevenueModule(address(revenueModule));
        manager.grantRole(manager.CAP_ADJUSTER_ROLE(), address(this));
        manager.setSwapCap(address(collateral), type(uint256).max);
        manager.setSwapCap(address(collateral2), type(uint256).max);
        manager.revokeRole(manager.CAP_ADJUSTER_ROLE(), address(this));
        manager.addCollateral(address(collateral), address(vault));
    }

    // Controller is never the zero address
    function echidna_controller_never_zero_address() public view returns (bool) {
        return manager.controller() != address(0);
    }

    // Swap module is never the zero address
    function echidna_swapModule_never_zero_address() public view returns (bool) {
        return manager.swapModule() != address(0);
    }

    // Revenue module is never the zero address
    function echidna_revenueModule_never_zero_address() public view returns (bool) {
        return manager.revenueModule() != address(0);
    }

    // Zero address is never a valid collateral
    function echidna_zero_address_is_never_collateral() public view returns (bool) {
        return address(manager.vaults(address(0))) == address(0);
    }

    // setPauseStatus always revert unauthorized callers
    function echidna_setPauseStatus_only_gatekeeper_callable() public returns (bool) {
        try manager.setPauseStatus(ICollateralManager.ManagerPauseStatus.FMLPause) {
            return false;
        } catch {
            return true;
        }
    }

    // setRebalanceCap always revert unauthorized callers
    function echidna_setRebalanceCap_only_capadjuster_callable() public returns (bool) {
        try manager.setRebalanceCap(address(asset), 1e18) {
            return false;
        } catch {
            return true;
        }
    }

    // setSwapCap always revert unauthorized callers
    function echidna_setSwapCap_only_capadjuster_callable() public returns (bool) {
        try manager.setSwapCap(address(asset), 1e18) {
            return false;
        } catch {
            return true;
        }
    }

    // setMinSwapPrice always revert unauthorized callers
    function echidna_setMinSwapPrice_only_capadjuster_callable() public returns (bool) {
        try manager.setMinSwapPrice(address(asset), address(asset), 1e18) {
            return false;
        } catch {
            return true;
        }
    }

    // getRevenue only returns existing collaterals
    function echidna_getRevenue_always_revert_non_collateral() public view returns (bool) {
        try manager.getRevenue(address(asset)) {
            return false;
        } catch {
            return true;
        }
    }

    // getVaultAssets always revert when trying to verify non collateral
    function echidna_getVaultAssets_always_revert_non_collateral() public view returns (bool) {
        try manager.getVaultAssets(address(asset)) {
            return false;
        } catch {
            return true;
        }
    }

    // Deposits only accepts collateral tokens
    function echidna_deposit_always_revert_non_collateral() public returns (bool) {
        try manager.deposit(address(asset), 1e18, 1e18) {
            return false;
        } catch {
            return true;
        }
    }

    // Withdraw only accepts collateral tokens
    function echidna_withdraw_always_revert_non_collateral() public returns (bool) {
        try manager.withdraw(address(asset), 1e18, 1e18) {
            return false;
        } catch {
            return true;
        }
    }

    // withdrawRevenue always revert unauthorized callers
    function echidna_withdrawRevenue_reverts_for_every_non_revenueModule_caller() public returns (bool) {
        try manager.withdrawRevenue(address(asset), 1e18) {
            return false;
        } catch {
            return true;
        }
    }

    // Only collateral balances can be converted to revenue
    function echidna_convertRevenue_always_revert_non_collateral() public returns (bool) {
        try manager.convertRevenue(address(asset), 1e18) {
            return false;
        } catch {
            return true;
        }
    }

    // claimMorphoRewards always revert unauthorized callers
    function echidna_claimMorphoRewards_reverts_for_every_non_revenueModule_caller() public returns (bool) {
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = keccak256("p0");
        proof[1] = keccak256("p1");
        try manager.claimMorphoRewards(address(1), address(2), 1e18, proof) {
            return false;
        } catch {
            return true;
        }
    }
}
