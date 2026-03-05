// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

// ─── Tokens ────────────────────────────────────────────────────────────────
import {EtrnaToken} from "../src/tokens/EtrnaToken.sol";
import {VibeToken} from "../src/tokens/VibeToken.sol";

// ─── Community Pass ────────────────────────────────────────────────────────
import {CommunityPass} from "../src/CommunityPass.sol";
import {CommunityTaskRegistry} from "../src/CommunityTaskRegistry.sol";
import {CommunityEconomyRouter} from "../src/CommunityEconomyRouter.sol";

// ─── Music ─────────────────────────────────────────────────────────────────
import {TrackRightsRegistry} from "../src/etrnamusic/TrackRightsRegistry.sol";
import {VenueProgramRegistry} from "../src/etrnamusic/VenueProgramRegistry.sol";
import {DJSetLedger} from "../src/etrnamusic/DJSetLedger.sol";
import {CulturalSignalRegistry} from "../src/etrnamusic/CulturalSignalRegistry.sol";
import {PerformanceAttribution} from "../src/etrnamusic/PerformanceAttribution.sol";

// ─── Governance ────────────────────────────────────────────────────────────
import {GovernanceHybrid} from "../src/governance/GovernanceHybrid.sol";

// ─── Identity ──────────────────────────────────────────────────────────────
import {IdentityProviderRegistry} from "../src/identity/IdentityProviderRegistry.sol";
import {IdentityGuard} from "../src/identity/IdentityGuard.sol";

// ─── Civilization Upgrade ──────────────────────────────────────────────────
import {RealityLedger} from "../src/civilization/RealityLedger.sol";
import {RealityState} from "../src/civilization/RealityState.sol";
import {TemporalRightNFT} from "../src/civilization/TemporalRightNFT.sol";
import {TimeEscrow} from "../src/civilization/TimeEscrow.sol";
import {CognitionMesh} from "../src/civilization/CognitionMesh.sol";
import {HumanityUpgradeProtocol} from "../src/civilization/HumanityUpgradeProtocol.sol";
import {ValueSignalAggregator} from "../src/civilization/ValueSignalAggregator.sol";
import {MeaningEngine} from "../src/civilization/MeaningEngine.sol";
import {JurisdictionRouter} from "../src/civilization/JurisdictionRouter.sol";

// ─── EtrnaPass ─────────────────────────────────────────────────────────
import {EtrnaPass} from "../src/etrnapass/EtrnaPass.sol";

// ─── Identity (extended) ──────────────────────────────────────────────
import {Etrnal} from "../src/identity/Etrnal.sol";
import {IssuerRegistry} from "../src/identity/IssuerRegistry.sol";
import {PassBindingRegistry} from "../src/identity/PassBindingRegistry.sol";

// ─── Mesh ──────────────────────────────────────────────────────────────
import {MeshHub} from "../src/mesh/MeshHub.sol";
import {EtrnaMeshOriginSettler} from "../src/mesh-erc7683/EtrnaMeshOriginSettler.sol";
import {EtrnaMeshDestinationSettler} from "../src/mesh-erc7683/EtrnaMeshDestinationSettler.sol";

// ─── Intents ───────────────────────────────────────────────────────────
import {EtrnaIntentRouter} from "../src/intents/EtrnaIntentRouter.sol";

// ─── Bridge ────────────────────────────────────────────────────────────
import {NftBridgeRouter} from "../src/bridge/NftBridgeRouter.sol";

// ─── Guardian ──────────────────────────────────────────────────────────
import {FeeVault} from "../src/guardian/FeeVault.sol";
import {InsurancePool} from "../src/guardian/InsurancePool.sol";

// ─── Quantum & Randomness ──────────────────────────────────────────────
import {QuantumRandomness} from "../src/quantum/QuantumRandomness.sol";
import {QuantumKeyPolicyRegistry} from "../src/quantum/QuantumKeyPolicyRegistry.sol";
import {PQKeyRegistry} from "../src/pq/PQKeyRegistry.sol";
import {RandomnessRouter} from "../src/randomness/RandomnessRouter.sol";

// ─── Fusion ────────────────────────────────────────────────────────────
import {FusionRegistry} from "../src/fusion/FusionRegistry.sol";

// ─── Seaport ───────────────────────────────────────────────────────────
import {EtrnaZone} from "../src/seaport/EtrnaZone.sol";

// ─── EtrnaVerse ────────────────────────────────────────────────────────
import {BlueprintRegistry} from "../src/etrnaverse/BlueprintRegistry.sol";
import {MilestoneEscrow} from "../src/etrnaverse/MilestoneEscrow.sol";
import {ReceiptNFT} from "../src/etrnaverse/ReceiptNFT.sol";

// ─── AI Agent Infrastructure ───────────────────────────────────────────
import {ComputeCreditVault} from "../src/agents/ComputeCreditVault.sol";
import {EtrnaMindsHub}      from "../src/agents/EtrnaMindsHub.sol";
import {AgentCoordinator}   from "../src/agents/AgentCoordinator.sol";
import {RewardsDistributor} from "../src/agents/RewardsDistributor.sol";

/// @title DeployAll — ETRNA Full Ecosystem Orchestrator
/// @notice Deploys ALL contracts in dependency order with role wiring.
///
/// Dependency graph:
///   1. ETR + VIBE tokens   (no deps)
///   2. CommunityPass        (no deps, uses deployer as admin)
///   3. Identity suite        (no deps)
///   4. Governance            (needs ETR)
///   5. Music suite           (needs ETR, EtrnaPass / CommunityPass)
///   6. Civilization suite    (needs ETR)
///   7. Extended Identity     (Etrnal, EtrnaPass, IssuerRegistry, PassBindingRegistry)
///   8. Mesh & Intents        (MeshHub, ERC7683 Settlers, EtrnaIntentRouter)
///   9. Bridge & Guardian     (NftBridgeRouter, FeeVault, InsurancePool)
///  10. Quantum & Randomness  (QuantumRandomness, QKeyPolicyReg, PQKeyReg, RandomnessRouter)
///  11. Fusion                (FusionRegistry)
///  12. Seaport               (EtrnaZone → IdentityGuard)
///  13. EtrnaVerse            (BlueprintRegistry, MilestoneEscrow, ReceiptNFT)
///
/// Environment variables required:
///   ADMIN           — ecosystem admin address
///   COMMUNITY_POOL  — community revenue pool address (defaults to ADMIN)
///
/// Optional overrides:
///   REP_ORACLE         — reputation oracle (default: address(0))
///   REWARD_DISTRIBUTOR — rewards engine address (default: ADMIN)
///
/// Usage:
///   forge script script/DeployAll.s.sol --rpc-url $RPC --broadcast --verify
contract DeployAll is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN");
        address communityPool = vm.envOr("COMMUNITY_POOL", admin);
        address repOracle = vm.envOr("REP_ORACLE", address(0));
        address rewardDistributor = vm.envOr("REWARD_DISTRIBUTOR", admin);

        vm.startBroadcast();

        EtrnaToken etr;
        VibeToken vibe;
        CommunityPass pass;
        IdentityGuard idGuard;
        GovernanceHybrid gov;

        // ═══════════════════════════════════════════════════════════════════
        // PHASE 1 — Foundation tokens
        // ═══════════════════════════════════════════════════════════════════
        {
            address[] memory recipients = new address[](1);
            recipients[0] = admin;
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = 100_000_000 ether; // 100M initial supply to admin

            etr = new EtrnaToken("Etrna", "ETR", admin, recipients, amounts);
            vibe = new VibeToken("Vibe", "VIBE", admin);

            console2.log("=== PHASE 1: TOKENS ===");
            console2.log("ETR:", address(etr));
            console2.log("VIBE:", address(vibe));
        }

        // ═══════════════════════════════════════════════════════════════════
        // PHASE 2 — Community Pass
        // ═══════════════════════════════════════════════════════════════════
        {
            pass = new CommunityPass(
                "ETRNA Community Pass",
                "ECP",
                "https://api.etrna.io/pass/",
                admin
            );
            CommunityTaskRegistry tasks = new CommunityTaskRegistry(admin, address(pass));
            CommunityEconomyRouter economyRouter = new CommunityEconomyRouter(admin, rewardDistributor);

            console2.log("=== PHASE 2: COMMUNITY PASS ===");
            console2.log("CommunityPass:", address(pass));
            console2.log("TaskRegistry:", address(tasks));
            console2.log("EconomyRouter:", address(economyRouter));
        }

        // ═══════════════════════════════════════════════════════════════════
        // PHASE 3 — Identity
        // ═══════════════════════════════════════════════════════════════════
        {
            IdentityProviderRegistry idRegistry = new IdentityProviderRegistry(admin);
            idGuard = new IdentityGuard(address(idRegistry));

            console2.log("=== PHASE 3: IDENTITY ===");
            console2.log("IdentityProviderRegistry:", address(idRegistry));
            console2.log("IdentityGuard:", address(idGuard));
        }

        // ═══════════════════════════════════════════════════════════════════
        // PHASE 4 — Governance (depends on ETR)
        // ═══════════════════════════════════════════════════════════════════
        {
            gov = new GovernanceHybrid(address(etr), repOracle);

            console2.log("=== PHASE 4: GOVERNANCE ===");
            console2.log("GovernanceHybrid:", address(gov));
        }

        // ═══════════════════════════════════════════════════════════════════
        // PHASE 5 — Music suite (depends on ETR, CommunityPass)
        // ═══════════════════════════════════════════════════════════════════
        _deployMusicPhase(admin, address(etr), address(pass), communityPool);

        // ═══════════════════════════════════════════════════════════════════
        // PHASE 6 — Civilization Upgrade (depends on ETR)
        // ═══════════════════════════════════════════════════════════════════
        _deployCivilizationPhase(admin, address(etr));

        // ═══════════════════════════════════════════════════════════════════
        // PHASE 7 — Extended Identity (Etrnal, EtrnaPass, IssuerRegistry, PassBindingRegistry)
        // ═══════════════════════════════════════════════════════════════════
        {
            Etrnal etrnal = new Etrnal("Etrnal", "ETRNAL", "https://api.etrna.io/etrnal/", admin);
            EtrnaPass etrnaPass = new EtrnaPass(
                admin,
                "EtrnaPass",
                "EPASS",
                "https://assets.etrna.com/ipfs/",
                admin,
                500
            );
            IssuerRegistry issuerReg = new IssuerRegistry(admin);
            PassBindingRegistry passBinding = new PassBindingRegistry(admin, address(etrnal));

            console2.log("=== PHASE 7: EXTENDED IDENTITY ===");
            console2.log("Etrnal:", address(etrnal));
            console2.log("EtrnaPass:", address(etrnaPass));
            console2.log("IssuerRegistry:", address(issuerReg));
            console2.log("PassBindingRegistry:", address(passBinding));
        }

        // ═══════════════════════════════════════════════════════════════════
        // PHASE 8 — Mesh & Intents
        // ═══════════════════════════════════════════════════════════════════
        {
            MeshHub meshHub = new MeshHub(admin);
            EtrnaMeshOriginSettler originSettler = new EtrnaMeshOriginSettler(address(meshHub));
            EtrnaMeshDestinationSettler destSettler = new EtrnaMeshDestinationSettler(address(meshHub), admin);
            EtrnaIntentRouter intentRouter = new EtrnaIntentRouter(address(meshHub), address(idGuard));

            meshHub.transferOwnership(admin);
            intentRouter.transferOwnership(admin);

            console2.log("=== PHASE 8: MESH & INTENTS ===");
            console2.log("MeshHub:", address(meshHub));
            console2.log("OriginSettler:", address(originSettler));
            console2.log("DestSettler:", address(destSettler));
            console2.log("IntentRouter:", address(intentRouter));
        }

        // ═══════════════════════════════════════════════════════════════════
        // PHASE 9 — Bridge & Guardian
        // ═══════════════════════════════════════════════════════════════════
        {
            NftBridgeRouter nftBridge = new NftBridgeRouter();
            nftBridge.transferOwnership(admin);

            FeeVault feeVault = new FeeVault(admin);
            InsurancePool insurancePool = new InsurancePool(admin);

            console2.log("=== PHASE 9: BRIDGE & GUARDIAN ===");
            console2.log("NftBridgeRouter:", address(nftBridge));
            console2.log("FeeVault:", address(feeVault));
            console2.log("InsurancePool:", address(insurancePool));
        }

        // ═══════════════════════════════════════════════════════════════════
        // PHASE 10 — Quantum, PQ & Randomness
        // ═══════════════════════════════════════════════════════════════════
        {
            QuantumRandomness qr = new QuantumRandomness(admin);
            qr.transferOwnership(admin);

            QuantumKeyPolicyRegistry qkpr = new QuantumKeyPolicyRegistry();
            qkpr.transferOwnership(admin);

            PQKeyRegistry pqKeyReg = new PQKeyRegistry();
            pqKeyReg.transferOwnership(admin);

            RandomnessRouter rndRouter = new RandomnessRouter();
            rndRouter.setFulfiller(admin, true);
            rndRouter.transferOwnership(admin);

            console2.log("=== PHASE 10: QUANTUM & RANDOMNESS ===");
            console2.log("QuantumRandomness:", address(qr));
            console2.log("QuantumKeyPolicyRegistry:", address(qkpr));
            console2.log("PQKeyRegistry:", address(pqKeyReg));
            console2.log("RandomnessRouter:", address(rndRouter));
        }

        // ═══════════════════════════════════════════════════════════════════
        // PHASE 11 — Fusion
        // ═══════════════════════════════════════════════════════════════════
        {
            FusionRegistry fusionReg = new FusionRegistry(admin);

            console2.log("=== PHASE 11: FUSION ===");
            console2.log("FusionRegistry:", address(fusionReg));
        }

        // ═══════════════════════════════════════════════════════════════════
        // PHASE 12 — Seaport Zone
        // ═══════════════════════════════════════════════════════════════════
        {
            bytes32 zoneProofType = keccak256("etrna.kyc.basic");
            EtrnaZone etrnaZone = new EtrnaZone(address(idGuard), zoneProofType);

            console2.log("=== PHASE 12: SEAPORT ===");
            console2.log("EtrnaZone:", address(etrnaZone));
        }

        // ═══════════════════════════════════════════════════════════════════
        // PHASE 13 — EtrnaVerse
        // ═══════════════════════════════════════════════════════════════════
        {
            BlueprintRegistry blueprintReg = new BlueprintRegistry(admin);
            MilestoneEscrow milestoneEscrow = new MilestoneEscrow(admin);
            ReceiptNFT receiptNft = new ReceiptNFT(admin);

            console2.log("=== PHASE 13: ETRNAVERSE ===");
            console2.log("BlueprintRegistry:", address(blueprintReg));
            console2.log("MilestoneEscrow:", address(milestoneEscrow));
            console2.log("ReceiptNFT:", address(receiptNft));
        }

        // ═══════════════════════════════════════════════════════════════════
        // PHASE 14 — AI Agent Infrastructure
        // ═══════════════════════════════════════════════════════════════════
        {
            ComputeCreditVault ccVault = new ComputeCreditVault(admin);
            EtrnaMindsHub mindsHub = new EtrnaMindsHub(admin);
            AgentCoordinator agentCoord = new AgentCoordinator(admin);
            RewardsDistributor rewardsDist = new RewardsDistributor(
                admin,
                address(vibe),
                rewardDistributor,
                1_000_000 ether
            );

            ccVault.grantRole(ccVault.ORCHESTRATOR_ROLE(), address(mindsHub));
            mindsHub.grantRole(mindsHub.ORCHESTRATOR_ROLE(), address(agentCoord));

            console2.log("=== PHASE 14: AI AGENT INFRASTRUCTURE ===");
            console2.log("ComputeCreditVault:", address(ccVault));
            console2.log("EtrnaMindsHub:     ", address(mindsHub));
            console2.log("AgentCoordinator:  ", address(agentCoord));
            console2.log("RewardsDistributor:", address(rewardsDist));
        }

        // ═══════════════════════════════════════════════════════════════════
        // CROSS-CONTRACT ROLE WIRING
        // ═══════════════════════════════════════════════════════════════════
        // GovernanceHybrid — transfer Ownable ownership to admin
        gov.transferOwnership(admin);

        vm.stopBroadcast();

        // ═══════════════════════════════════════════════════════════════════
        // Summary
        // ═══════════════════════════════════════════════════════════════════
        console2.log("");
        console2.log("============================================");
        console2.log("  ETRNA FULL ECOSYSTEM DEPLOYED");
        console2.log("  46 contracts across 14 phases");
        console2.log("  Admin:", admin);
        console2.log("============================================");
    }

    function _deployMusicPhase(
        address admin,
        address etr,
        address pass,
        address communityPool
    ) internal {
        TrackRightsRegistry trackRights = new TrackRightsRegistry(admin);
        VenueProgramRegistry venues = new VenueProgramRegistry(admin, etr);
        DJSetLedger sets = new DJSetLedger(admin, pass, address(venues));
        CulturalSignalRegistry signals = new CulturalSignalRegistry(admin);
        PerformanceAttribution attrib = new PerformanceAttribution(
            admin,
            address(sets),
            address(venues),
            address(signals),
            communityPool
        );

        signals.grantRole(signals.ORACLE_ROLE(), admin);
        attrib.grantRole(attrib.SETTLEMENT_ROLE(), admin);
        sets.grantRole(sets.SETTLEMENT_ROLE(), address(attrib));

        console2.log("=== PHASE 5: MUSIC ===");
        console2.log("TrackRightsRegistry:", address(trackRights));
        console2.log("VenueProgramRegistry:", address(venues));
        console2.log("DJSetLedger:", address(sets));
        console2.log("CulturalSignalRegistry:", address(signals));
        console2.log("PerformanceAttribution:", address(attrib));
    }

    function _deployCivilizationPhase(address admin, address etr) internal {
        RealityLedger ledger = new RealityLedger(admin, etr, 1 ether);
        RealityState rState = new RealityState(admin);
        TemporalRightNFT rights = new TemporalRightNFT(admin);
        TimeEscrow escrow = new TimeEscrow(admin, etr, address(rights));
        CognitionMesh cognition = new CognitionMesh(admin);
        HumanityUpgradeProtocol hup = new HumanityUpgradeProtocol(admin, etr);
        ValueSignalAggregator agg = new ValueSignalAggregator(admin);
        MeaningEngine meaning = new MeaningEngine(admin, address(agg));
        JurisdictionRouter jRouter = new JurisdictionRouter(admin);

        console2.log("=== PHASE 6: CIVILIZATION UPGRADE ===");
        console2.log("RealityLedger:", address(ledger));
        console2.log("RealityState:", address(rState));
        console2.log("TemporalRightNFT:", address(rights));
        console2.log("TimeEscrow:", address(escrow));
        console2.log("CognitionMesh:", address(cognition));
        console2.log("HUP:", address(hup));
        console2.log("ValueSignalAggregator:", address(agg));
        console2.log("MeaningEngine:", address(meaning));
        console2.log("JurisdictionRouter:", address(jRouter));
    }
}
