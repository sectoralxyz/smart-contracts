// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ConfidentialToken} from "../src/confidential/ConfidentialToken.sol";
import {StubTransferVerifier} from "../src/confidential/StubTransferVerifier.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract ConfidentialTokenPauseUnchangedTest is Test {
    ConfidentialToken confidential;
    address admin = makeAddr("admin");

    function setUp() public {
        MockERC20 usdg = new MockERC20("Global Dollar", "USDG", 6);
        confidential =
            new ConfidentialToken(IERC20(address(usdg)), new StubTransferVerifier(), admin);
    }

    function test_unpausing_a_running_layer_reverts() public {
        vm.expectRevert(ConfidentialToken.PauseUnchanged.selector);
        vm.prank(admin);
        confidential.setPaused(false);
    }

    function test_pausing_twice_reverts() public {
        vm.startPrank(admin);
        confidential.setPaused(true);
        vm.expectRevert(ConfidentialToken.PauseUnchanged.selector);
        confidential.setPaused(true);
        vm.stopPrank();

        assertTrue(confidential.paused());
    }
}
