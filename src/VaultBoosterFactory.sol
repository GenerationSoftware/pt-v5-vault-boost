// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import { VaultBooster, PrizePool } from "./VaultBooster.sol";

contract VaultBoosterFactory  {
    function createVaultBooster(PrizePool _prizePool, address _vault, address _owner) external returns (VaultBooster) {
        return new VaultBooster(_prizePool, _vault, _owner);
    }
}
