// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProtocolAuthority} from "../src/ProtocolAuthority.sol";
import {AccountRegistry} from "../src/AccountRegistry.sol";
import {IProtocolAuthority} from "../src/interfaces/IProtocolAuthority.sol";
import {IAccountRegistry} from "../src/interfaces/IAccountRegistry.sol";

contract AccountKycTierTest is Test {
    ProtocolAuthority protocol;
    AccountRegistry registry;

    address compliance = makeAddr("compliance");
    address gwen = makeAddr("gwen");

    function setUp() public {
        protocol = new ProtocolAuthority(compliance);
        registry = new AccountRegistry(IProtocolAuthority(address(protocol)));

        vm.prank(gwen);
        registry.createProfile("gwen", AccountRegistry.AccountKind.Personal);
    }

    function test_recording_the_current_tier_again_reverts() public {
        vm.prank(compliance);
        registry.setKycTier(gwen, IAccountRegistry.KycTier.Basic);

        vm.warp(block.timestamp + 1 days);
        vm.expectRevert(AccountRegistry.SameKycTier.selector);
        vm.prank(compliance);
        registry.setKycTier(gwen, IAccountRegistry.KycTier.Basic);
    }

    function test_new_accounts_cannot_be_set_to_unverified_again() public {
        vm.expectRevert(AccountRegistry.SameKycTier.selector);
        vm.prank(compliance);
        registry.setKycTier(gwen, IAccountRegistry.KycTier.Unverified);
    }

    function test_a_real_change_still_goes_through() public {
        vm.startPrank(compliance);
        registry.setKycTier(gwen, IAccountRegistry.KycTier.Basic);
        registry.setKycTier(gwen, IAccountRegistry.KycTier.Enhanced);
        vm.stopPrank();

        assertEq(uint8(registry.kycTierOf(gwen)), uint8(IAccountRegistry.KycTier.Enhanced));
    }
}
