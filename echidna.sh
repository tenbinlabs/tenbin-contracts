#!/bin/bash
echidna test/echidna/AssetSiloEchidna.sol --contract AssetSiloEchidna --config echidna.yaml
echidna test/echidna/AssetTokenEchidna.sol --contract AssetTokenEchidna --config echidna.yaml
echidna test/echidna/CollateralManagerEchidna.sol --contract CollateralManagerEchidna --config echidna.yaml
echidna test/echidna/ControllerEchidna.sol --contract ControllerEchidna --config echidna.yaml
echidna test/echidna/CustodianModuleEchidna.sol --contract CustodianModuleEchidna --config echidna.yaml
echidna test/echidna/RevenueModuleEchidna.sol --contract RevenueModuleEchidna --config echidna.yaml
echidna test/echidna/StakedAssetEchidna.sol --contract StakedAssetEchidna --config echidna.yaml
echidna test/echidna/SwapModuleEchidna.sol --contract SwapModuleEchidna --config echidna.yaml