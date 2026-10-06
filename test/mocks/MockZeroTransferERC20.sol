// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice An ERC-20 whose transferFrom reports success but moves nothing,
///         standing in for a token that takes the entire transfer as a fee.
contract MockZeroTransferERC20 {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return true;
    }
}
