// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import { ILiquidationSource } from "pt-v5-liquidator-interfaces/interfaces/ILiquidationSource.sol";
import { PrizePool, IERC20, TwabController } from "pt-v5-prize-pool/PrizePool.sol";
import { UD60x18, convert } from "prb-math/UD60x18.sol";
import { Ownable } from "openzeppelin/access/Ownable.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";

error OnlyLiquidationPair();
error InitialAvailableExceedsBalance(uint112 initialAvailable, uint256 balance);
error InsufficientAvailableBalance(uint256 amountOut, uint256 available);
error UnsupportedTokenIn();

contract VaultBooster is Ownable, ILiquidationSource {
  using SafeERC20 for IERC20;
  using SafeCast for uint256;

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
  }

  function setBoost(IERC20 _token, address _liquidationPair, UD60x18 _multiplierOfTotalSupplyPerSecond, UD60x18 _tokensPerSecond, uint112 _initialAvailable) external onlyOwner {
    if (_initialAvailable > 0) {
      uint256 balance = _token.balanceOf(address(this));
      if (balance < _initialAvailable) {
        revert InitialAvailableExceedsBalance(_initialAvailable, balance);
      }
    }
    boosts[_token] = Boost({
      liquidationPair: _liquidationPair,
      multiplierOfTotalSupplyPerSecond: _multiplierOfTotalSupplyPerSecond.unwrap().toUint96(),
      tokensPerSecond: _tokensPerSecond.unwrap().toUint96(),
      available: _initialAvailable,
      lastAccruedAt: uint48(block.timestamp)
    });
  }

  function deposit(IERC20 _token, uint256 _amount) external {
    _accrue(_token);
    _token.safeTransferFrom(msg.sender, address(this), _amount);
  }

  function accrue(IERC20 _token) external returns (uint256) {
    return _accrue(_token);
  }

  function withdraw(IERC20 _token, uint256 _amount) external onlyOwner {
    uint256 availableBalance = _token.balanceOf(address(this));
    uint256 remainingBalance = availableBalance - _amount;
    uint256 availableBoost = boosts[IERC20(_token)].available;
    boosts[IERC20(_token)].available = (availableBoost > remainingBalance ? remainingBalance : availableBoost).toUint112();
    _token.transfer(msg.sender, _amount);
  }

  function liquidatableBalanceOf(address _tokenOut) external override returns (uint256) {
    return _accrue(IERC20(_tokenOut));
  }

  function liquidate(
    address _account,
    address,
    uint256 _amountIn,
    address _tokenOut,
    uint256 _amountOut
  ) external override onlyLiquidationPair(_tokenOut) returns (bool) {
    uint256 amountAvailable = _computeAvailable(IERC20(_tokenOut));
    if (_amountOut > amountAvailable) {
      revert InsufficientAvailableBalance(_amountOut, amountAvailable);
    }
    boosts[IERC20(_tokenOut)].available = (amountAvailable - _amountOut).toUint112();
    boosts[IERC20(_tokenOut)].lastAccruedAt = uint48(block.timestamp);
    prizePool.contributePrizeTokens(vault, _amountIn);
    IERC20(_tokenOut).safeTransfer(_account, _amountOut);

    return true;
  }

  function targetOf(address tokenIn) external view override returns (address) {
    if (IERC20(tokenIn) != prizePool.prizeToken()) {
      revert UnsupportedTokenIn();
    }
    return address(prizePool);
  }

  modifier onlyLiquidationPair(address _token) {
    if (boosts[IERC20(_token)].liquidationPair != msg.sender) {
      revert OnlyLiquidationPair();
    }
    _;
  }

  function _accrue(IERC20 _tokenOut) internal returns (uint256) {
    uint256 available = _computeAvailable(_tokenOut);
    boosts[_tokenOut].available = available.toUint112();
    boosts[_tokenOut].lastAccruedAt = uint48(block.timestamp);
    return available;
  }

  function _computeAvailable(IERC20 _tokenOut) internal view returns (uint256) {
    Boost memory boost = boosts[_tokenOut];
    uint256 deltaTime = block.timestamp - boost.lastAccruedAt;
    uint256 deltaAmount;
    if (boost.tokensPerSecond > 0) {
      deltaAmount = convert(UD60x18.wrap(uint256(boost.tokensPerSecond)).mul(convert(deltaTime)));
    }
    if (boost.multiplierOfTotalSupplyPerSecond > 0) {
      uint256 totalSupply = twabController.getTotalSupplyTwabBetween(address(vault), uint32(boost.lastAccruedAt), uint32(block.timestamp));
      deltaAmount += convert(UD60x18.wrap(uint256(boost.multiplierOfTotalSupplyPerSecond)).mul(convert(deltaTime)).mul(convert(totalSupply)));
    }
    uint256 availableBalance = _tokenOut.balanceOf(address(this));
    deltaAmount = availableBalance > deltaAmount ? deltaAmount : availableBalance;
    return boost.available + deltaAmount;
  }

}
