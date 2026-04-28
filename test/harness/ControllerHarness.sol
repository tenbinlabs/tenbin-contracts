// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Controller} from "../../src/Controller.sol";

contract ControllerHarness is Controller {
    constructor(address asset_, address stakedAsset_, uint256 ratio_, address custodian_, address owner_)
        Controller(asset_, stakedAsset_, ratio_, custodian_, owner_)
    {}

    function exposedVerifyNonce(address signer, uint256 nonce) external view {
        _verifyNonce(signer, nonce);
    }

    function exposedBlockNumberMint() external view returns (uint256) {
        return mintLimit.blockNumber;
    }

    function exposedBlockNumberRedeem() external view returns (uint256) {
        return redeemLimit.blockNumber;
    }

    function exposedBlockMints() external view returns (uint256) {
        return mintLimit.amount;
    }

    function exposedBlockRedeems() external view returns (uint256) {
        return redeemLimit.amount;
    }
}
