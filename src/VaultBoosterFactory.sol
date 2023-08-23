// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import { VaultBooster, PrizePool } from "./VaultBooster.sol";

/// @title VaultBoosterFactory
/// @author G9 Software Inc.
/// @notice Factory contract for VaultBooster
contract VaultBoosterFactory  {

    /// @notice Emitted when a new VaultBooster is created
    /// @param vaultBooster The address of the new Vault Booster
    /// @param prizePool The address of the prize pool to contribute to
    /// @param vault The address of the vault to contribute for
    /// @param owner The owner of the VaultBooster
    event CreatedVaultBooster(
        VaultBooster indexed vaultBooster,
        PrizePool indexed prizePool,
        address indexed vault,
        address owner
    );

    /// @notice Mapping to store deployer nonces for CREATE2
    mapping(address deployer => uint256 nonce) public deployerNonces;

    /// @notice Creates a new vault booster contract
    /// @param _prizePool The prize pool to contribute to
    /// @param _vault The vault to contribute for
    /// @param _owner The owner of the Vault Booster
    /// @return The address of the new Vault Booster
    function createVaultBooster(PrizePool _prizePool, address _vault, address _owner) external returns (VaultBooster) {
        // Use CREATE2 constructor with a salt derived from caller's address and their unique nonce
        VaultBooster booster = new VaultBooster{salt: keccak256(abi.encode(msg.sender, deployerNonces[msg.sender]++))}(_prizePool, _vault, _owner);

        emit CreatedVaultBooster(booster, _prizePool, _vault, _owner);

        return booster;
    }
}
