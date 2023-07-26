// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { Foo } from "../src/Foo.sol";

interface IERC20 {
  function balanceOf(address account) external view returns (uint256);
}

/// @dev See the "Writing Tests" section in the Foundry Book if this is your first time with Forge.
/// https://book.getfoundry.sh/forge/writing-tests
contract FooTest is Test {

  function setUp() public {
  }

}
