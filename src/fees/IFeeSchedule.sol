// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IFeeSchedule
/// @notice The protocol's single price list. Every contract that moves value
///         prices its fee through here, and clients call the same view to show
///         someone their rate before they commit to anything.
interface IFeeSchedule {
    /// @notice What a `payer` owes on a transfer of `amount`.
    /// @param payer Account paying the fee. Every account pays the same rate
    ///        today; the parameter keeps the call shape stable for callers.
    /// @param amount The transfer's full size, denominated in settlement-token units.
    /// @return feeAmount What is owed, in those same units.
    /// @return effectiveBps The rate that actually resulted, for display.
    function quoteFee(address payer, uint256 amount)
        external
        view
        returns (uint256 feeAmount, uint256 effectiveBps);
}
