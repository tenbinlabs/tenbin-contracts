// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {AdaptiveCurveIrm} from "vault-v2/lib/morpho-blue-irm/src/adaptive-curve-irm/AdaptiveCurveIrm.sol";
import {Morpho} from "vault-v2/lib/morpho-blue/src/Morpho.sol";

// Morpho blue and its IRM are pinned to solc 0.8.19 and cannot be imported by the 0.8.30
// deploy scripts. Referencing them here forces artifact compilation so Deploy.s.sol can
// deploy them on local chains via deployCode (vm.getCode). See MorphoArtifacts.sol.
contract MorphoBlueArtifacts {
    AdaptiveCurveIrm internal adaptiveCurveIrm;
    Morpho internal morpho;
}
