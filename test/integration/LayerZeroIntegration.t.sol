// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {EndpointV2Mock} from "lib/devtools/packages/test-devtools-evm-foundry/contracts/mocks/EndpointV2Mock.sol";
import {ExecutorConfig} from "lib/LayerZero-v2/packages/layerzero-v2/evm/messagelib/contracts/SendLibBase.sol";
import {LayerZeroMintBurnOFTAdapter} from "src/adapters/LayerZeroMintBurnOFTAdapter.sol";
import {LayerZeroOFTAdapter} from "src/adapters/LayerZeroOFTAdapter.sol";
import {LayerZeroOVaultComposer} from "src/adapters/LayerZeroOVaultComposer.sol";
import {MessagingFee, SendParam} from "lib/devtools/packages/oft-evm/contracts/interfaces/IOFT.sol";
import {MockLayerZeroExecutor} from "test/mocks/MockLayerZeroExecutor.sol";
import {MockSendLibBaseE2} from "test/mocks/MockSendLibBaseE2.sol";
import {OFTMsgCodec} from "lib/devtools/packages/oft-evm/contracts/libs/OFTMsgCodec.sol";
import {Origin} from "lib/devtools/packages/oapp-evm/contracts/oapp/OAppReceiver.sol";
import {
    SetDefaultExecutorConfigParam
} from "lib/LayerZero-v2/packages/layerzero-v2/evm/messagelib/contracts/SendLibBase.sol";

/// @notice Integration test for layerzero oft
/// Mock layer zero endpoint for hub chain
contract LayerZeroIntegrationTest is BaseTest {
    // constants
    uint32 internal constant BASE_CHAINID = 8453;
    bytes32 internal constant MOCK_PEER = 0x1000000000000000000000000000000000000000000000000000000000000000;
    bytes32 internal constant MOCK_SENDER = 0x1000000000000000000000000000000000000000000000000000000000000000;
    bytes32 internal constant MOCK_GUID = 0xFF00000000000000000000000000000000000000000000000000000000000000;
    // with 6 shared decimals, the amount that can be sent is 1e12 - 2e64
    uint256 internal constant ASSET_SLIPPAGE = 1e12;
    uint256 internal constant MIN_ASSET_AMOUNT = 1e12;
    uint256 internal constant MAX_ASSET_AMOUNT = uint256(type(uint64).max) * 1e6;

    // contracts
    LayerZeroMintBurnOFTAdapter internal mintBurnAdapter;
    LayerZeroOFTAdapter internal assetAdapter;
    LayerZeroOFTAdapter internal stakingAdapter;
    EndpointV2Mock internal endpoint;
    MockSendLibBaseE2 internal sendLib;
    MockLayerZeroExecutor internal executor;
    LayerZeroOVaultComposer internal oVaultComposer;

    function setUp() public virtual override {
        super.setUp();

        // set up accounts
        user = vm.addr(0xC001);

        // run from owner account
        vm.startPrank(owner);

        // deploy layerzero and adapter
        executor = new MockLayerZeroExecutor();
        endpoint = new EndpointV2Mock(BASE_CHAINID, owner);
        sendLib = new MockSendLibBaseE2(address(endpoint), owner);
        assetAdapter = new LayerZeroOFTAdapter(address(asset), address(endpoint), owner);
        stakingAdapter = new LayerZeroOFTAdapter(address(staking), address(endpoint), owner);
        mintBurnAdapter =
            new LayerZeroMintBurnOFTAdapter(owner, address(asset), address(asset), address(endpoint), owner);
        oVaultComposer = new LayerZeroOVaultComposer(address(staking), address(assetAdapter), address(stakingAdapter));
        // Configure layerzero
        SetDefaultExecutorConfigParam[] memory configs = new SetDefaultExecutorConfigParam[](2);
        configs[0] = SetDefaultExecutorConfigParam({
            eid: 1, config: ExecutorConfig({maxMessageSize: type(uint32).max, executor: address(executor)})
        });
        configs[1] = SetDefaultExecutorConfigParam({
            eid: BASE_CHAINID, config: ExecutorConfig({maxMessageSize: type(uint32).max, executor: address(executor)})
        });
        sendLib.setDefaultExecutorConfigs(configs);

        // set peer for adapters
        assetAdapter.setPeer(BASE_CHAINID, MOCK_PEER);
        stakingAdapter.setPeer(BASE_CHAINID, MOCK_PEER);
        mintBurnAdapter.setPeer(BASE_CHAINID, MOCK_PEER);
        assetAdapter.setPeer(1, MOCK_PEER);
        stakingAdapter.setPeer(1, MOCK_PEER);
        mintBurnAdapter.setPeer(1, MOCK_PEER);

        // register and set send library
        endpoint.registerLibrary(address(sendLib));
        endpoint.setSendLibrary({
            _oapp: address(assetAdapter), // address _oapp,
            _eid: BASE_CHAINID, // uint32 _eid,
            _newLib: address(sendLib) // address _newLib
        });
        endpoint.setSendLibrary({
            _oapp: address(stakingAdapter), // address _oapp,
            _eid: BASE_CHAINID, // uint32 _eid,
            _newLib: address(sendLib) // address _newLib
        });
        endpoint.setSendLibrary({
            _oapp: address(mintBurnAdapter), // address _oapp,
            _eid: BASE_CHAINID, // uint32 _eid,
            _newLib: address(sendLib) // address _newLib
        });

        endpoint.setSendLibrary({
            _oapp: address(assetAdapter), // address _oapp,
            _eid: 1, // uint32 _eid,
            _newLib: address(sendLib) // address _newLib
        });
        endpoint.setSendLibrary({
            _oapp: address(stakingAdapter), // address _oapp,
            _eid: 1, // uint32 _eid,
            _newLib: address(sendLib) // address _newLib
        });
        endpoint.setSendLibrary({
            _oapp: address(mintBurnAdapter), // address _oapp,
            _eid: 1, // uint32 _eid,
            _newLib: address(sendLib) // address _newLib
        });
        vm.stopPrank();
        label(address(mintBurnAdapter), "mintBurnAdapter");
        label(address(assetAdapter), "assetAdapter");
        label(address(stakingAdapter), "stakingAdapter");
        label(address(endpoint), "endpoint");
        label(address(sendLib), "sendLib");
        label(address(executor), "executor");
        label(address(oVaultComposer), "oVaultComposer");
    }

    function test_LayerZero_SetUp() public view {
        assertEq(assetAdapter.token(), address(asset));
        assertEq(assetAdapter.approvalRequired(), true);
        assertEq(stakingAdapter.token(), address(staking));
        assertEq(stakingAdapter.approvalRequired(), true);
    }

    function test_LayerZero_OFTAdapter_Send(uint256 amount) public {
        amount = bound(amount, MIN_ASSET_AMOUNT, MAX_ASSET_AMOUNT);

        // mint asset tokens
        mintAsset(user, amount);

        // approve the adapter to spend user tokens
        vm.prank(user);
        asset.approve(address(assetAdapter), amount);

        // create the parameters for the send
        MessagingFee memory fee = MessagingFee({
            nativeFee: 0, // uint256 nativeFee;
            lzTokenFee: 0 // uint256 lzTokenFee;
        });
        SendParam memory sendParam = SendParam({
            dstEid: BASE_CHAINID, // uint32 dstEid; // Destination endpoint ID.
            to: bytes32(0), // bytes32 to; // Recipient address.
            amountLD: amount, // uint256 amountLD; // Amount to send in local decimals.
            minAmountLD: amount - ASSET_SLIPPAGE, // uint256 minAmountLD; // Minimum amount to send in local decimals.
            extraOptions: new bytes(0), // bytes extraOptions; // Additional options supplied by the caller to be used in the LayerZero message.
            composeMsg: new bytes(0), // bytes composeMsg; // The composed message for the send() operation.
            oftCmd: new bytes(0) // bytes oftCmd; // The OFT command to be executed, unused in default OFT implementations.
        });

        // call send function on adapter
        vm.prank(user);
        assetAdapter.send(sendParam, fee, user);

        // assert adapter has tokens
        assertApproxEqAbs(
            asset.balanceOf(address(assetAdapter)), amount, ASSET_SLIPPAGE, "insufficient amount received"
        );
        assertApproxEqAbs(asset.balanceOf(user), 0, ASSET_SLIPPAGE, "excessive balance");
    }

    function test_LayerZero_OFTAdapter_Receive(uint256 amount) public {
        amount = bound(amount, MIN_ASSET_AMOUNT, MAX_ASSET_AMOUNT);

        // mint asset tokens
        mintAsset(address(assetAdapter), amount);

        Origin memory origin = Origin({
            srcEid: BASE_CHAINID, // uint32 srcEid;
            sender: MOCK_SENDER, // bytes32 sender;
            nonce: 0 // uint64 nonce;
        });

        // convert to shared decimal format used by layer zero
        // forge-lint: disable-next-line(unsafe-typecast)
        uint64 amountSD = uint64(amount / assetAdapter.decimalConversionRate());

        (bytes memory message,) = OFTMsgCodec.encode(
            OFTMsgCodec.addressToBytes32(user), // bytes32 _sendTo,
            amountSD, // uint64 _amountShared,
            new bytes(0) // bytes memory _composeMsg
        );

        vm.prank(address(endpoint));
        assetAdapter.lzReceive(
            origin, // Origin calldata _origin,
            MOCK_GUID, // bytes32 _guid,
            message, // bytes calldata _message, (the address we send to)
            address(executor), // address _executor,
            new bytes(0) // bytes calldata _extraData
        );

        assertApproxEqAbs(asset.balanceOf(address(assetAdapter)), 0, ASSET_SLIPPAGE, "insufficient amount sent");
        assertApproxEqAbs(asset.balanceOf(user), amount, ASSET_SLIPPAGE, "insufficient amount received");
    }

    function test_LayerZero_MintBurnAdapter_Send(uint256 amount) public {
        amount = bound(amount, MIN_ASSET_AMOUNT, MAX_ASSET_AMOUNT);

        // mint asset tokens
        mintAsset(user, amount);

        // make mint and burn adapter minter
        vm.prank(owner);
        asset.setMinter(address(mintBurnAdapter));

        // approve the adapter to spend user tokens
        vm.prank(user);
        asset.approve(address(mintBurnAdapter), amount);

        // create the parameters for the send
        MessagingFee memory fee = MessagingFee({
            nativeFee: 0, // uint256 nativeFee;
            lzTokenFee: 0 // uint256 lzTokenFee;
        });
        SendParam memory sendParam = SendParam({
            dstEid: BASE_CHAINID, // uint32 dstEid; // Destination endpoint ID.
            to: bytes32(0), // bytes32 to; // Recipient address.
            amountLD: amount, // uint256 amountLD; // Amount to send in local decimals.
            minAmountLD: amount - ASSET_SLIPPAGE, // uint256 minAmountLD; // Minimum amount to send in local decimals.
            extraOptions: new bytes(0), // bytes extraOptions; // Additional options supplied by the caller to be used in the LayerZero message.
            composeMsg: new bytes(0), // bytes composeMsg; // The composed message for the send() operation.
            oftCmd: new bytes(0) // bytes oftCmd; // The OFT command to be executed, unused in default OFT implementations.
        });

        // call send function on adapter
        vm.prank(user);
        mintBurnAdapter.send(sendParam, fee, user);

        // assert tokens are burned
        assertApproxEqAbs(asset.totalSupply(), 0, ASSET_SLIPPAGE, "insufficient balance burned");
        assertApproxEqAbs(asset.balanceOf(user), 0, ASSET_SLIPPAGE, "exceeds balance");
    }

    function test_LayerZero_MintBurnAdapter_Receive(uint256 amount) public {
        amount = bound(amount, MIN_ASSET_AMOUNT, MAX_ASSET_AMOUNT);

        // make mint and burn adapter minter
        vm.prank(owner);
        asset.setMinter(address(mintBurnAdapter));

        Origin memory origin = Origin({
            srcEid: BASE_CHAINID, // uint32 srcEid;
            sender: MOCK_SENDER, // bytes32 sender;
            nonce: 0 // uint64 nonce;
        });

        // convert to shared decimal format used by layer zero
        // forge-lint: disable-next-line(unsafe-typecast)
        uint64 amountSD = uint64(amount / assetAdapter.decimalConversionRate());

        (bytes memory message,) = OFTMsgCodec.encode(
            OFTMsgCodec.addressToBytes32(user), // bytes32 _sendTo,
            amountSD, // uint64 _amountShared,
            new bytes(0) // bytes memory _composeMsg
        );

        vm.prank(address(endpoint));
        mintBurnAdapter.lzReceive(
            origin, // Origin calldata _origin,
            MOCK_GUID, // bytes32 _guid,
            message, // bytes calldata _message, (the address we send to)
            address(executor), // address _executor,
            new bytes(0) // bytes calldata _extraData
        );

        assertApproxEqAbs(asset.balanceOf(user), amount, ASSET_SLIPPAGE, "insufficient balance minted");
        assertApproxEqAbs(asset.totalSupply(), amount, ASSET_SLIPPAGE, "insufficient total supply");
    }

    function test_LayerZero_OVault_Send() public {
        uint256 amount = 10e18;
        mintAsset(user, amount);
        vm.prank(user);
        asset.approve(address(oVaultComposer), amount);

        // convert to shared decimal format used by layer zero
        // forge-lint: disable-next-line(unsafe-typecast)
        uint64 amountSD = uint64(amount / assetAdapter.decimalConversionRate());

        (bytes memory message,) = OFTMsgCodec.encode(
            OFTMsgCodec.addressToBytes32(user), // bytes32 _sendTo,
            amountSD, // uint64 _amountShared,
            new bytes(0) // bytes memory _composeMsg
        );

        SendParam memory sendParam = SendParam({
            dstEid: 1, // uint32 dstEid; // Destination endpoint ID.
            to: bytes32(abi.encode(user)), // bytes32 to; // Recipient address.
            amountLD: amount, // uint256 amountLD; // Amount to send in local decimals.
            minAmountLD: amount - ASSET_SLIPPAGE, // uint256 minAmountLD; // Minimum amount to send in local decimals.
            extraOptions: new bytes(0), // bytes extraOptions; // Additional options supplied by the caller to be used in the LayerZero message.
            composeMsg: message, // bytes composeMsg; // The composed message for the send() operation.
            oftCmd: new bytes(0) // bytes oftCmd; // The OFT command to be executed, unused in default OFT implementations.
        });
        vm.chainId(BASE_CHAINID);
        vm.prank(user);
        oVaultComposer.depositAndSend(
            amount, // uint256 _assetAmount,
            sendParam, // SendParam memory _sendParam,
            user // address _refundAddress
        );
        assertApproxEqAbs(staking.balanceOf(address(stakingAdapter)), amount, ASSET_SLIPPAGE);
    }
}
