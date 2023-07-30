// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import { ILiquidationSource } from "pt-v5-liquidator-interfaces/interfaces/ILiquidationSource.sol";
import { PrizePool, IERC20, Ownable, TwabController } from "pt-v5-prize-pool/PrizePool.sol";
import { UD60x18, intoUint128 } from "prb-math/UD60x18.sol";

error OnlyLiquidationPair();
error InitialAvailableExceedsBalance(uint112 initialAvailable, uint256 balance);
error InsufficientAvailableBalance(uint112 amountOut, uint112 available);

contract VaultBooster is Ownable, ILiquidationSource {

  PrizePool public immutable prizePool;
  TwabController public immutable twabController;
  address public immutable vault;

  struct Boost {
    address liquidationPair;
    uint96 multiplierOfTotalSupplyPerSecond;
    uint96 tokensPerSecond;
    uint112 available;
    uint48 lastAccruedAt;
  }

  mapping(IERC20 => Boost) public boosts;

  constructor(
    PrizePool _prizePool,
    address _vault,
    address _owner
  ) Ownable(_owner) {
    prizePool = _prizePool;
    twabController = prizePool.twabController();
    vault = _vault;
    aprFixedPoint18 = _aprFixedPoint18;
    lastAccruedAt = block.timestamp;
  }

  function setBoost(IERC20 _token, address _liquidationPair, UD60x18 _multiplierOfTotalSupplyPerSecond, UD60x18 _tokensPerSecond, uint112 _initialAvailable) external onlyOwner {
    if (_initialAvailable > 0) {
      uint256 balance = token.balanceOf(address(this));
      if (balance < _initialAvailable) {
        revert InitialAvailableExceedsBalance(_initialAvailable, balance);
      }
    }
    boosts[_token] = Boost({
      multiplierOfTotalSupplyPerSecond: intoUint128(_multiplierOfTotalSupplyPerSecond),
      tokensPerSecond: intoUint128(_tokensPerSecond),
      available: _initialAvailable,
      lastAccruedAt: uint48(block.timestamp)
    });
  }

  function deposit(IERC20 _token, uint256 _amount) external {
    _accrue(_token);
    _token.transferFrom(msg.sender, address(this), _amount);
  }

  function accrue(IERC20 _token) external returns (uint256) {
    return _accrue(_token);
  }

  function withdraw(IERC20 _token, uint256 _amount) external onlyOwner {
    _token.transfer(msg.sender, _amount);
  }

  /// @inherit-doc ILiquidationSource
  function liquidatableBalanceOf(address tokenOut) external override returns (uint256) {
    return _accrue(tokenOut);
  }

  /// @inherit-doc ILiquidationSource
  function liquidate(
    address _account,
    address _tokenIn,
    uint256 _amountIn,
    address _tokenOut,
    uint256 _amountOut
  ) external override onlyLiquidationPair(_tokenOut) returns (bool) {
    uint256 amountAvailable = _computeAvailable(_tokenOut);
    if (_amountOut > amountAvailable) {
      revert InsufficientAvailableBalance(_amountOut, amountAvailable);
    }
    boosts[_tokenOut].available = amountAvailable - _amountOut;
    boosts[_tokenOut].lastAccruedAt = uint48(block.timestamp);
    vault.prizePool().contributePrizeTokens(address(this), _amountIn);
    token.transfer(_account, _amountOut);
  }

  /// @inherit-doc ILiquidationSource
  function targetOf(address tokenIn) external view override returns (address) {
    return prizePool;
  }

  modifier onlyLiquidationPair(address _token) {
    if (boosts[IERC20(_token)].liquidationPair != msg.sender) {
      revert OnlyLiquidationPair();
    }
    _;
  }

  function _accrue(IERC20 _tokenOut) internal {
    boosts[_tokenOut].available = _computeAvailable(_tokenOut);
    boosts[_tokenOut].lastAccruedAt = uint48(block.timestamp);
    return available;
  }

  function _computeAvailable(IERC20 _tokenOut) internal view returns (uint256) {
    Boost memory boost = boosts[tokenOut];
    uint256 deltaTime = block.timestamp - boost.lastAccruedAt;
    uint256 deltaAmount;
    if (boost.tokensPerSecond > 0) {
      deltaAmount = convert(UD60x18.wrap(uint256(boost.tokensPerSecond)).mul(convert(deltaTime)));
    }
    if (boost.multiplierOfTotalSupplyPerSecond) {
      uint256 totalSupply = twabController.getTotalSupplyTwabBetween(address(vault), boost.lastAccruedAt, block.timestamp);
      deltaAmount += convert(UD60x18.wrap(uint256(boost.multiplierOfTotalSupplyPerSecond)).mul(convert(deltaTime)).mul(totalSupply));
    }
    uint256 availableBalance = token.balanceOf(address(this));
    deltaAmount = availableBalance > deltaAmount ? deltaAmount : availableBalance;
    return boost.available + deltaAmount;
  }

}
