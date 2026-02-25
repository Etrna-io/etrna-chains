// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library EtrnaMusicTypes {
    uint16 internal constant MAX_BPS = 10000;

    /// @notice Reward roles used in settlement outputs.
    enum RewardRole {
        ARTIST,
        DJ,
        VENUE,
        COMMUNITY
    }

    /// @notice Optional summarized signal metrics (basis points, clamped to [-10000, 10000]).
    struct SignalSummary {
        int16 attentionBps;
        int16 syncBps;
        int16 momentumBps;
        int16 localityBps;
        int16 densityBps;
    }
}
