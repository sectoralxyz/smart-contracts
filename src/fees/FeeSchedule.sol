// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IFeeSchedule} from "./IFeeSchedule.sol";
import "../libraries/ProtocolErrors.sol";

/// @title FeeSchedule
/// @notice The protocol's price list. Contracts that move value call
///         {quoteFee} to price a transfer; the app and SDK call the same view
///         to show someone their live rate. Both arrive at the same number by
///         the same route.
///
/// @dev All arithmetic in basis points, where 1 bps is 0.01%:
///
///        grossFee   = amount * baseFeeBps / 10_000
///        feeAmount  = min(grossFee, feeCap)       // when a cap is configured
///
///      Amounts and the cap are in the settlement token's smallest unit, with
///      defaults assuming a six-decimal stablecoin: 0.10% capped at 5 USDG.
contract FeeSchedule is IFeeSchedule {
    /// @notice Thrown when someone other than the nominated successor tries to
    ///         complete an authority handoff.
    error NotPendingAuthority();

    uint256 internal constant BPS = 10_000;

    /// @notice The highest base rate the schedule will accept: 1%. The fee is
    ///         added on top of every payment, so a slipped digit in a retune
    ///         should be refused here rather than charged to users.
    uint16 public constant MAX_BASE_FEE_BPS = 100;

    /// @notice Who may retune the schedule; the protocol multisig in practice.
    address public authority;

    /// @notice Successor nominated for that role, powerless until it calls
    ///         {acceptAuthority}. The key that prices every fee in the protocol
    ///         should not be losable to a typo.
    address public pendingAuthority;

    /// @notice The rate applied to every transfer, in basis points.
    uint16 public baseFeeBps;

    /// @notice Hard ceiling on a single fee, in settlement-token units. Zero
    ///         means no ceiling.
    uint256 public feeCap;

    event FeeScheduleUpdated(uint16 baseFeeBps, uint256 feeCap);
    event AuthorityTransferStarted(
        address indexed currentAuthority, address indexed pendingAuthority
    );
    event AuthorityTransferAccepted(
        address indexed previousAuthority, address indexed newAuthority
    );

    modifier onlyAuthority() {
        if (msg.sender != authority) revert Unauthorized();
        _;
    }

    constructor(address authority_) {
        if (authority_ == address(0)) revert ZeroAddress();
        authority = authority_;

        // Shipping defaults: a tenth of a percent, never more than 5 units
        // (5 USDG at six decimals).
        baseFeeBps = 10;
        feeCap = 5_000_000;
    }

    // ── Pricing ──────────────────────────────────────────────────────────────

    /// @inheritdoc IFeeSchedule
    function quoteFee(address, uint256 amount)
        external
        view
        returns (uint256 feeAmount, uint256 effectiveBps)
    {
        uint256 gross = (amount * baseFeeBps) / BPS;
        feeAmount = (feeCap != 0 && gross > feeCap) ? feeCap : gross;
        effectiveBps = amount == 0 ? 0 : (feeAmount * BPS) / amount;
    }

    // ── Tuning ───────────────────────────────────────────────────────────────

    /// @notice Resets the base rate and the ceiling.
    function setSchedule(uint16 baseFeeBps_, uint256 feeCap_) external onlyAuthority {
        if (baseFeeBps_ > MAX_BASE_FEE_BPS) revert InvalidFeeConfig();
        baseFeeBps = baseFeeBps_;
        feeCap = feeCap_;
        emit FeeScheduleUpdated(baseFeeBps_, feeCap_);
    }

    /// @notice Nominates the next tuning authority without giving anything up
    ///         yet. The nominee takes the role by calling {acceptAuthority}.
    /// @dev The same two-step handoff every admin role in the protocol uses, so
    ///      there is one procedure to learn rather than three. Nominating the
    ///      zero address withdraws an outstanding nomination.
    function beginAuthorityTransfer(address newAuthority) external onlyAuthority {
        pendingAuthority = newAuthority;
        emit AuthorityTransferStarted(authority, newAuthority);
    }

    /// @notice Claims the role nominated through {beginAuthorityTransfer}.
    function acceptAuthority() external {
        if (msg.sender != pendingAuthority) revert NotPendingAuthority();
        address previous = authority;
        authority = msg.sender;
        pendingAuthority = address(0);
        emit AuthorityTransferAccepted(previous, msg.sender);
    }
}
