// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {QuantumKeyPolicyRegistry} from "../src/quantum/QuantumKeyPolicyRegistry.sol";

contract QuantumKeyPolicyTest is Test {
    QuantumKeyPolicyRegistry registry;

    address owner = address(this);
    address alice = address(0xA1);

    function setUp() public {
        registry = new QuantumKeyPolicyRegistry();
    }

    function test_setPolicyAndGet() public {
        bytes32 pid = keccak256("dilithium-v3");
        registry.setPolicy(pid, "Dilithium v3", "ipfs://Qm123");

        QuantumKeyPolicyRegistry.Policy memory p = registry.getPolicy(pid);
        assertEq(p.name, "Dilithium v3");
        assertEq(p.uri, "ipfs://Qm123");
        assertTrue(p.exists);
    }

    function test_getPolicyNonExistent() public view {
        bytes32 pid = keccak256("unknown");
        QuantumKeyPolicyRegistry.Policy memory p = registry.getPolicy(pid);
        assertEq(bytes(p.name).length, 0);
        assertFalse(p.exists);
    }

    function test_setPolicyOverwrite() public {
        bytes32 pid = keccak256("policy1");
        registry.setPolicy(pid, "v1", "uri1");
        registry.setPolicy(pid, "v2", "uri2");

        QuantumKeyPolicyRegistry.Policy memory p = registry.getPolicy(pid);
        assertEq(p.name, "v2");
        assertEq(p.uri, "uri2");
        assertTrue(p.exists);
    }

    function test_setPolicyRevertNonOwner() public {
        bytes32 pid = keccak256("policy1");
        vm.prank(alice);
        vm.expectRevert();
        registry.setPolicy(pid, "fail", "nope");
    }

    function test_multiplePolicies() public {
        bytes32 pid1 = keccak256("kyber");
        bytes32 pid2 = keccak256("falcon");

        registry.setPolicy(pid1, "Kyber", "ipfs://k");
        registry.setPolicy(pid2, "Falcon", "ipfs://f");

        assertEq(registry.getPolicy(pid1).name, "Kyber");
        assertEq(registry.getPolicy(pid2).name, "Falcon");
    }

    function test_setPolicyEmitsEvent() public {
        bytes32 pid = keccak256("test-emit");
        vm.expectEmit(true, false, false, true);
        emit QuantumKeyPolicyRegistry.PolicySet(pid, "TestPolicy", "ipfs://test");
        registry.setPolicy(pid, "TestPolicy", "ipfs://test");
    }

    function test_setPolicyEmptyStrings() public {
        bytes32 pid = keccak256("empty");
        registry.setPolicy(pid, "", "");

        QuantumKeyPolicyRegistry.Policy memory p = registry.getPolicy(pid);
        assertEq(bytes(p.name).length, 0);
        assertEq(bytes(p.uri).length, 0);
        assertTrue(p.exists);
    }
}
