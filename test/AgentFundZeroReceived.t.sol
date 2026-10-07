// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProtocolAuthority} from "../src/ProtocolAuthority.sol";
import {AccountRegistry} from "../src/AccountRegistry.sol";
import {AgentController} from "../src/AgentController.sol";
import {IProtocolAuthority} from "../src/interfaces/IProtocolAuthority.sol";
import {IAccountRegistry} from "../src/interfaces/IAccountRegistry.sol";
import {MockZeroTransferERC20} from "./mocks/MockZeroTransferERC20.sol";
import "../src/libraries/ProtocolErrors.sol";

contract AgentFundZeroReceivedTest is Test {
    AgentController agents;
    MockZeroTransferERC20 token;

    address compliance = makeAddr("compliance");
    address gwen = makeAddr("gwen");

    uint256 agentId;

    function setUp() public {
        token = new MockZeroTransferERC20();
        ProtocolAuthority protocol = new ProtocolAuthority(compliance);
        AccountRegistry registry = new AccountRegistry(IProtocolAuthority(address(protocol)));
        agents = new AgentController(
            IProtocolAuthority(address(protocol)), IAccountRegistry(address(registry))
        );

        vm.prank(gwen);
        registry.createProfile("gwen", AccountRegistry.AccountKind.Personal);

        address[] memory none = new address[](0);
        vm.prank(gwen);
        agentId = agents.createAgent(
            makeAddr("signer"),
            "coding-assistant",
            AgentController.AutonomyTier.SemiAutonomous,
            address(token),
            10e6,
            50e6,
            5e6,
            none,
            false
        );
    }

    function test_funding_that_delivers_nothing_reverts() public {
        vm.expectRevert(InvalidSpendAmount.selector);
        vm.prank(gwen);
        agents.fundAgent(agentId, 100e6);

        assertEq(agents.vaultBalance(agentId), 0);
    }
}
