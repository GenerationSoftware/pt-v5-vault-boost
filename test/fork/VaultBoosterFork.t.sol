// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";

import {
    VaultBooster,
    Boost,
    UD60x18,
    UD2x18,
    OnlyLiquidationPair,
    UnsupportedTokenIn,
    InsufficientAvailableBalance,
    ZeroAmountWithdraw,
    ZeroAmountDeposit,
    VaultZeroAddress,
    OwnerZeroAddress,
    CannotDepositWithoutBoost,
    TokenZeroAddress,
    LiquidationPairZeroAddress,
    InsufficientAvailableBalance
} from "../../src/VaultBooster.sol";

import { IFlashSwapCallback } from "pt-v5-liquidator-interfaces/IFlashSwapCallback.sol";
import { PrizePool, TwabController, IERC20 } from "pt-v5-prize-pool/PrizePool.sol";
import { IERC4626 } from "openzeppelin/interfaces/IERC4626.sol";

/// @dev See the "Writing Tests" section in the Foundry Book if this is your first time with Forge.
/// https://book.getfoundry.sh/forge/writing-tests
contract VaultBoosterForkTest is Test {

    uint256 public fork;
    uint256 public forkBlock = 11619108;

    PrizePool public prizePool = PrizePool(0x99ffb0A6c0CD543861c8dE84dd40E059FD867dcF);
    IERC4626 public vault = IERC4626(0x8aD5959c9245b64173D4C0C3CD3ff66dAc3caB0E);
    IERC4626 public poolVault = IERC4626(0x0045cC66eCf34da9D8D89aD5b36cB82061c0907C);
    IERC20 public wld = IERC20(0x2cFc85d8E48F8EAB294be644d9E25C3030863003);
    IERC20 public pool = IERC20(0x7077C71B4AF70737a08287E279B717Dcf64fdC57);

    VaultBooster public vaultBooster;

    VaultBooster public oldVaultBooster = VaultBooster(0x2b6f1A0d569dA91F09AfF8e9303BaBdd2715b2C0);

    function setUp() public {
        fork = vm.createFork("world", forkBlock);
        vm.selectFork(fork);

        // make it the poolvault so that we can deposit (world id)
        vaultBooster = new VaultBooster(prizePool, address(poolVault), address(this));
    }

    function testApr() public {
        deal(address(wld), address(this), 1000000e18);
        deal(address(pool), address(this), 1000000e18);

        vaultBooster.setBoost(
            wld,
            address(this),
            UD2x18.wrap(1000000000000),
            0,
            0
        );

        vm.warp(block.timestamp + 1 days);
        assertEq(vaultBooster.accrue(wld), 0);

        vm.warp(block.timestamp + 1 days);
        wld.approve(address(vaultBooster), 100e18);
        vaultBooster.deposit(wld, 100e18);

        assertEq(vaultBooster.accrue(wld), 0);

        pool.approve(address(poolVault), 100e18);
        poolVault.deposit(100e18, address(this));

        vm.warp(block.timestamp + 1 days);

        assertEq(vaultBooster.accrue(wld), 8.534499999999999999e18);

        vaultBooster.updateBoostRates(
            wld,
            UD2x18.wrap(6342000000),
            0
        );

        vm.warp(block.timestamp + 365 days);

        assertEq(vaultBooster.accrue(wld), 28.534631199999999999e18);

    }
}
