// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;
import {ForkFeatures, RawProxy, RawImpl, Factory, Child, IToken} from "../src/ForkFeatures.sol";

contract ReentrantActor {
    function ping() external { ForkFeatures(msg.sender).callback(); }
}

contract StorageWitnessReference {
    int16[] private numbers = [-1, -2];
    bytes10[] private words;
    function sum() external view returns (int16) { return numbers[0] + numbers[1]; }
    function widen() external returns (bytes10) {
        bytes4[] memory source = new bytes4[](3);
        source[2] = "cdef";
        words = source;
        return words[2];
    }
}

contract ForkFeaturesTest {
    function testStorageWitnessReference() public {
        StorageWitnessReference r = new StorageWitnessReference();
        require(r.sum() == -3);
        require(r.widen() == bytes10(hex"63646566000000000000"));
    }
    function testFrontend() public {
        require((new ForkFeatures(0)).storageArg() == 2);
        require((new ForkFeatures(0)).tupleArg() == 12);
        require((new ForkFeatures(0)).storageDecl() == 11);
        require((new ForkFeatures(0)).discarded() == 1);
        ForkFeatures f = new ForkFeatures(0);
        require(keccak256(f.encodedType()) == keccak256(abi.encodeCall(IToken.transfer, (address(1), 7))));
        require(keccak256(f.encodedVariable(IToken(address(2)))) == keccak256(f.encodedType()));
        f.withOptions(); require(f.readA() == 1 && f.readB() == 3);
    }
    function testAssembly() public {
        ForkFeatures f = new ForkFeatures(0);
        require(f.rawSlot(0, 42) == 42 && f.readA() == 42);
        require(f.storagePointer(1, 17) == 17 && f.readB() == 17);
        uint256[] memory words = new uint256[](2); words[0] = 1; words[1] = 2;
        address[] memory addresses = f.arrayCast(words);
        require(addresses.length == 2 && addresses[0] == address(1) && addresses[1] == address(2));
        (bool ok, bytes memory out) = address(f).call(abi.encodeCall(f.rawRevert, (hex"1234")));
        require(!ok && keccak256(out) == keccak256(hex"1234"));
        (ok, out) = address(f).call(abi.encodeCall(f.rawRevertLength, (hex"1234")));
        require(!ok && keccak256(out) == keccak256(hex"1234"));
        RawProxy p = new RawProxy(address(new RawImpl()));
        (ok, out) = address(p).call(hex"deadbeef");
        require(ok && keccak256(out) == keccak256(hex"1234"));
        require(uint160(p.impl()) == 7);
        RawProxy failing = new RawProxy(address(new RawImpl()));
        (ok, out) = address(failing).call("");
        require(!ok && out.length == 0);
    }
    function testReentrancyAndImmutables() public {
        ForkFeatures f = new ForkFeatures(42);
        f.enter(address(new ReentrantActor())); require(f.readA() == 12);
        f.observe(); require(f.readA() == 42 && f.readB() == block.timestamp + block.number);
    }
    function testCreationAndRevert() public {
        require(address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff), address(0x500), bytes32(uint256(5)), bytes32(uint256(123))
        ))))) == address(0x48AcC88f821691C8Fb9f469db7eFD32058126db9));
        Factory f = new Factory(); f.make{value: 3}(7); require(f.answer() == 7);
        (bool ok,) = address(f).call(abi.encodeCall(f.make, (0)));
        require(!ok && f.answer() == 7);
        f.make2(9, bytes32(uint256(5))); require(f.answer() == 9);
        // Same creator, salt, init code: a second CREATE2 cannot deploy again.
        (ok,) = address(f).call(abi.encodeCall(f.make2, (9, bytes32(uint256(5)))));
        require(!ok);
    }
}
