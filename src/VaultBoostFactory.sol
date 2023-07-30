// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import { VaultBoost, PrizePool } from "./VaultBoost.sol";

contract VaultBoostFactory  {
    function createVaultBoost(PrizePool _prizePool, address _vault, address _owner) external returns (VaultBoost) {
        return new VaultBoost(_prizePool, _vault, _owner);
    }
}
