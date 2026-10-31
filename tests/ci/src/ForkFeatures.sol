// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

interface IActor { function ping() external; }
interface IToken { function transfer(address, uint256) external returns (bool); }

contract ForkFeatures {
    struct Box { uint256 x; }
    Box private a;
    Box private b;
    uint256 public immutable immutableValue;
    constructor(uint256 n) { immutableValue = n; }

    function bump() internal returns (uint256) { return ++a.x; }
    function read(Box storage p, uint256) internal view returns (uint256) { return p.x; }
    function pair(uint256 n) internal pure returns (uint256, uint256) { return (n, n + 1); }
    function pick(uint256) internal view returns (Box storage, uint256) { return (a, a.x); }
    function consume(uint256 n, uint256) internal returns (uint256) { b.x = n; return n; }
    function storageArg() external returns (uint256) { a.x = 1; return read(a, bump()); }
    function tupleArg() external returns (uint256) {
        uint256 x; uint256 y; (x, y) = pair(bump()); return x * 10 + y;
    }
    function storageDecl() external returns (uint256) {
        (Box storage p, uint256 n) = pick(bump()); return p.x * 10 + n;
    }
    function discarded() external returns (uint256) { consume(bump(), 0); return b.x; }
    function encodedType() external pure returns (bytes memory) {
        return abi.encodeCall(IToken.transfer, (address(1), 7));
    }
    function encodedVariable(IToken token) external pure returns (bytes memory) {
        return abi.encodeCall(token.transfer, (address(1), 7));
    }
    function receiver() internal returns (ForkFeatures) { a.x += 1; return this; }
    function deposit(uint256 n) external payable { b.x = n + msg.value; }
    function withOptions() external {
        receiver().deposit{value: 0}(3);
    }
    function rawSlot(uint256 slot, uint256 value) external returns (uint256 r) {
        assembly { sstore(slot, value) }
        assembly { r := sload(slot) }
    }
    function storagePointer(uint256 slot, uint256 value) external returns (uint256) {
        Box storage r; assembly { r.slot := slot }
        r.x = value;
        Box storage p; assembly { p.slot := r.slot }
        return p.x;
    }
    function arrayCast(uint256[] memory values) external pure returns (address[] memory result) {
        assembly { result := values }
    }
    function rawRevert(bytes memory data) external pure {
        assembly { revert(add(data, 32), mload(data)) }
    }
    function rawRevertLength(bytes memory data) external pure {
        assembly { let n := mload(data) revert(add(32, data), n) }
    }
    function enter(address actor) external { a.x = 1; IActor(actor).ping(); a.x += 1; }
    function callback() external { a.x += 10; }
    function recordSender() external { a.x = uint160(msg.sender); }
    function observe() external { a.x = immutableValue; b.x = block.timestamp + block.number; }
    function readA() external view returns (uint256) { return a.x; }
    function readB() external view returns (uint256) { return b.x; }
}

contract RawProxy {
    address public impl;
    constructor(address target) { impl = target; }
    fallback() external payable {
        forward(impl);
        revert("forwarding must halt the whole frame");
    }
    function forward(address target) internal {
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), target, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}

contract RawImpl {
    uint256 public count;
    fallback(bytes calldata d) external returns (bytes memory) {
        require(d.length != 0);
        count = 7;
        return hex"1234";
    }
}

contract Child {
    uint256 public x;
    constructor(uint256 n) payable { require(n != 0); x = n; }
}

contract Factory {
    uint256 public answer;
    function make(uint256 n) external payable {
        Child child = new Child{value: msg.value}(n);
        answer = child.x();
    }
    function make2(uint256 n, bytes32 salt) external {
        Child child = new Child{salt: salt}(n);
        answer = child.x();
    }
}
