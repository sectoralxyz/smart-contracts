// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProtocolAuthority} from "../src/ProtocolAuthority.sol";
import {AccountRegistry} from "../src/AccountRegistry.sol";
import {DisclosureLog} from "../src/DisclosureLog.sol";
import {IProtocolAuthority} from "../src/interfaces/IProtocolAuthority.sol";
import {IAccountRegistry} from "../src/interfaces/IAccountRegistry.sol";

contract DisclosureLogPagingTest is Test {
    DisclosureLog disclosures;

    address compliance = makeAddr("compliance");
    address gwen = makeAddr("gwen");

    function setUp() public {
        ProtocolAuthority protocol = new ProtocolAuthority(compliance);
        AccountRegistry registry = new AccountRegistry(IProtocolAuthority(address(protocol)));
        disclosures = new DisclosureLog(IAccountRegistry(address(registry)));

        vm.prank(gwen);
        registry.createProfile("gwen", AccountRegistry.AccountKind.Personal);

        vm.startPrank(gwen);
        disclosures.file("tx-a", keccak256("auditor"), keccak256("proof-a"));
        disclosures.file("tx-b", keccak256("auditor"), keccak256("proof-b"));
        disclosures.file("tx-c", keccak256("auditor"), keccak256("proof-c"));
        vm.stopPrank();
    }

    function test_max_limit_returns_the_rest_of_the_list() public view {
        uint256[] memory page = disclosures.receiptIdsOf(gwen, 1, type(uint256).max);
        assertEq(page.length, 2);
        assertEq(page[0], 2);
        assertEq(page[1], 3);
    }

    function test_ordinary_pages_are_unchanged() public view {
        assertEq(disclosures.receiptIdsOf(gwen, 0, 2).length, 2);
        assertEq(disclosures.receiptIdsOf(gwen, 2, 2).length, 1);
        assertEq(disclosures.receiptIdsOf(gwen, 3, 2).length, 0);
    }
}
