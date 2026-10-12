// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract CiGateProbe {
    function isFunded() external view returns (bool) {
        return address(this).balance == 1 ether;
    }
}
