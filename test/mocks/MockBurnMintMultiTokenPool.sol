// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IBurnMintERC20} from "src/interface/IBurnMintERC20.sol";
import {RateLimiter} from "lib/chainlink-ccip/chains/evm/contracts/libraries/RateLimiter.sol";
import {EnumerableSet} from "lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {IRouter} from "lib/chainlink-ccip/chains/evm/contracts/interfaces/IRouter.sol";
import {IERC165} from "lib/openzeppelin-contracts/contracts/interfaces/IERC165.sol";
import {Ownable, Ownable2Step} from "lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";

//TODO fix natspecs inherit
/// @dev Chainlink inspired pool compatible with multiple V1 pool types.
contract MockBurnMintMultiTokenPool is IERC165, Ownable2Step {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using RateLimiter for RateLimiter.TokenBucket;

    error CallerIsNotARampOnRouter(address caller);
    error ZeroAddressNotAllowed();
    error SenderNotAllowed(address sender);
    error AllowListNotEnabled();
    error NonExistentChain(uint64 remoteChainSelector);
    error ChainNotAllowed(uint64 remoteChainSelector);
    error CursedByRMN();
    error ChainAlreadyExists(uint64 chainSelector);
    error InvalidSourcePoolAddress(bytes sourcePoolAddress);
    error InvalidToken(address token);

    event Locked(address indexed sender, uint256 amount);
    event Burned(address indexed sender, uint256 amount);
    event Released(address indexed sender, address indexed recipient, uint256 amount);
    event Minted(address indexed sender, address indexed recipient, uint256 amount);
    event ChainAdded(
        uint64 remoteChainSelector,
        bytes remoteToken,
        RateLimiter.Config outboundRateLimiterConfig,
        RateLimiter.Config inboundRateLimiterConfig
    );
    event ChainConfigured(
        uint64 remoteChainSelector,
        RateLimiter.Config outboundRateLimiterConfig,
        RateLimiter.Config inboundRateLimiterConfig
    );
    event ChainRemoved(uint64 remoteChainSelector);
    event RemotePoolSet(uint64 indexed remoteChainSelector, bytes previousPoolAddress, bytes remotePoolAddress);
    event AllowListAdd(address sender);
    event AllowListRemove(address sender);
    event RouterUpdated(address oldRouter, address newRouter);

    // The tag used to signal support for the pool v1 standard.
    // bytes4(keccak256("CCIP_POOL_V1"))
    bytes4 public constant CCIP_POOL_V1 = 0xaff2afbf;

    // The number of bytes in the return data for a pool v1 releaseOrMint call.
    // This should match the size of the ReleaseOrMintOutV1 struct.
    uint16 public constant CCIP_POOL_V1_RET_BYTES = 32;

    // The default max number of bytes in the return data for a pool v1 lockOrBurn call.
    // This data can be used to send information to the destination chain token pool. Can be overwritten
    // in the TokenTransferFeeConfig.destBytesOverhead if more data is required.
    uint32 public constant CCIP_LOCK_OR_BURN_V1_RET_BYTES = 32;

    struct LockOrBurnInV1 {
        bytes receiver; //  The recipient of the tokens on the destination chain, abi encoded.
        uint64 remoteChainSelector; // ─╮ The chain ID of the destination chain.
        address originalSender; // ─────╯ The original sender of the tx on the source chain.
        uint256 amount; //  The amount of tokens to lock or burn, denominated in the source token's decimals.
        address localToken; //  The address on this chain of the token to lock or burn.
    }

    struct LockOrBurnOutV1 {
        // The address of the destination token, abi encoded in the case of EVM chains.
        // This value is UNTRUSTED as any pool owner can return whatever value they want.
        bytes destTokenAddress;
        // Optional pool data to be transferred to the destination chain. Be default this is capped at
        // CCIP_LOCK_OR_BURN_V1_RET_BYTES bytes. If more data is required, the TokenTransferFeeConfig.destBytesOverhead
        // has to be set for the specific token.
        bytes destPoolData;
    }

    struct ReleaseOrMintInV1 {
        bytes originalSender; //            The original sender of the tx on the source chain.
        uint64 remoteChainSelector; // ───╮ The chain ID of the source chain.
        address receiver; // ─────────────╯ The recipient of the tokens on the destination chain.
        uint256 sourceDenominatedAmount; // The amount of tokens to release or mint, denominated in the source token's decimals.
        address localToken; //              The address on this chain of the token to release or mint.
        /// @dev WARNING: sourcePoolAddress should be checked prior to any processing of funds. Make sure it matches the
        /// expected pool address for the given remoteChainSelector.
        bytes sourcePoolAddress; //         The address of the source pool, abi encoded in the case of EVM chains.
        bytes sourcePoolData; //            The data received from the source pool to process the release or mint.
        /// @dev WARNING: offchainTokenData is untrusted data.
        bytes offchainTokenData; //         The offchain data to process the release or mint.
    }

    struct ReleaseOrMintOutV1 {
        // The number of tokens released or minted on the destination chain, denominated in the local token's decimals.
        // This value is expected to be equal to the ReleaseOrMintInV1.amount in the case where the source and destination
        // chain have the same number of decimals.
        uint256 destinationAmount;
    }

    struct ChainUpdate {
        uint64 remoteChainSelector; // ──╮ Remote chain selector
        bool allowed; // ────────────────╯ Whether the chain is allowed
        bytes remotePoolAddress; //        Address of the remote pool, ABI encoded in the case of a remote EVM chain.
        bytes remoteTokenAddress; //       Address of the remote token, ABI encoded in the case of a remote EVM chain.
        RateLimiter.Config outboundRateLimiterConfig; // Outbound rate limited config, meaning the rate limits for all of the onRamps for the given chain
        RateLimiter.Config inboundRateLimiterConfig; // Inbound rate limited config, meaning the rate limits for all of the offRamps for the given chain
    }

    struct RemoteChainConfig {
        RateLimiter.TokenBucket outboundRateLimiterConfig; // Outbound rate limited config, meaning the rate limits for all of the onRamps for the given chain
        RateLimiter.TokenBucket inboundRateLimiterConfig; // Inbound rate limited config, meaning the rate limits for all of the offRamps for the given chain
        bytes remotePoolAddress; // Address of the remote pool, ABI encoded in the case of a remote EVM chain.
        bytes remoteTokenAddress; // Address of the remote token, ABI encoded in the case of a remote EVM chain.
    }

    /// @dev The IERC20 token that this pool supports
    EnumerableSet.AddressSet internal s_tokens;
    /// @dev The address of the RMN proxy
    address internal immutable i_rmnProxy; //TODO cehck if can be erased
    /// @dev The immutable flag that indicates if the pool is access-controlled.
    bool internal immutable i_allowlistEnabled;
    /// @dev A set of addresses allowed to trigger lockOrBurn as original senders.
    /// Only takes effect if i_allowlistEnabled is true.
    /// This can be used to ensure only token-issuer specified addresses can
    /// move tokens.
    EnumerableSet.AddressSet internal s_allowlist;
    /// @dev The address of the router
    IRouter internal s_router;
    /// @dev A set of allowed chain selectors. We want the allowlist to be enumerable to
    /// be able to quickly determine (without parsing logs) who can access the pool.
    /// @dev The chain selectors are in uin256 format because of the EnumerableSet implementation.
    EnumerableSet.UintSet internal s_remoteChainSelectors;
    mapping(address token => mapping(uint64 remoteChainSelector => RemoteChainConfig)) internal s_remoteChainConfigs;
    /// @dev indicates wether the lockOrBurn should lock and burn the tokens
    bool isLock;

    constructor(IERC20[] memory token, address[] memory allowlist, address rmnProxy, address router)
        Ownable(msg.sender)
    {
        for (uint256 i = 0; i < token.length; ++i) {
            s_tokens.add(address(token[i]));
        }
        i_rmnProxy = rmnProxy;
        s_router = IRouter(router);

        // Pool can be set as permissioned or permissionless at deployment time only to save hot-path gas.
        i_allowlistEnabled = allowlist.length > 0;
        if (i_allowlistEnabled) {
            _applyAllowListUpdates(new address[](0), allowlist);
        }
    }

    /// @notice Get RMN proxy address
    /// @return rmnProxy Address of RMN proxy
    function getRmnProxy() public view returns (address rmnProxy) {
        return i_rmnProxy;
    }

    /// Returns wether the token is supported
    function isSupportedToken(address token) public view virtual returns (bool) {
        return s_tokens.contains(token);
    }

    /// @notice Gets the IERC20 token that this pool can lock or burn.
    /// @return tokens The IERC20 token representation.
    function getTokens() public view returns (IERC20[] memory tokens) {
        tokens = new IERC20[](s_tokens.length());
        for (uint256 i = 0; i < s_tokens.length(); ++i) {
            tokens[i] = IERC20(s_tokens.at(i));
        }
        return tokens;
    }

    /// @notice Gets the pool's Router
    /// @return router The pool's Router
    function getRouter() public view returns (address router) {
        return address(s_router);
    }

    /// @notice Sets the pool's Router
    /// @param newRouter The new Router
    function setRouter(address newRouter) public onlyOwner {
        if (newRouter == address(0)) revert ZeroAddressNotAllowed();
        address oldRouter = address(s_router);
        s_router = IRouter(newRouter);

        emit RouterUpdated(oldRouter, newRouter);
    }

    /// @notice Signals which version of the pool interface is supported
    function supportsInterface(bytes4 id) public pure virtual override returns (bool) {
        return (id == 0xffffffff) ? false : true;
    }

    // ================================================================
    // │                         Validation                           │
    // ================================================================

    /// @notice Validates the lock or burn input for correctness on
    /// - token to be locked or burned
    /// - RMN curse status
    /// - allowlist status
    /// - if the sender is a valid onRamp
    /// - rate limit status
    /// @param lockOrBurnIn The input to validate.
    /// @dev This function should always be called before executing a lock or burn. Not doing so would allow
    /// for various exploits.
    function _validateLockOrBurn(LockOrBurnInV1 memory lockOrBurnIn) internal {
        _checkAllowList(lockOrBurnIn.originalSender);

        _onlyOnRamp(lockOrBurnIn.remoteChainSelector);
        _consumeOutboundRateLimit(lockOrBurnIn.localToken, lockOrBurnIn.remoteChainSelector, lockOrBurnIn.amount);
    }

    /// @notice Validates the release or mint input for correctness on
    /// - token to be released or minted
    /// - RMN curse status
    /// - if the sender is a valid offRamp
    /// - if the source pool is valid
    /// - rate limit status
    /// @param releaseOrMintIn The input to validate.
    /// @dev This function should always be called before executing a lock or burn. Not doing so would allow
    /// for various exploits.
    function _validateReleaseOrMint(ReleaseOrMintInV1 memory releaseOrMintIn) internal {
        // Validates that the source pool address is configured on this pool.
        _consumeInboundRateLimit(
            releaseOrMintIn.localToken, releaseOrMintIn.remoteChainSelector, releaseOrMintIn.sourceDenominatedAmount
        );
    }

    // ================================================================
    // │                     Chain permissions                        │
    // ================================================================

    /// @notice Gets the pool address on the remote chain.
    /// @param remoteChainSelector Remote chain selector.
    /// @dev To support non-evm chains, this value is encoded into bytes
    function getRemotePool(address token, uint64 remoteChainSelector) public view returns (bytes memory) {
        return s_remoteChainConfigs[token][remoteChainSelector].remotePoolAddress;
    }

    /// @notice Gets the token address on the remote chain.
    /// @param remoteChainSelector Remote chain selector.
    /// @dev To support non-evm chains, this value is encoded into bytes
    function getRemoteToken(address token, uint64 remoteChainSelector) public view returns (bytes memory) {
        return s_remoteChainConfigs[token][remoteChainSelector].remoteTokenAddress;
    }

    /// Return if remote chain selector is supported
    function isSupportedChain(uint64 remoteChainSelector) public view returns (bool) {
        return s_remoteChainSelectors.contains(remoteChainSelector);
    }

    /// @notice Get list of allowed chains
    /// @return list of chains.
    function getSupportedChains() public view returns (uint64[] memory) {
        uint256[] memory uint256ChainSelectors = s_remoteChainSelectors.values();
        uint64[] memory chainSelectors = new uint64[](uint256ChainSelectors.length);
        for (uint256 i = 0; i < uint256ChainSelectors.length; ++i) {
            chainSelectors[i] = uint64(uint256ChainSelectors[i]);
        }

        return chainSelectors;
    }

    /// @notice Sets the permissions for a list of chains selectors. Actual senders for these chains
    /// need to be allowed on the Router to interact with this pool.
    /// @dev Only callable by the owner
    /// @param chains A list of chains and their new permission status & rate limits. Rate limits
    /// are only used when the chain is being added through `allowed` being true.
    function applyChainUpdates(address token, ChainUpdate[] calldata chains) external virtual onlyOwner {
        for (uint256 i = 0; i < chains.length; ++i) {
            ChainUpdate memory update = chains[i];
            RateLimiter._validateTokenBucketConfig(update.outboundRateLimiterConfig);
            RateLimiter._validateTokenBucketConfig(update.inboundRateLimiterConfig);

            if (update.allowed) {
                // If the chain already exists, revert
                s_remoteChainSelectors.add(update.remoteChainSelector);

                if (update.remotePoolAddress.length == 0 || update.remoteTokenAddress.length == 0) {
                    revert ZeroAddressNotAllowed();
                }

                s_remoteChainConfigs[token][update.remoteChainSelector] = RemoteChainConfig({
                    outboundRateLimiterConfig: RateLimiter.TokenBucket({
                        rate: update.outboundRateLimiterConfig.rate,
                        capacity: update.outboundRateLimiterConfig.capacity,
                        tokens: update.outboundRateLimiterConfig.capacity,
                        lastUpdated: uint32(block.timestamp),
                        isEnabled: update.outboundRateLimiterConfig.isEnabled
                    }),
                    inboundRateLimiterConfig: RateLimiter.TokenBucket({
                        rate: update.inboundRateLimiterConfig.rate,
                        capacity: update.inboundRateLimiterConfig.capacity,
                        tokens: update.inboundRateLimiterConfig.capacity,
                        lastUpdated: uint32(block.timestamp),
                        isEnabled: update.inboundRateLimiterConfig.isEnabled
                    }),
                    remotePoolAddress: update.remotePoolAddress,
                    remoteTokenAddress: update.remoteTokenAddress
                });

                emit ChainAdded(
                    update.remoteChainSelector,
                    update.remoteTokenAddress,
                    update.outboundRateLimiterConfig,
                    update.inboundRateLimiterConfig
                );
            } else {
                // If the chain doesn't exist, revert
                if (!s_remoteChainSelectors.remove(update.remoteChainSelector)) {
                    revert NonExistentChain(update.remoteChainSelector);
                }

                delete s_remoteChainConfigs[token][update.remoteChainSelector];

                emit ChainRemoved(update.remoteChainSelector);
            }
        }
    }

    // ================================================================
    // │                        Rate limiting                         │
    // ================================================================

    /// @notice Consumes outbound rate limiting capacity in this pool
    function _consumeOutboundRateLimit(address token, uint64 remoteChainSelector, uint256 amount) internal {
        s_remoteChainConfigs[token][remoteChainSelector].outboundRateLimiterConfig._consume(amount, token);
    }

    /// @notice Consumes inbound rate limiting capacity in this pool
    function _consumeInboundRateLimit(address token, uint64 remoteChainSelector, uint256 amount) internal {
        s_remoteChainConfigs[token][remoteChainSelector].inboundRateLimiterConfig._consume(amount, token);
    }

    /// @notice Gets the token bucket with its values for the block it was requested at.
    /// @return The token bucket.
    function getCurrentOutboundRateLimiterState(address token, uint64 remoteChainSelector)
        external
        view
        returns (RateLimiter.TokenBucket memory)
    {
        return s_remoteChainConfigs[token][remoteChainSelector].outboundRateLimiterConfig._currentTokenBucketState();
    }

    /// @notice Gets the token bucket with its values for the block it was requested at.
    /// @return The token bucket.
    function getCurrentInboundRateLimiterState(address token, uint64 remoteChainSelector)
        external
        view
        returns (RateLimiter.TokenBucket memory)
    {
        return s_remoteChainConfigs[token][remoteChainSelector].inboundRateLimiterConfig._currentTokenBucketState();
    }

    /// @notice Sets the chain rate limiter config.
    /// @param remoteChainSelector The remote chain selector for which the rate limits apply.
    /// @param outboundConfig The new outbound rate limiter config, meaning the onRamp rate limits for the given chain.
    /// @param inboundConfig The new inbound rate limiter config, meaning the offRamp rate limits for the given chain.
    function _setChainRateLimiterConfig(
        address token,
        uint64 remoteChainSelector,
        RateLimiter.Config memory outboundConfig,
        RateLimiter.Config memory inboundConfig
    ) internal {
        if (!isSupportedChain(remoteChainSelector)) {
            revert NonExistentChain(remoteChainSelector);
        }
        RateLimiter._validateTokenBucketConfig(outboundConfig);
        s_remoteChainConfigs[token][remoteChainSelector].outboundRateLimiterConfig._setTokenBucketConfig(outboundConfig);
        RateLimiter._validateTokenBucketConfig(inboundConfig);
        s_remoteChainConfigs[token][remoteChainSelector].inboundRateLimiterConfig._setTokenBucketConfig(inboundConfig);
        emit ChainConfigured(remoteChainSelector, outboundConfig, inboundConfig);
    }

    // ================================================================
    // │                           Access                             │
    // ================================================================

    /// @notice Checks whether remote chain selector is configured on this contract, and if the msg.sender
    /// is a permissioned onRamp for the given chain on the Router.
    function _onlyOnRamp(uint64 remoteChainSelector) internal view {
        if (!isSupportedChain(remoteChainSelector)) revert ChainNotAllowed(remoteChainSelector);
        if (!(msg.sender == s_router.getOnRamp(remoteChainSelector))) revert CallerIsNotARampOnRouter(msg.sender);
    }

    /// @notice Checks whether remote chain selector is configured on this contract, and if the msg.sender
    /// is a permissioned offRamp for the given chain on the Router.
    function _onlyOffRamp(uint64 remoteChainSelector) internal view {
        if (!isSupportedChain(remoteChainSelector)) revert ChainNotAllowed(remoteChainSelector);
        if (!s_router.isOffRamp(remoteChainSelector, msg.sender)) revert CallerIsNotARampOnRouter(msg.sender);
    }

    // ================================================================
    // │                          Allowlist                           │
    // ================================================================

    function _checkAllowList(address sender) internal view {
        if (i_allowlistEnabled && !s_allowlist.contains(sender)) revert SenderNotAllowed(sender);
    }

    /// @notice Gets whether the allowlist functionality is enabled.
    /// @return true is enabled, false if not.
    function getAllowListEnabled() external view returns (bool) {
        return i_allowlistEnabled;
    }

    /// @notice Gets the allowed addresses.
    /// @return The allowed addresses.
    function getAllowList() external view returns (address[] memory) {
        return s_allowlist.values();
    }

    /// @notice Apply updates to the allow list.
    /// @param removes The addresses to be removed.
    /// @param adds The addresses to be added.
    /// @dev allowlisting will be removed before public launch
    function applyAllowListUpdates(address[] calldata removes, address[] calldata adds) external onlyOwner {
        _applyAllowListUpdates(removes, adds);
    }

    /// @notice Internal version of applyAllowListUpdates to allow for reuse in the constructor.
    function _applyAllowListUpdates(address[] memory removes, address[] memory adds) internal {
        if (!i_allowlistEnabled) revert AllowListNotEnabled();

        for (uint256 i = 0; i < removes.length; ++i) {
            address toRemove = removes[i];
            if (s_allowlist.remove(toRemove)) {
                emit AllowListRemove(toRemove);
            }
        }
        for (uint256 i = 0; i < adds.length; ++i) {
            address toAdd = adds[i];
            if (toAdd == address(0)) {
                continue;
            }
            if (s_allowlist.add(toAdd)) {
                emit AllowListAdd(toAdd);
            }
        }
    }

    /// @notice Burn the token in the pool
    /// @dev The _validateLockOrBurn check is an essential security check
    function lockOrBurn(LockOrBurnInV1 calldata lockOrBurnIn) external virtual returns (LockOrBurnOutV1 memory) {
        _validateLockOrBurn(lockOrBurnIn);

        if (!isLock) {
            IBurnMintERC20(lockOrBurnIn.localToken).burn(lockOrBurnIn.amount);

            emit Burned(msg.sender, lockOrBurnIn.amount);
        }

        return LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.localToken, lockOrBurnIn.remoteChainSelector),
            destPoolData: ""
        });
    }

    /// @notice Mint tokens from the pool to the recipient
    /// @dev The _validateReleaseOrMint check is an essential security check
    function releaseOrMint(ReleaseOrMintInV1 calldata releaseOrMintIn)
        external
        virtual
        returns (ReleaseOrMintOutV1 memory)
    {
        _validateReleaseOrMint(releaseOrMintIn);

        // Mint to the receiver
        IBurnMintERC20(releaseOrMintIn.localToken)
            .mint(releaseOrMintIn.receiver, releaseOrMintIn.sourceDenominatedAmount);

        emit Minted(msg.sender, releaseOrMintIn.receiver, releaseOrMintIn.sourceDenominatedAmount);

        return ReleaseOrMintOutV1({destinationAmount: releaseOrMintIn.sourceDenominatedAmount});
    }

    function setIsLock(bool newValue) external {
        isLock = newValue;
    }
}
