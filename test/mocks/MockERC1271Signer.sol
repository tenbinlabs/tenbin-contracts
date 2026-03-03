// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.30;

import {IController} from "../../src/interface/IController.sol";
import {IERC1271} from "openzeppelin-contracts/contracts/interfaces/IERC1271.sol";
import {Test} from "forge-std/src/Test.sol";

contract MockERC1271Signer is IERC1271, Test {
    // @dev in a real implementation this is not public
    bytes4 public constant MAGICVALUE = bytes4(keccak256("isValidSignature(bytes32,bytes)"));

    mapping(bytes => bool) validSignatures;

    function isValidSignature(
        bytes32,
        /*_hash*/
        bytes memory _signature
    )
        public
        view
        returns (bytes4 magicValue)
    {
        if (validSignatures[_signature]) {
            return MAGICVALUE;
        } else {
            return 0xffffffff;
        }
    }

    function signOrder(uint256 key, bytes32 orderHash) public returns (IController.Signature memory signature) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, orderHash);
        signature = IController.Signature({
            signature_type: IController.SignatureType.ERC1271, signature_bytes: abi.encodePacked(r, s, v)
        });

        validSignatures[signature.signature_bytes] = true;
    }
}
