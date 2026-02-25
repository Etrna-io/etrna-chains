// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {MockERC20} from "./Mocks.sol";
import {MockPass} from "./MockPass.sol";

import {VenueProgramRegistry} from "../src/etrnamusic/VenueProgramRegistry.sol";
import {DJSetLedger} from "../src/etrnamusic/DJSetLedger.sol";
import {CulturalSignalRegistry} from "../src/etrnamusic/CulturalSignalRegistry.sol";
import {PerformanceAttribution} from "../src/etrnamusic/PerformanceAttribution.sol";
import {EtrnaMusicTypes} from "../src/etrnamusic/EtrnaMusicTypes.sol";

contract EtrnaMusicTest is Test {
    address internal admin = address(0xA11CE);
    address internal venueOwner = address(0xB0B);
    address internal dj = address(0xD00D);
    address internal artist1 = address(0xA1);
    address internal artist2 = address(0xA2);
    address internal communityPool = address(0xC011);

    MockERC20 internal etr;
    MockPass internal pass;

    VenueProgramRegistry internal venues;
    DJSetLedger internal sets;
    CulturalSignalRegistry internal signals;
    PerformanceAttribution internal attrib;

    function setUp() public {
        etr = new MockERC20("ETR", "ETR", 18);
        etr.mint(venueOwner, 1_000_000e18);

        // Deploy venue registry with admin owning roles.
        venues = new VenueProgramRegistry(admin, address(etr));

        // Deploy pass and grant DJ identity.
        pass = new MockPass();
        pass.mint(dj);

        // Deploy set ledger.
        sets = new DJSetLedger(admin, address(pass), address(venues));

        // Deploy signal registry.
        signals = new CulturalSignalRegistry(admin);

        // Deploy attribution/settlement.
        attrib = new PerformanceAttribution(admin, address(sets), address(venues), address(signals), communityPool);

        // Allow attribution contract to mark sets settled.
        vm.startPrank(admin);
        sets.grantRole(sets.SETTLEMENT_ROLE(), address(attrib));
        vm.stopPrank();
    }

    function test_end_to_end_settlement_flow() public {
        // 1) Create + verify + activate venue.
        bytes32 venueId;
        vm.startPrank(admin);
        venueId = venues.createVenue(venueOwner, venueOwner, keccak256("venue-metadata"), keccak256("salt"));
        venues.setVenueVerification(venueId, true);
        venues.setVenueStatus(venueId, true);
        vm.stopPrank();

        // 2) DJ creates and ends a set.
        uint256 setId;
        vm.startPrank(dj);
        setId = sets.createSet(venueId, 0, 0, keccak256("set-hash"));
        vm.warp(block.timestamp + 60); // advance time so endTime > startTime
        sets.endSet(setId, 0, keccak256("final-set-hash"));
        vm.stopPrank();

        // 3) Oracle submits signals.
        uint64 epoch = 1;
        vm.prank(admin);
        signals.submitSignalBatch(
            setId,
            epoch,
            keccak256("signal-hash"),
            EtrnaMusicTypes.SignalSummary({
                attentionBps: int16(5000),
                syncBps: int16(5000),
                momentumBps: int16(0),
                localityBps: int16(0),
                densityBps: int16(8000)
            })
        );

        // 4) Settlement finalizes attribution.
        address[] memory artists = new address[](2);
        artists[0] = artist1;
        artists[1] = artist2;

        uint16[] memory bps = new uint16[](2);
        bps[0] = 6000;
        bps[1] = 4000;

        uint32 units = 1000;
        int16 meaningBps = 7000;
        bytes32 attributionHash = keccak256("full-attribution-payload");

        vm.prank(admin);
        attrib.finalizeSetAttribution(setId, epoch, units, meaningBps, attributionHash, artists, bps);

        // 5) Verify set is marked settled.
        (, , , , , , , DJSetLedger.SetStatus status) = sets.sets(setId);
        assertEq(uint8(status), uint8(DJSetLedger.SetStatus.Settled));
    }
}
