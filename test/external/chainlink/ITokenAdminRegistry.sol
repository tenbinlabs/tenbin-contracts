// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface ITokenAdminRegistry {
    struct TokenConfig {
        address administrator;
        address pendingAdministrator;
        address tokenPool;
    }

    function getTokenConfig(address token) external view returns (TokenConfig memory);
    function setPool(address asset, address pool) external;
    function transferAdminRole(address asset, address newAdmin) external;
    function proposeAdministrator(address asset, address owner) external;
    function acceptAdminRole(address asset) external;
}
