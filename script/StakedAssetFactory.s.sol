// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetToken} from "src/AssetToken.sol";
import {BaseScript} from "script/Base.s.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable, Ownable2Step} from "lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {StakedAsset} from "src/StakedAsset.sol";

/// @notice Script to deploy a staking contract with initial shares minted
/// Contract must be funded by at least 1e18 amount of the underlying asset token before attempting to call
// the `createStakedAsset` function.
contract StakedAssetFactory is BaseScript, Ownable2Step {
    using SafeERC20 for AssetToken;

    /// @notice emits when a new staking contract was deployed
    event StakingCreated(address indexed staking);

    constructor(address _owner) Ownable(_owner) {}

    /// @notice Deploys a staking contract with the data provided, and returns it.
    /// @param _payer The address where the asset tokens will come from
    /// @param _salt The salt to be used during deployment
    /// @param _description The description for the new staking contract
    /// @param _symbol The symbol for the new staking contract
    /// @param _asset The underlying token address
    /// @param _owner The owner address of the new staking contract
    function createStakedAsset(
        address _payer,
        bytes32 _salt,
        string memory _description,
        string memory _symbol,
        address _asset,
        address _owner
    ) external onlyOwner returns (StakedAsset staking) {
        address stakingImplementation = address(new StakedAsset{salt: _salt}());
        bytes memory data =
            abi.encodeWithSelector(StakedAsset.initialize.selector, _description, _symbol, _asset, _owner);
        ERC1967Proxy proxy = new ERC1967Proxy{salt: _salt}(stakingImplementation, data);
        staking = StakedAsset(address(proxy));

        // transfer funds from payer
        AssetToken(_asset).safeTransferFrom(_payer, address(this), 1e18);

        AssetToken(_asset).approve(address(staking), 1e18);
        staking.mint(1e18, address(this));

        require(staking.transfer(address(0xDEAD), 1e18));

        emit StakingCreated(address(staking));
        return staking;
    }

    // mark this as a test contract
    function test() public {}
}
