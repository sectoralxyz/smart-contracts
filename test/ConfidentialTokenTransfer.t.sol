// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {AltBn128} from "../src/confidential/AltBn128.sol";
import {ConfidentialToken} from "../src/confidential/ConfidentialToken.sol";
import {StubTransferVerifier} from "../src/confidential/StubTransferVerifier.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import "../src/libraries/ProtocolErrors.sol";

contract ConfidentialTokenTransferTest is Test {
    ConfidentialToken confidential;
    MockERC20 usdg;

    address admin = makeAddr("admin");
    address felix = makeAddr("felix");
    address gwen = makeAddr("gwen");

    function pk(uint256 k) internal view returns (uint256 x, uint256 y) {
        AltBn128.Point memory p = AltBn128.encode(k);
        return (p.x, p.y);
    }

    function setUp() public {
        usdg = new MockERC20("Global Dollar", "USDG", 6);
        confidential =
            new ConfidentialToken(IERC20(address(usdg)), new StubTransferVerifier(), admin);

        usdg.mint(felix, 1_000e6);

        (uint256 fx, uint256 fy) = pk(2);
        (uint256 gx, uint256 gy) = pk(3);

        vm.startPrank(felix);
        confidential.register(fx, fy);
        usdg.approve(address(confidential), type(uint256).max);
        confidential.deposit(100e6);
        vm.stopPrank();

        vm.prank(gwen);
        confidential.register(gx, gy);
    }

    function test_transfer_to_self_reverts_with_its_own_error() public {
        uint256[] memory signals = new uint256[](0);
        ConfidentialToken.Ciphertext memory delta = confidential.encryptedBalanceOf(gwen);

        vm.expectRevert(ConfidentialToken.SelfTransfer.selector);
        vm.prank(felix);
        confidential.confidentialTransfer(felix, delta, delta, "", signals);
    }

    function test_transfer_to_unregistered_account_reverts() public {
        uint256[] memory signals = new uint256[](0);
        ConfidentialToken.Ciphertext memory delta = confidential.encryptedBalanceOf(gwen);

        vm.expectRevert(AccountNotRegistered.selector);
        vm.prank(felix);
        confidential.confidentialTransfer(makeAddr("nobody"), delta, delta, "", signals);
    }

    function test_pool_reports_backing_through_wraps_and_unwraps() public {
        assertTrue(confidential.isFullyBacked());

        uint256[] memory signals = new uint256[](0);
        vm.prank(felix);
        confidential.withdraw(40e6, "", signals);
        assertTrue(confidential.isFullyBacked());

        // A stray direct transfer overfunds the pool, which still counts.
        usdg.mint(address(confidential), 1e6);
        assertTrue(confidential.isFullyBacked());
    }
}
