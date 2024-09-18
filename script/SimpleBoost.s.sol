// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import { ILiquidationPair } from "pt-v5-liquidator-interfaces/ILiquidationPair.sol";
import { VaultBoosterFactory, PrizePool } from "../src/VaultBoosterFactory.sol";
import { VaultBooster, UD2x18 } from "../src/VaultBooster.sol";
import { IERC20, IERC20Metadata } from "openzeppelin/interfaces/IERC20Metadata.sol"; 

interface ILPFactory {
  function createPair(
    address source,
    address tokenIn,
    address tokenOut,
    uint64 targetAuctionPeriod,
    uint192 targetAuctionPrice,
    uint256 smoothingFactor
  ) external returns (address);
}

contract SimpleBoost is Script {

  address public prizePool;
  address public boostToken;
  address public boostTarget;
  address public boostFactory;
  address public lpFactory;
  uint256 public amount;
  uint256 public duration;
  bool public makeDeposit;
  uint256 public targetAuctionPriceWeth;

  function run() external {

    // Load ENV
    {
      prizePool = vm.envAddress("BOOST_PRIZE_POOL");
      boostToken = vm.envAddress("BOOST_TOKEN");
      boostTarget = vm.envAddress("BOOST_TARGET");
      boostFactory = vm.envAddress("BOOST_FACTORY");
      lpFactory = vm.envAddress("BOOST_LP_FACTORY");
      amount = vm.envUint("BOOST_AMOUNT");
      duration = vm.envUint("BOOST_DURATION");
      makeDeposit = vm.envBool("BOOST_MAKE_DEPOSIT");
    }
    uint256 targetAuctionPeriod = PrizePool(prizePool).drawPeriodSeconds();
    address prizeToken = address(PrizePool(prizePool).prizeToken());
    string memory prizeTokenSymbol = IERC20Metadata(prizeToken).symbol();
    if (keccak256(abi.encode(prizeTokenSymbol)) == keccak256(abi.encode("WETH"))) {
      targetAuctionPriceWeth = uint256(1e15);
    } else if (keccak256(abi.encode(prizeTokenSymbol)) == keccak256(abi.encode("WXDAI"))) {
      targetAuctionPriceWeth = uint256(1e18);
    } else {
      revert("script is currently set up to only handle boosts on WETH or WXDAI prize pools");
    }

    vm.startBroadcast();

    // Create vault booster
    VaultBooster booster = VaultBoosterFactory(boostFactory).createVaultBooster(
      PrizePool(prizePool),
      boostTarget,
      msg.sender
    );

    // Create booster LP
    address lp = ILPFactory(lpFactory).createPair(
      address(booster),
      prizeToken,
      boostToken,
      uint64(targetAuctionPeriod),
      uint192(targetAuctionPriceWeth),
      0
    );

    // Set up boost
    booster.setBoost(
      IERC20(boostToken),
      lp,
      UD2x18.wrap(0),
      uint96(amount / duration),
      0
    );

    if (makeDeposit) {
      // Approve tokens
      IERC20(boostToken).approve(address(booster), amount);

      // Deposit tokens
      booster.deposit(IERC20(boostToken), amount);
    }

    vm.stopBroadcast();
  }

}