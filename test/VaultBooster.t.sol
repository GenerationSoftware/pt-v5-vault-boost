// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";

import { VaultBooster, Boost, UD60x18, UD2x18, OnlyLiquidationPair, UnsupportedTokenIn, InsufficientAvailableBalance, ZeroAmountWithdraw, ZeroAmountDeposit, VaultZeroAddress, OwnerZeroAddress, CannotDepositWithoutBoost, TokenZeroAddress, LiquidationPairZeroAddress, InsufficientAvailableBalance } from "../src/VaultBooster.sol";

import { IFlashSwapCallback } from "pt-v5-liquidator-interfaces/IFlashSwapCallback.sol";
import { PrizePool, TwabController, IERC20 } from "pt-v5-prize-pool/PrizePool.sol";

/// @dev See the "Writing Tests" section in the Foundry Book if this is your first time with Forge.
/// https://book.getfoundry.sh/forge/writing-tests
contract VaultBoosterTest is Test {
  event LiquidationPairSet(address indexed tokenOut, address indexed liquidationPair);

  event SetBoost(
    IERC20 indexed _token,
    address indexed _liquidationPair,
    UD2x18 _multiplierOfTotalSupplyPerSecond,
    uint96 _tokensPerSecond,
    uint144 _initialAvailable,
    uint48 lastAccruedAt
  );

  event Deposited(IERC20 indexed _token, address indexed _from, uint256 _amount);

  event Withdrawn(IERC20 indexed _token, address indexed _from, uint256 _amount);

  event Liquidated(
    IERC20 indexed token,
    address indexed from,
    uint256 amountIn,
    uint256 amountOut,
    uint256 availableBoostBalance
  );

  event BoostAccrued(IERC20 indexed token, uint256 availableBoostBalance);

  VaultBooster booster;

  address liquidationPair;
  address vault;
  PrizePool prizePool;
  TwabController twabController;

  IERC20 boostToken;
  IERC20 prizeToken;

  function setUp() public {
    boostToken = IERC20(makeAddr("boostToken"));
    prizeToken = IERC20(makeAddr("prizeToken"));
    liquidationPair = makeAddr("liquidationPair");
    vault = makeAddr("vault");
    prizePool = PrizePool(makeAddr("prizePool"));
    twabController = TwabController(makeAddr("twabController"));
    vm.mockCall(
      address(prizePool),
      abi.encodeWithSelector(prizePool.twabController.selector),
      abi.encode(twabController)
    );
    vm.mockCall(
      address(prizePool),
      abi.encodeWithSelector(prizePool.prizeToken.selector),
      abi.encode(prizeToken)
    );

    booster = new VaultBooster(prizePool, vault, address(this));
  }

  function testConstructor() public {
    assertEq(address(booster.prizePool()), address(prizePool));
    assertEq(booster.vault(), vault);
    assertEq(address(booster.twabController()), address(twabController));
    assertEq(booster.owner(), address(this));
  }

  function testConstructor_OwnerZeroAddress() public {
    vm.expectRevert(abi.encodeWithSelector(OwnerZeroAddress.selector));
    new VaultBooster(prizePool, vault, address(0));
  }

  function testConstructor_VaultZeroAddress() public {
    vm.expectRevert(abi.encodeWithSelector(VaultZeroAddress.selector));
    new VaultBooster(prizePool, address(0), address(this));
  }

  // should fail since we call a function on the prize pool in the constructor
  function testFailConstructor_PrizePoolZeroAddress() public {
    new VaultBooster(PrizePool(address(0)), vault, address(this));
  }

  function testSetBoost() public {
    vm.expectEmit();
    emit LiquidationPairSet(address(boostToken), address(liquidationPair));
    vm.expectEmit(true, true, true, true);
    emit SetBoost(
      boostToken,
      liquidationPair,
      UD2x18.wrap(0.001e18),
      0.03e18,
      0,
      uint48(block.timestamp)
    );

    booster.setBoost(boostToken, liquidationPair, UD2x18.wrap(0.001e18), 0.03e18, 0);
    Boost memory boost = booster.getBoost(boostToken);
    assertEq(boost.liquidationPair, liquidationPair);
    assertEq(boost.multiplierOfTotalSupplyPerSecond.unwrap(), 0.001e18, "multiplier");
    assertEq(boost.tokensPerSecond, uint96(0.03e18), "tokensPerSecond");
    assertEq(boost.lastAccruedAt, block.timestamp);
  }

  function testSetBoost_available() public {
    vm.mockCall(
      address(boostToken),
      abi.encodeWithSelector(IERC20.balanceOf.selector, address(booster)),
      abi.encode(1e18)
    );
    booster.setBoost(boostToken, liquidationPair, UD2x18.wrap(0.001e18), 0.03e18, 1e18);
    Boost memory boost = booster.getBoost(boostToken);
    assertEq(boost.available, 1e18);
  }

  function testSetBoost_TokenZeroAddress() public {
    vm.expectRevert(abi.encodeWithSelector(TokenZeroAddress.selector));
    booster.setBoost(IERC20(address(0)), liquidationPair, UD2x18.wrap(0.001e18), 0.03e18, 1e18);
  }

  function testSetBoost_LiquidationPairZeroAddress() public {
    vm.expectRevert(abi.encodeWithSelector(LiquidationPairZeroAddress.selector));
    booster.setBoost(IERC20(address(boostToken)), address(0), UD2x18.wrap(0.001e18), 0.03e18, 1e18);
  }

  function testSetBoost_ltAvailable() public {
    mockBoostTokenBalance(0.5e18);
    booster.setBoost(boostToken, liquidationPair, UD2x18.wrap(0.001e18), 0.03e18, 1e18);
    Boost memory boost = booster.getBoost(boostToken);
    assertEq(boost.available, 0.5e18);
  }

  function testIsLiquidationPair() public {
    assertEq(booster.isLiquidationPair(address(boostToken), address(liquidationPair)), false);
    booster.setBoost(boostToken, liquidationPair, UD2x18.wrap(0.001e18), 0.03e18, 0);
    assertEq(booster.isLiquidationPair(address(boostToken), address(liquidationPair)), true);
    assertEq(booster.isLiquidationPair(address(boostToken), address(1)), false);
    assertEq(booster.isLiquidationPair(address(1), address(liquidationPair)), false);
  }

  function testDeposit_success() public {
    mockBoostTokenBalance(1e18);
    booster.setBoost(boostToken, liquidationPair, UD2x18.wrap(0), 0, 1e18);
    vm.mockCall(
      address(boostToken),
      abi.encodeWithSelector(IERC20.transferFrom.selector, address(this), address(booster), 2e18),
      abi.encode(true)
    );
    vm.warp(1 days);

    vm.expectEmit(true, true, true, true);
    emit Deposited(boostToken, address(this), 2e18);

    booster.deposit(boostToken, 2e18);
    Boost memory boost = booster.getBoost(boostToken);
    assertEq(boost.lastAccruedAt, 1 days); // called accrued
  }

  function testDeposit_ZeroAmountDeposit() public {
    mockBoostTokenBalance(1e18);
    booster.setBoost(boostToken, liquidationPair, UD2x18.wrap(0), 0, 1e18);
    vm.mockCall(
      address(boostToken),
      abi.encodeWithSelector(IERC20.transferFrom.selector, address(this), address(booster), 2e18),
      abi.encode(true)
    );
    vm.warp(1 days);

    vm.expectRevert(abi.encodeWithSelector(ZeroAmountDeposit.selector));
    booster.deposit(boostToken, 0); // zero amount
  }

  function testDeposit_CannotDepositWithoutBoost() public {
    vm.expectRevert(abi.encodeWithSelector(CannotDepositWithoutBoost.selector, boostToken));
    booster.deposit(boostToken, 2e18);
  }

  function testAccrue_tokensPerSecond() public {
    vm.warp(0);
    mockBoostTokenBalance(1e18);
    booster.setBoost(boostToken, liquidationPair, UD2x18.wrap(0), 0.1e18, 0);
    vm.warp(10);
    booster.accrue(boostToken);
    Boost memory boost = booster.getBoost(boostToken);
    assertEq(boost.lastAccruedAt, 10); // called accrued
    assertEq(boost.available, 1e18); // 0.1e18 * 10
  }

  function testAccrue_multiplier() public {
    vm.warp(0);
    mockBoostTokenBalance(1e18);
    booster.setBoost(boostToken, liquidationPair, UD2x18.wrap(0.02e18), 0, 0);
    vm.warp(10);
    vm.mockCall(
      address(twabController),
      abi.encodeWithSelector(twabController.getTotalSupplyTwabBetween.selector, vault, 0, 10),
      abi.encode(UD60x18.wrap(5e18))
    );
    booster.accrue(boostToken); // 0.1 * 10 * 5 = 5
    Boost memory boost = booster.getBoost(boostToken);
    assertEq(boost.lastAccruedAt, 10, "last accrued at"); // called accrued
    // 0.02 * 10 * 5e18 = 1e18
    assertEq(boost.available, 1e18, "available"); // 1 wei has acrrue
  }

  function testAccrue_both() public {
    vm.warp(0);
    mockBoostTokenBalance(100e18);
    booster.setBoost(boostToken, liquidationPair, UD2x18.wrap(0.02e18), 1e18, 0);
    vm.warp(10);
    vm.mockCall(
      address(twabController),
      abi.encodeWithSelector(twabController.getTotalSupplyTwabBetween.selector, vault, 0, 10),
      abi.encode(UD60x18.wrap(5e18))
    );

    vm.expectEmit(true, true, true, true);
    emit BoostAccrued(boostToken, 1e18 + 10e18);

    booster.accrue(boostToken);
    Boost memory boost = booster.getBoost(boostToken);
    assertEq(boost.lastAccruedAt, 10, "last accrued at"); // called accrued
    // 1e18 * 10 + 5e18 * 10 * 0.02
    assertEq(boost.available, 1e18 + 10e18, "available");
  }

  function testAccrue_ltBalance() public {
    vm.warp(0);
    mockBoostTokenBalance(1e18);
    booster.setBoost(boostToken, liquidationPair, UD2x18.wrap(0.02e18), 1e18, 0);
    vm.warp(10);
    vm.mockCall(
      address(twabController),
      abi.encodeWithSelector(twabController.getTotalSupplyTwabBetween.selector, vault, 0, 10),
      abi.encode(UD60x18.wrap(5e18))
    );
    booster.accrue(boostToken);
    Boost memory boost = booster.getBoost(boostToken);
    assertEq(boost.lastAccruedAt, 10, "last accrued at"); // called accrued
    assertEq(boost.available, 1e18, "available"); // max 1e18 has accrued
  }

  function testAccrue_reduceAvailable() public {
    vm.warp(0);
    mockBoostTokenBalance(100e18);
    booster.setBoost(boostToken, liquidationPair, UD2x18.wrap(0.02e18), 1e18, 0);
    vm.warp(10);
    vm.mockCall(
      address(twabController),
      abi.encodeWithSelector(twabController.getTotalSupplyTwabBetween.selector, vault, 0, 10),
      abi.encode(UD60x18.wrap(5e18))
    );
    booster.accrue(boostToken); // (0.02 * 5 * 10) + (1 * 10) = 11
    Boost memory boost = booster.getBoost(boostToken);
    assertEq(boost.lastAccruedAt, 10, "last accrued at");
    assertEq(boost.available, 11e18, "available"); // normal amount has accrued

    vm.mockCall(
      address(boostToken),
      abi.encodeWithSelector(boostToken.transfer.selector, address(this), 96e18),
      abi.encode(true)
    );
    booster.withdraw(boostToken, 96e18);

    booster.accrue(boostToken);
    boost = booster.getBoost(boostToken);
    assertEq(boost.available, 4e18, "available"); // reduced
  }

  function testWithdraw() public {
    vm.warp(0);
    booster.setBoost(boostToken, liquidationPair, UD2x18.wrap(0), 1e18, 0);
    mockBoostTokenBalance(1e18);
    vm.warp(10);
    vm.mockCall(
      address(boostToken),
      abi.encodeWithSelector(IERC20.transfer.selector, address(this), 1e18),
      abi.encode(true)
    );
    vm.expectEmit(true, true, true, true);
    emit Withdrawn(boostToken, address(this), 1e18);
    booster.withdraw(boostToken, 1e18);
    Boost memory boost = booster.getBoost(boostToken);
    assertEq(boost.available, 0);
  }

  function testWithdraw_ZeroAmountWithdraw() public {
    vm.warp(0);
    booster.setBoost(boostToken, liquidationPair, UD2x18.wrap(0), 1e18, 0);
    mockBoostTokenBalance(1e18);
    vm.warp(10);
    vm.mockCall(
      address(boostToken),
      abi.encodeWithSelector(IERC20.transfer.selector, address(this), 1e18),
      abi.encode(true)
    );
    vm.expectRevert(abi.encodeWithSelector(ZeroAmountWithdraw.selector));
    booster.withdraw(boostToken, 0); // zero amount
  }

  function testLiquidatableBalanceOf() public {
    vm.warp(0);
    booster.setBoost(boostToken, liquidationPair, UD2x18.wrap(0), 1e18, 0);
    mockBoostTokenBalance(1e18);
    vm.warp(10);
    assertEq(booster.liquidatableBalanceOf(address(boostToken)), 1e18);
  }

  function testTransferTokensOut() public {
    vm.warp(0);
    booster.setBoost(boostToken, liquidationPair, UD2x18.wrap(0), 1e18, 0);
    mockBoostTokenBalance(1e18);
    vm.warp(10);

    vm.mockCall(
      address(boostToken),
      abi.encodeWithSelector(IERC20.transfer.selector, address(this), 1e18),
      abi.encode(true)
    );

    vm.mockCall(
      address(prizePool),
      abi.encodeWithSelector(prizePool.contributePrizeTokens.selector, vault, 9999e18),
      abi.encode(9999e18)
    );

    Boost memory boost = booster.getBoost(boostToken);
    assertEq(boost.available, 1e18); // cleared out

    vm.startPrank(liquidationPair);
    // vm.expectEmit(true, true, true, true);
    // emit Liquidated(boostToken, address(this), 9999e18, 1e18, 0);
    booster.transferTokensOut(address(this), address(this), address(boostToken), 1e18);
    vm.stopPrank();

    boost = booster.getBoost(boostToken);
    assertEq(boost.available, 0); // cleared out
    assertEq(boost.lastAccruedAt, 10); // accrued
  }

  function testTransferTokensOut_InsufficientAvailableBalance() public {
    vm.warp(0);
    booster.setBoost(boostToken, liquidationPair, UD2x18.wrap(0), 1e18, 0);
    mockBoostTokenBalance(1e18);
    vm.warp(10);

    vm.startPrank(liquidationPair);
    vm.expectRevert(abi.encodeWithSelector(InsufficientAvailableBalance.selector, 1000e18, 1e18));
    booster.transferTokensOut(address(this), address(this), address(boostToken), 1000e18);
    vm.stopPrank();
  }

  function testTransferTokensOut_onlyLiquidationPair() public {
    vm.warp(0);
    booster.setBoost(boostToken, liquidationPair, UD2x18.wrap(0), 1e18, 0);
    mockBoostTokenBalance(1e18);
    vm.warp(10);

    vm.expectRevert(abi.encodeWithSelector(OnlyLiquidationPair.selector));
    booster.transferTokensOut(address(this), address(this), address(boostToken), 1000e18);
  }

  function testVerifyTokensIn() public {
    vm.mockCall(
      address(prizePool),
      abi.encodeCall(prizePool.contributePrizeTokens, (address(vault), 1000e18)),
      abi.encode(0)
    );

    booster.setBoost(boostToken, liquidationPair, UD2x18.wrap(0), 1e18, 0);

    vm.startPrank(liquidationPair);
    booster.verifyTokensIn(address(prizeToken), 1000e18, abi.encode(boostToken));
    vm.stopPrank();
  }

  function testVerifyTokensIn_OnlyLiquidationPair() public {
    booster.setBoost(boostToken, liquidationPair, UD2x18.wrap(0), 1e18, 0);
    vm.expectRevert(abi.encodeWithSelector(OnlyLiquidationPair.selector));
    booster.verifyTokensIn(address(prizeToken), 1000e18, abi.encode(boostToken));
  }

  function testTargetOf() public {
    assertEq(booster.targetOf(address(prizeToken)), address(prizePool));
  }

  function testTargetOf_unknownToken() public {
    vm.expectRevert(abi.encodeWithSelector(UnsupportedTokenIn.selector));
    booster.targetOf(address(boostToken));
  }

  /** =========== MOCKS ============= */

  function mockBoostTokenBalance(uint256 _balance) public {
    vm.mockCall(
      address(boostToken),
      abi.encodeWithSelector(IERC20.balanceOf.selector, address(booster)),
      abi.encode(_balance)
    );
  }
}
