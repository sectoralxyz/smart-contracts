// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProtocolAuthority} from "../src/ProtocolAuthority.sol";
import {AccountRegistry} from "../src/AccountRegistry.sol";
import {DisclosureLog} from "../src/DisclosureLog.sol";
import {IProtocolAuthority} from "../src/interfaces/IProtocolAuthority.sol";
import {IAccountRegistry} from "../src/interfaces/IAccountRegistry.sol";
import "../src/libraries/ProtocolErrors.sol";

contract DisclosureLogCommitmentTest is Test {
    ProtocolAuthority protocol;
    AccountRegistry registry;
    DisclosureLog disclosures;

    address compliance = makeAddr("compliance");
    address gwen = makeAddr("gwen");

    function setUp() public {
        protocol = new ProtocolAuthority(compliance);
        registry = new AccountRegistry(IProtocolAuthority(address(protocol)));
        disclosures = new DisclosureLog(IAccountRegistry(address(registry)));

        vm.prank(gwen);
        registry.createProfile("gwen", AccountRegistry.AccountKind.Personal);
    }

    function test_receipt_without_a_viewer_is_refused() public {
        vm.expectRevert(MissingCommitment.selector);
        vm.prank(gwen);
        disclosures.file("tx-a", bytes32(0), keccak256("proof"));
    }

    function test_receipt_without_a_payload_hash_is_refused() public {
        vm.expectRevert(MissingCommitment.selector);
        vm.prank(gwen);
        disclosures.file("tx-a", keccak256("auditor"), bytes32(0));
    }

    function test_refused_receipts_leave_no_trace() public {
        vm.prank(gwen);
        try disclosures.file("tx-a", bytes32(0), bytes32(0)) {} catch {}

        assertEq(disclosures.receiptCount(), 0);
        assertEq(disclosures.receiptIdsForTransfer("tx-a").length, 0);
    }
}
