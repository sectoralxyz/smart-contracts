// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {FeeSchedule} from "../src/fees/FeeSchedule.sol";
import "../src/libraries/ProtocolErrors.sol";

contract FeeScheduleCeilingTest is Test {
    FeeSchedule fees;
    address admin = makeAddr("admin");

    function setUp() public {
        fees = new FeeSchedule(admin);
    }

    function test_rate_can_be_set_up_to_the_ceiling() public {
        vm.prank(admin);
        fees.setSchedule(100, 5_000_000);
        assertEq(fees.baseFeeBps(), 100);
    }

    function test_rate_above_the_ceiling_is_refused() public {
        vm.expectRevert(InvalidFeeConfig.selector);
        vm.prank(admin);
        fees.setSchedule(101, 5_000_000);

        // A slipped digit on the default rate.
        vm.expectRevert(InvalidFeeConfig.selector);
        vm.prank(admin);
        fees.setSchedule(1_000, 5_000_000);

        assertEq(fees.baseFeeBps(), 10);
    }
}
