// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseScript} from "script/Base.s.sol";
import {console2} from "lib/forge-std/src/console2.sol";
import {Controller} from "src/Controller.sol";
import {IController} from "src/interface/IController.sol";

/// @notice Script to mint tokens on testnet
/// 1) Ensure `COLLATERAL_ADDRESS`, `CONTROLLER_ADDRESS`, `MINTER_ADDRESS`, `MINTER_KEY`, and `SIGNER_KEY` are set in `.env`
/// 2) Ensure scripts/MintTestnet.s.sol has the correct addresses set as constants
/// 3) Run `source .env`
/// 4) Ensure approval is granted from payer key
/// ```cast send $COLLATERAL_ADDRESS "approve(address,uint256)" $CONTROLLER_ADDRESS 1000000000000000000000000000000 --rpc-url $SEPOLIA_RPC_URL --private-key $SIGNER_KEY```
/// 5) Run the mint script
/// ```forge script script/MintTestnet.s.sol --rpc-url $SEPOLIA_RPC_URL --private-key $MINTER_KEY --broadcast```
/// THIS SCRIPT IS NOT SAFE TO RUN ON MAINNET!!
contract MintTestnetScript is BaseScript {
    /// @notice Sepolia controller
    address internal constant CONTROLLER_ADDRESS = 0x301351Edf95F7aa505Bd7119a43e40331E2F7E1D;
    /// @notice Testnet signer
    address internal constant SIGNER_ADDRESS = 0xFc8E0e6c28C8f6dD656dE0e9C0b0ecef598Fc9Ce;
    /// @notice Recipient account
    address internal constant RECIPIENT_ADDRESS = 0xFc8E0e6c28C8f6dD656dE0e9C0b0ecef598Fc9Ce;
    /// @notice Collateral address
    address internal constant COLLATERAL_ADDRESS = 0x81FF19CF5053856c2B9f2A6CB5FFc87b96C1e322;

    constructor() {
        broadcaster = vm.envOr({name: "MINTER_ADDRESS", defaultValue: address(0)});
    }

    /// @notice Get order for this mint from
    function getOrder(uint256 nonce) public view returns (IController.Order memory order) {
        /// The order we want to create
        order = IController.Order({
            order_type: IController.OrderType.Mint,
            nonce: nonce,
            expiry: block.timestamp + 60 minutes,
            payer: SIGNER_ADDRESS,
            recipient: RECIPIENT_ADDRESS,
            collateral_token: COLLATERAL_ADDRESS,
            collateral_amount: 100_000e6, // 100k usdc
            asset_amount: 238e17 // 23.8k gold
        });
    }

    /// @notice Execute a mint on sepolia. Must be called using minter key
    function run() public broadcast {
        // set up
        Controller controller = Controller(CONTROLLER_ADDRESS);
        uint256 nonce = block.number;
        IController.Order memory order = getOrder(nonce);
        uint256 payerKey = vm.envUint("SIGNER_KEY");
        address signer = vm.rememberKey(payerKey);
        require(controller.hasRole(MINTER_ROLE, broadcaster) == true, "Broadcaster must be minter");
        controller.verifyNonce(signer, nonce);

        // get order hash and sign
        bytes32 orderHash = controller.hashOrder(order);
        IController.Signature memory signature = signOrder(payerKey, orderHash);
        console2.log("\nSignature bytes: \n");
        console2.logBytes(signature.signature_bytes);

        // perform mint
        controller.mint(order, signature);
        console2.log("mint success.");
        console2.log("recipient: ", order.recipient);
    }

    /// @notice function to sign an order hash
    function signOrder(uint256 payerKey, bytes32 orderHash)
        internal
        pure
        returns (IController.Signature memory signature)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(payerKey, orderHash);
        signature = IController.Signature({
            signature_type: IController.SignatureType.EIP712, signature_bytes: abi.encodePacked(r, s, v)
        });
    }

    // mark this as a test contract
    function test() public {}
}
