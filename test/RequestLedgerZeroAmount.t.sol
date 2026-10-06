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

contract RequestLedgerZeroAmountTest is Test {
    ProtocolAuthority protocol;
    AccountRegistry registry;
    RequestLedger requests;
    MockERC20 usdg;

    address compliance = makeAddr("compliance");
    address gwen = makeAddr("gwen");
    address felix = makeAddr("felix");

    function setUp() public {
        usdg = new MockERC20("Global Dollar", "USDG", 6);
        protocol = new ProtocolAuthority(compliance);
        registry = new AccountRegistry(IProtocolAuthority(address(protocol)));
        requests = new RequestLedger(
            IProtocolAuthority(address(protocol)), IAccountRegistry(address(registry))
        );

        vm.prank(gwen);
        registry.createProfile("gwen", AccountRegistry.AccountKind.Personal);
    }

    function test_confidential_request_committed_to_zero_cannot_be_settled() public {
        bytes32 blinding = keccak256("blinding");
        bytes32 commitment = keccak256(abi.encodePacked(uint256(0), blinding));

        vm.prank(gwen);
        uint256 id = requests.create(
            gwen,
            address(usdg),
            true,
            0,
            commitment,
            bytes32(0),
            uint64(block.timestamp + 1 hours)
        );

        vm.expectRevert(InvalidSpendAmount.selector);
        vm.prank(felix);
        requests.fulfill(id, 0, blinding);

        assertTrue(requests.isFulfillable(id));
    }

    function test_confidential_request_still_settles_for_its_real_figure() public {
        bytes32 blinding = keccak256("blinding");
        bytes32 commitment = keccak256(abi.encodePacked(uint256(25e6), blinding));

        vm.prank(gwen);
        uint256 id = requests.create(
            gwen,
            address(usdg),
            true,
            0,
            commitment,
            bytes32(0),
            uint64(block.timestamp + 1 hours)
        );

        usdg.mint(felix, 25e6);
        vm.startPrank(felix);
        usdg.approve(address(requests), 25e6);
        requests.fulfill(id, 25e6, blinding);
        vm.stopPrank();

        assertEq(usdg.balanceOf(gwen), 25e6);
    }
}
