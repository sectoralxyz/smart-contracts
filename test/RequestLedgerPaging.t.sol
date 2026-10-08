// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProtocolAuthority} from "../src/ProtocolAuthority.sol";
import {AccountRegistry} from "../src/AccountRegistry.sol";
import {RequestLedger} from "../src/RequestLedger.sol";
import {IProtocolAuthority} from "../src/interfaces/IProtocolAuthority.sol";
import {IAccountRegistry} from "../src/interfaces/IAccountRegistry.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract RequestLedgerPagingTest is Test {
    RequestLedger requests;
    MockERC20 usdg;

    address compliance = makeAddr("compliance");
    address gwen = makeAddr("gwen");

    function setUp() public {
        usdg = new MockERC20("Global Dollar", "USDG", 6);
        ProtocolAuthority protocol = new ProtocolAuthority(compliance);
        AccountRegistry registry = new AccountRegistry(IProtocolAuthority(address(protocol)));
        requests = new RequestLedger(
            IProtocolAuthority(address(protocol)), IAccountRegistry(address(registry))
        );

        vm.prank(gwen);
        registry.createProfile("gwen", AccountRegistry.AccountKind.Personal);

        vm.startPrank(gwen);
        for (uint256 i; i < 3; ++i) {
            requests.create(
                gwen,
                address(usdg),
                false,
                25e6,
                bytes32(0),
                bytes32(0),
                uint64(block.timestamp + 1 hours)
            );
        }
        vm.stopPrank();
    }

    function test_max_limit_returns_the_rest_of_the_list() public view {
        uint256[] memory page = requests.requestIdsOf(gwen, 1, type(uint256).max);
        assertEq(page.length, 2);
        assertEq(page[0], 2);
        assertEq(page[1], 3);
    }

    function test_ordinary_pages_are_unchanged() public view {
        assertEq(requests.requestIdsOf(gwen, 0, 2).length, 2);
        assertEq(requests.requestIdsOf(gwen, 2, 2).length, 1);
        assertEq(requests.requestIdsOf(gwen, 3, 2).length, 0);
    }
}
