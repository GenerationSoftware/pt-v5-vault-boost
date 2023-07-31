// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {
  VaultBoosterFactory,
  VaultBooster
} from "../src/VaultBoosterFactory.sol";

import { PrizePool, TwabController, IERC20 } from "pt-v5-prize-pool/PrizePool.sol";

/// @dev See the "Writing Tests" section in the Foundry Book if this is your first time with Forge.
/// https://book.getfoundry.sh/forge/writing-tests
contract VaultBoosterTest is Test {

  event CreatedVaultBooster(
    VaultBooster indexed vaultBooster,
    PrizePool indexed _prizePool,
    address indexed _vault,
    address _owner
  );

  VaultBoosterFactory factory;

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
    vm.mockCall(address(prizePool), abi.encodeWithSelector(prizePool.twabController.selector), abi.encode(twabController));
    vm.mockCall(address(prizePool), abi.encodeWithSelector(prizePool.prizeToken.selector), abi.encode(prizeToken));

    factory = new VaultBoosterFactory();
  }

  function testCreateVaultBooster() public {
    vm.expectEmit(false, true, true, false);
    emit CreatedVaultBooster(
        VaultBooster(address(0xdeadbeef)),
        prizePool,
        vault,
        address(this)
    );
    VaultBooster booster = factory.createVaultBooster(prizePool, vault, address(this));
    assertEq(address(booster.prizePool()), address(prizePool));
    assertEq(booster.vault(), vault);
    assertEq(booster.owner(), address(this));
  }

}
