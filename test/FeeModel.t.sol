// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProtocolAuthority} from "../src/ProtocolAuthority.sol";
import {AccountRegistry} from "../src/AccountRegistry.sol";
import {AgentController} from "../src/AgentController.sol";
import {RequestLedger} from "../src/RequestLedger.sol";
import {FeeSchedule} from "../src/fees/FeeSchedule.sol";
import {IProtocolAuthority} from "../src/interfaces/IProtocolAuthority.sol";
import {IAccountRegistry} from "../src/interfaces/IAccountRegistry.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @notice Drives the whole fee model from one end to the other: the
///         arithmetic behind a quote and the routing of fees through both
///         settlement paths.
contract FeeModelTest is Test {
    ProtocolAuthority protocol;
    AccountRegistry registry;
    AgentController agents;
    RequestLedger requests;
    FeeSchedule fees;
    MockERC20 usdg; // 6 dp settlement token

    address admin = makeAddr("admin");
    address compliance = makeAddr("compliance");
    address treasury = makeAddr("treasury");
    address gwen = makeAddr("gwen");
    address felix = makeAddr("felix");
    address vendor = makeAddr("vendor");
    address signer = makeAddr("signer");

    function usd(uint256 d) internal pure returns (uint256) {
        return d * 1e6;
    }

    function setUp() public {
        usdg = new MockERC20("Global Dollar", "USDG", 6);

        vm.prank(admin);
        protocol = new ProtocolAuthority(compliance);
        registry = new AccountRegistry(IProtocolAuthority(address(protocol)));
        agents = new AgentController(
            IProtocolAuthority(address(protocol)), IAccountRegistry(address(registry))
        );
        requests = new RequestLedger(
            IProtocolAuthority(address(protocol)), IAccountRegistry(address(registry))
        );

        fees = new FeeSchedule(admin);

        vm.prank(admin);
        protocol.setFeeConfig(treasury, address(fees));

        vm.prank(gwen);
        registry.createProfile("gwen", AccountRegistry.AccountKind.Personal);
        vm.prank(felix);
        registry.createProfile("felix", AccountRegistry.AccountKind.Personal);

        usdg.mint(gwen, usd(1_000_000));
        usdg.mint(felix, usd(1_000_000));
    }

    // ── Quoting ────────────────────────────────────────────────────────────────

    function test_base_fee() public view {
        // A tenth of a percent on 1,000 USDG is 1 USDG.
        (uint256 fee, uint256 bps) = fees.quoteFee(gwen, usd(1_000));
        assertEq(fee, usd(1));
        assertEq(bps, 10);
    }

    function test_fee_capped_at_five_usdg() public view {
        // 0.10% of 100,000 USDG is 100 USDG, which the 5 USDG ceiling clips.
        (uint256 fee, uint256 bps) = fees.quoteFee(gwen, usd(100_000));
        assertEq(fee, usd(5));
        assertEq(bps, 0); // 5 / 100,000 rounds below a whole basis point
    }

    function test_every_payer_pays_the_same_rate() public view {
        (uint256 gwenFee,) = fees.quoteFee(gwen, usd(2_500));
        (uint256 felixFee,) = fees.quoteFee(felix, usd(2_500));
        assertEq(gwenFee, felixFee);
    }

    function test_zero_amount_quotes_nothing() public view {
        (uint256 fee, uint256 bps) = fees.quoteFee(gwen, 0);
        assertEq(fee, 0);
        assertEq(bps, 0);
    }

    // ── Fee routing through settlement ─────────────────────────────────────────

    function _fundedAgent() internal returns (uint256 agentId) {
        address[] memory none = new address[](0);
        vm.prank(gwen);
        agentId = agents.createAgent(
            signer,
            "bot",
            AgentController.AutonomyTier.SemiAutonomous,
            address(usdg),
            usd(2_000),
            usd(10_000),
            usd(2_000),
            none,
            false
        );
        vm.startPrank(gwen);
        usdg.approve(address(agents), type(uint256).max);
        agents.fundAgent(agentId, usd(5_000));
        vm.stopPrank();
    }

    function test_agent_pay_charges_fee_to_treasury() public {
        uint256 agentId = _fundedAgent();

        // On 1,000 USDG the fee is 1 USDG, drawn from the same vault.
        vm.prank(signer);
        agents.payInvoice(agentId, vendor, usd(1_000), bytes32("inv"));

        uint256 expectedFee = usd(1);
        assertEq(usdg.balanceOf(vendor), usd(1_000)); // recipient kept whole
        assertEq(usdg.balanceOf(treasury), expectedFee); // fee to treasury
        assertEq(agents.vaultBalance(agentId), usd(5_000) - usd(1_000) - expectedFee);
    }

    function test_agent_pay_no_fee_when_unconfigured() public {
        // Unwire the routing and settlement is an ordinary transfer once more.
        vm.prank(admin);
        protocol.setFeeConfig(address(0), address(0));

        uint256 agentId = _fundedAgent();
        vm.prank(signer);
        agents.payInvoice(agentId, vendor, usd(1_000), bytes32("inv"));

        assertEq(usdg.balanceOf(vendor), usd(1_000));
        assertEq(usdg.balanceOf(treasury), 0);
        assertEq(agents.vaultBalance(agentId), usd(5_000) - usd(1_000));
    }

    function test_payment_request_charges_fee_on_top() public {
        // gwen asks for 500 USDG; felix covers it and the fee.
        vm.prank(gwen);
        uint256 id = requests.create(
            gwen,
            address(usdg),
            false,
            usd(500),
            bytes32(0),
            bytes32(0),
            uint64(block.timestamp + 1 days)
        );

        uint256 gwenBefore = usdg.balanceOf(gwen);
        uint256 felixBefore = usdg.balanceOf(felix);

        vm.startPrank(felix);
        usdg.approve(address(requests), type(uint256).max);
        requests.fulfill(id, usd(500), bytes32(0));
        vm.stopPrank();

        uint256 fee = usd(500) * 10 / 10_000; // 0.10% = 0.5 USDG
        assertEq(usdg.balanceOf(gwen), gwenBefore + usd(500)); // requester whole
        assertEq(usdg.balanceOf(treasury), fee);
        assertEq(usdg.balanceOf(felix), felixBefore - usd(500) - fee); // payer pays fee
    }

    function test_only_authority_tunes_schedule() public {
        vm.expectRevert();
        vm.prank(gwen);
        fees.setSchedule(20, usd(10));

        vm.prank(admin);
        fees.setSchedule(20, usd(10));
        assertEq(fees.baseFeeBps(), 20);
        assertEq(fees.feeCap(), usd(10));
    }
}
