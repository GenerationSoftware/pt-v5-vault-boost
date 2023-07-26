// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import { VaultBoost, Vault } from "./VaultBoost.sol";

contract VaultBoostFactory  {

    function createVaultBoost(
        Vault _vault,
        uint256 _aprFixedPoint18,
        address _owner
    ) external returns (VaultBoost) {
        return new VaultBoost(_vault, _aprFixedPoint18, _owner);
    }

}
