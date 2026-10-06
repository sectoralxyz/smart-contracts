// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProtocolAuthority} from "../src/ProtocolAuthority.sol";
import {AccountRegistry} from "../src/AccountRegistry.sol";
import {AgentController} from "../src/AgentController.sol";
import {IProtocolAuthority} from "../src/interfaces/IProtocolAuthority.sol";
import {IAccountRegistry} from "../src/interfaces/IAccountRegistry.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract AgentStatusChangeTest is Test {
    ProtocolAuthority protocol;
    AccountRegistry registry;
    AgentController agents;
    MockERC20 usdg;

    address compliance = makeAddr("compliance");
    address gwen = makeAddr("gwen");
    address signer = makeAddr("signer");

    uint256 agentId;

    function setUp() public {
        usdg = new MockERC20("Global Dollar", "USDG", 6);
        protocol = new ProtocolAuthority(compliance);
        registry = new AccountRegistry(IProtocolAuthority(address(protocol)));
        agents = new AgentController(
            IProtocolAuthority(address(protocol)), IAccountRegistry(address(registry))
        );

        vm.prank(gwen);
        registry.createProfile("gwen", AccountRegistry.AccountKind.Personal);

        address[] memory none = new address[](0);
        vm.prank(gwen);
        agentId = agents.createAgent(
            signer,
            "coding-assistant",
            AgentController.AutonomyTier.SemiAutonomous,
            address(usdg),
            10e6,
            50e6,
            5e6,
            none,
            false
        );
    }

    function test_setting_the_current_status_again_reverts() public {
        vm.expectRevert(AgentController.SameAgentStatus.selector);
        vm.prank(gwen);
        agents.setAgentStatus(agentId, AgentController.AgentStatus.Active);

        vm.startPrank(gwen);
        agents.setAgentStatus(agentId, AgentController.AgentStatus.Paused);
        vm.expectRevert(AgentController.SameAgentStatus.selector);
        agents.setAgentStatus(agentId, AgentController.AgentStatus.Paused);
        vm.stopPrank();
    }

    function test_pause_and_resume_still_work() public {
        vm.startPrank(gwen);
        agents.setAgentStatus(agentId, AgentController.AgentStatus.Paused);
        agents.setAgentStatus(agentId, AgentController.AgentStatus.Active);
        vm.stopPrank();

        assertEq(
            uint8(agents.getAgent(agentId).status), uint8(AgentController.AgentStatus.Active)
        );
    }
}
