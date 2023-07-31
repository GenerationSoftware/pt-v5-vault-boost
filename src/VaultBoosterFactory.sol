// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import { VaultBooster, PrizePool } from "./VaultBooster.sol";

contract VaultBoosterFactory  {

    event CreatedVaultBooster(
        VaultBooster indexed vaultBooster,
        PrizePool indexed _prizePool,
        address indexed _vault,
        address _owner
    );

    function createVaultBooster(PrizePool _prizePool, address _vault, address _owner) external returns (VaultBooster) {
        VaultBooster booster = new VaultBooster(_prizePool, _vault, _owner);

        emit CreatedVaultBooster(booster, _prizePool, _vault, _owner);

        return booster;
    }
}
