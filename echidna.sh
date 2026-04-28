#!/bin/bash
echidna test/invariant/AssetTokenInvariant.t.sol --contract AssetTokenInvariantTest --config echidna.yaml
echidna test/invariant/CollateralManagerInvariant.t.sol --contract CollateralManagerInvariantTest --config echidna.yaml
echidna test/invariant/ControllerInvariant.t.sol --contract ControllerInvariantTest --config echidna.yaml
echidna test/invariant/CustodianInvariant.t.sol --contract CustodianModuleInvariantTest --config echidna.yaml
echidna test/invariant/StakedAssetInvariant.t.sol --contract StakedAssetInvariantTest --config echidna.yaml