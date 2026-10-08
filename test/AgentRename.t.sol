// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProtocolAuthority} from "../src/ProtocolAuthority.sol";
import {AccountRegistry} from "../src/AccountRegistry.sol";
import {AgentController} from "../src/AgentController.sol";
import {IProtocolAuthority} from "../src/interfaces/IProtocolAuthority.sol";
import {IAccountRegistry} from "../src/interfaces/IAccountRegistry.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract AgentRenameTest is Test {
    AgentController agents;

    address compliance = makeAddr("compliance");
    address gwen = makeAddr("gwen");

    uint256 agentId;

    function setUp() public {
        MockERC20 usdg = new MockERC20("Global Dollar", "USDG", 6);
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
            address(usdg),
            10e6,
            50e6,
            5e6,
            none,
            false
        );
    }

    function test_renaming_to_the_current_label_reverts() public {
        vm.expectRevert(AgentController.SameLabel.selector);
        vm.prank(gwen);
        agents.renameAgent(agentId, "coding-assistant");
    }

    function test_a_real_rename_still_goes_through() public {
        vm.prank(gwen);
        agents.renameAgent(agentId, "research-assistant");
        assertEq(agents.getAgent(agentId).label, "research-assistant");
    }
}
