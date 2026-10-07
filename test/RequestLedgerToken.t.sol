// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProtocolAuthority} from "../src/ProtocolAuthority.sol";
import {AccountRegistry} from "../src/AccountRegistry.sol";
import {RequestLedger} from "../src/RequestLedger.sol";
import {IProtocolAuthority} from "../src/interfaces/IProtocolAuthority.sol";
import {IAccountRegistry} from "../src/interfaces/IAccountRegistry.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import "../src/libraries/ProtocolErrors.sol";

contract RequestLedgerTokenTest is Test {
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
    }

    function test_request_for_a_token_with_no_code_reverts() public {
        vm.expectRevert(InvalidToken.selector);
        vm.prank(gwen);
        requests.create(
            gwen,
            makeAddr("wallet"),
            false,
            25e6,
            bytes32(0),
            bytes32(0),
            uint64(block.timestamp + 1 hours)
        );

        assertEq(requests.requestCount(), 0);
    }

    function test_request_for_a_real_token_still_works() public {
        vm.prank(gwen);
        uint256 id = requests.create(
            gwen,
            address(usdg),
            false,
            25e6,
            bytes32(0),
            bytes32(0),
            uint64(block.timestamp + 1 hours)
        );

        assertTrue(requests.isFulfillable(id));
    }
}
