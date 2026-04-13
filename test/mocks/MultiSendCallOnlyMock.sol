// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @dev Test double for Safe's MultiSendCallOnly batching helper
contract MultiSendCallOnlyMock {
    function multiSend(bytes calldata transactions) external {
        uint256 i = 0;

        while (i < transactions.length) {
            uint8 op = uint8(transactions[i]);
            i += 1;

            address to;
            assembly {
                to := shr(96, calldataload(add(transactions.offset, i)))
            }
            i += 20;

            uint256 value;
            assembly {
                value := calldataload(add(transactions.offset, i))
            }
            i += 32;

            uint256 dataLen;
            assembly {
                dataLen := calldataload(add(transactions.offset, i))
            }
            i += 32;

            bytes calldata data = transactions[i:i + dataLen];
            i += dataLen;

            require(op == 0, "only CALL");

            (bool ok,) = to.call{value: value}(data);
            require(ok, "inner failed");
        }
    }
}
