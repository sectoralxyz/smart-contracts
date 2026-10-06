// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {AltBn128} from "../src/confidential/AltBn128.sol";
import {ConfidentialToken} from "../src/confidential/ConfidentialToken.sol";
import {StubTransferVerifier} from "../src/confidential/StubTransferVerifier.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {MockZeroTransferERC20} from "./mocks/MockZeroTransferERC20.sol";
import "../src/libraries/ProtocolErrors.sol";

contract ConfidentialTokenDepositTest is Test {
    ConfidentialToken confidential;
    MockZeroTransferERC20 token;

    address admin = makeAddr("admin");
    address felix = makeAddr("felix");

    function setUp() public {
        token = new MockZeroTransferERC20();
        confidential =
            new ConfidentialToken(IERC20(address(token)), new StubTransferVerifier(), admin);

        AltBn128.Point memory pk = AltBn128.encode(2);
        vm.prank(felix);
        confidential.register(pk.x, pk.y);
    }

    function test_deposit_that_delivers_nothing_reverts() public {
        vm.expectRevert(InvalidSpendAmount.selector);
        vm.prank(felix);
        confidential.deposit(10e6);

        assertEq(confidential.totalWrapped(), 0);
    }
}
