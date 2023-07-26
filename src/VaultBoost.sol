// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import { ILiquidationSource } from "pt-v5-liquidator-interfaces/interfaces/ILiquidationSource.sol";
import { Vault, PrizePool, IERC20, Ownable } from "pt-v5-vault/Vault.sol";

contract VaultBoost is Ownable, ILiquidationSource {

  Vault public immutable vault;
  PrizePool public immutable prizePool;
  IERC20 public immutable token;
  uint256 public immutable aprFixedPoint18;

  address liquidationPair;

  uint208 public available;
  uint48 public lastAccruedAt;

  constructor(
    Vault _vault,
    uint256 _aprFixedPoint18,
    address _owner
  ) Ownable(_owner) {
    vault = _vault;
    prizePool = _vault.prizePool();
    token = _vault.asset();
    aprFixedPoint18 = _aprFixedPoint18;
    lastAccruedAt = block.timestamp;
  }

  function setLiquidationPair(address _liquidationPair) external onlyOwner {
    liquidationPair = _liquidationPair;
  }

  /// @inherit-doc ILiquidationSource
  function liquidatableBalanceOf(address tokenOut) external override returns (uint256) {
    require(tokenOut == token, "VaultBoost/invalid-token-out");
    _accrue();
    return available;
  }

  /// @inherit-doc ILiquidationSource
  function liquidate(
    address _account,
    address _tokenIn,
    uint256 _amountIn,
    address _tokenOut,
    uint256 _amountOut
  ) external override returns (bool) {
    require(_tokenIn == prizePool.prizeToken(), "VaultBoost/invalid-token-in");
    require(_tokenOut == token, "VaultBoost/invalid-token-out");
    vault.prizePool().contributePrizeTokens(address(this), _amountIn);
    token.transfer(_account, _amountOut);
  }

  /// @inherit-doc ILiquidationSource
  function targetOf(address tokenIn) external view override returns (address) {
    return prizePool;
  }

  function _accrue() internal {
    uint256 deltaTime = block.timestamp - lastAccruedAt;
    uint256 interest = (deltaTime * aprFixedPoint18 * vault.totalAssets()) / (365 days * 1e18);
    uint256 availableBalance = token.balanceOf(address(this));
    available += availableBalance > interest ? uint208(interest) : availableBalance;
    lastAccruedAt = uint48(block.timestamp);
  }

}
