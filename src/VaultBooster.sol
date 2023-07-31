// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "forge-std/console2.sol";

import { ILiquidationSource } from "pt-v5-liquidator-interfaces/interfaces/ILiquidationSource.sol";
import { PrizePool, IERC20, TwabController } from "pt-v5-prize-pool/PrizePool.sol";
import { UD60x18, convert } from "prb-math/UD60x18.sol";
import { UD2x18, intoUD60x18 } from "prb-math/UD2x18.sol";
import { Ownable } from "openzeppelin/access/Ownable.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";

error OnlyLiquidationPair();
error InitialAvailableExceedsBalance(uint144 initialAvailable, uint256 balance);
error InsufficientAvailableBalance(uint256 amountOut, uint256 available);
error UnsupportedTokenIn();

struct Boost {
  address liquidationPair;
  UD2x18 multiplierOfTotalSupplyPerSecond;
  uint96 tokensPerSecond;
  uint144 available;
  uint48 lastAccruedAt;
}

contract VaultBooster is Ownable, ILiquidationSource {
  using SafeERC20 for IERC20;
  using SafeCast for uint256;

  event SetBoost(
    IERC20 indexed token,
    address liquidationPair,
    UD2x18 multiplierOfTotalSupplyPerSecond,
    uint96 tokensPerSecond,
    uint144 initialAvailable,
    uint48 lastAccruedAt
  );

  event Deposited(
    IERC20 indexed token,
    address indexed from,
    uint256 amount
  );

  event Withdrawn(
    IERC20 indexed token,
    address indexed from,
    uint256 amount
  );

  event Liquidated(
    IERC20 indexed token,
    address indexed from,
    uint256 amountIn,
    uint256 amountOut,
    uint256 available
  );

  event BoostAccrued(
    uint256 available
  );

  PrizePool public immutable prizePool;
  TwabController public immutable twabController;
  address public immutable vault;

  mapping(IERC20 => Boost) internal _boosts;

  constructor(
    PrizePool _prizePool,
    address _vault,
    address _owner
  ) Ownable(_owner) {
    prizePool = _prizePool;
    twabController = prizePool.twabController();
    vault = _vault;
  }

  function getBoost(IERC20 _token) external returns (Boost memory) {
    _accrue(_token);
    return _boosts[_token];
  }

  function setBoost(IERC20 _token, address _liquidationPair, UD2x18 _multiplierOfTotalSupplyPerSecond, uint96 _tokensPerSecond, uint144 _initialAvailable) external onlyOwner {
    if (_initialAvailable > 0) {
      uint256 balance = _token.balanceOf(address(this));
      if (balance < _initialAvailable) {
        revert InitialAvailableExceedsBalance(_initialAvailable, balance);
      }
    }
    _boosts[_token] = Boost({
      liquidationPair: _liquidationPair,
      multiplierOfTotalSupplyPerSecond: _multiplierOfTotalSupplyPerSecond,
      tokensPerSecond: _tokensPerSecond,
      available: _initialAvailable,
      lastAccruedAt: uint48(block.timestamp)
    });

    emit SetBoost(
      _token,
      _liquidationPair,
      _multiplierOfTotalSupplyPerSecond,
      _tokensPerSecond,
      _initialAvailable,
      uint48(block.timestamp)
    );
  }

  function deposit(IERC20 _token, uint256 _amount) external {
    _accrue(_token);
    _token.safeTransferFrom(msg.sender, address(this), _amount);

    emit Deposited(_token, msg.sender, _amount);
  }

  function accrue(IERC20 _token) external returns (uint256) {
    return _accrue(_token);
  }

  function withdraw(IERC20 _token, uint256 _amount) external onlyOwner {
    uint256 availableBoost = _accrue(_token);
    uint256 availableBalance = _token.balanceOf(address(this));
    uint256 remainingBalance = availableBalance - _amount;
    _boosts[IERC20(_token)].available = (availableBoost > remainingBalance ? remainingBalance : availableBoost).toUint144();
    _token.transfer(msg.sender, _amount);

    emit Withdrawn(_token, msg.sender, _amount);
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
    amountAvailable = (amountAvailable - _amountOut);
    _boosts[IERC20(_tokenOut)].available = amountAvailable.toUint144();
    _boosts[IERC20(_tokenOut)].lastAccruedAt = uint48(block.timestamp);
    prizePool.contributePrizeTokens(vault, _amountIn);
    IERC20(_tokenOut).safeTransfer(_account, _amountOut);

    emit Liquidated(
      IERC20(_tokenOut),
      _account,
      _amountIn,
      _amountOut,
      amountAvailable
    );

    return true;
  }

  function targetOf(address tokenIn) external view override returns (address) {
    if (IERC20(tokenIn) != prizePool.prizeToken()) {
      revert UnsupportedTokenIn();
    }
    return address(prizePool);
  }

  modifier onlyLiquidationPair(address _token) {
    if (_boosts[IERC20(_token)].liquidationPair != msg.sender) {
      revert OnlyLiquidationPair();
    }
    _;
  }

  function _accrue(IERC20 _tokenOut) internal returns (uint256) {
    uint256 available = _computeAvailable(_tokenOut);
    _boosts[_tokenOut].available = available.toUint144();
    _boosts[_tokenOut].lastAccruedAt = uint48(block.timestamp);

    emit BoostAccrued(available);

    return available;
  }

  function _computeAvailable(IERC20 _tokenOut) internal view returns (uint256) {
    Boost memory boost = _boosts[_tokenOut];
    uint256 deltaTime = block.timestamp - boost.lastAccruedAt;
    uint256 deltaAmount;
    if (deltaTime == 0) {
      return boost.available;
    }
    if (boost.tokensPerSecond > 0) {
      deltaAmount = boost.tokensPerSecond * deltaTime;
    }
    if (boost.multiplierOfTotalSupplyPerSecond.unwrap() > 0) {
      uint256 totalSupply = twabController.getTotalSupplyTwabBetween(address(vault), uint32(boost.lastAccruedAt), uint32(block.timestamp));
      deltaAmount += convert(boost.multiplierOfTotalSupplyPerSecond.intoUD60x18().mul(convert(deltaTime)).mul(convert(totalSupply)));
    }
    uint256 availableBalance = _tokenOut.balanceOf(address(this));
    deltaAmount = availableBalance > deltaAmount ? deltaAmount : availableBalance;
    return boost.available + deltaAmount;
  }

}
