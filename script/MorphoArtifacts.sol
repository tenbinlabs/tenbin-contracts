// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {MorphoVaultV1AdapterFactory} from "vault-v2/src/adapters/MorphoVaultV1AdapterFactory.sol";
import {VaultV2Factory} from "vault-v2/src/VaultV2Factory.sol";

// The concrete morpho contracts are pinned to solc 0.8.28 and cannot be imported by the
// 0.8.30 deploy scripts. Referencing them here forces artifact compilation so Deploy.s.sol
// can deploy them on local chains via deployCode (vm.getCode).
contract MorphoArtifacts {
    MorphoVaultV1AdapterFactory internal adapterFactory;
    VaultV2Factory internal vaultFactory;
}
