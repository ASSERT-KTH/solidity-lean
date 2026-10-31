"""Real-solc boundary controls for the fork's assembly importer and reject gate."""
from __future__ import annotations

import copy
import os
from pathlib import Path
import subprocess

import pytest

from contest import reject_gate as gate

frontend = gate._IMPORTER


@pytest.fixture
def compile_source(tmp_path):
    solc = os.environ.get('SOLC', 'solc')
    version = subprocess.check_output([solc, '--version'], text=True)
    assert 'Version: 0.8.35+' in version, 'set SOLC to pinned solc 0.8.35'

    def compile_text(source):
        path = tmp_path / 'Probe.sol'
        path.write_text('// SPDX-License-Identifier: MIT\npragma solidity ^0.8.35;\n' + source)
        return frontend.run_solc_ast(solc, path)[1]
    return compile_text


def markers(ast):
    ast = copy.deepcopy(ast)
    frontend.rewrite_recognised_assembly(ast)
    return [node['marker'] for node in gate.iter_nodes(ast)
            if node.get('nodeType') == 'RecognisedAssembly']


@pytest.mark.parametrize('ending', [
    'switch result case 0 { revert(0, returndatasize()) } default { return(0, returndatasize()) }',
    'if iszero(result) { revert(0, returndatasize()) } return(0, returndatasize())',
    'if eq(result, 0) { revert(0, returndatasize()) } return(0, returndatasize())',
])
def test_proxy_exact_and_near_miss(compile_source, ending):
    def source(offset):
        return '''contract C { function f(address target) external {
          assembly { calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), target, 0, calldatasize(), 0, 0)
            returndatacopy(OFFSET, 0, returndatasize()) ENDING }
        }}'''.replace('OFFSET', str(offset)).replace('ENDING', ending)
    accepted = compile_source(source(0))
    rejected = compile_source(source(1))
    assert markers(accepted) == ['forward-delegatecall:target']
    assert markers(rejected) == []
    entry = gate.reg.entry_by_id('X-ASM')
    assert not gate.detect_inline_assembly(entry, gate.SourceAst('Probe.sol', accepted))
    assert gate.detect_inline_assembly(entry, gate.SourceAst('Probe.sol', rejected))


@pytest.mark.parametrize('element', ['uint', 'uint256', 'bytes32'])
def test_memory_array_source_must_not_be_read(compile_source, element):
    def source(extra):
        return '''contract C {
          function f(ELEMENT[] memory src) external pure returns (address[] memory dst) {
            assembly { dst := src } EXTRA
          }}'''.replace('EXTRA', extra).replace('ELEMENT', element)
    assert len(markers(compile_source(source('')))) == 1
    assert markers(compile_source(source('require(src.length != 0);'))) == []


def test_raw_slot_requires_variable_operands(compile_source):
    def source(slot):
        return '''contract C { function f(uint slot, uint value) external {
          assembly { sstore(SLOT, value) }
        }}'''.replace('SLOT', slot)
    assert len(markers(compile_source(source('slot')))) == 1
    assert markers(compile_source(source('0'))) == []


def test_enclosing_contract_cache_matches_independent_walk(compile_source):
    ast = compile_source('contract A { uint x; } contract B { uint y; function f() external {} }')

    def reference(node, owner='?'):
        if isinstance(node, dict):
            yield node, owner
            if node.get('nodeType') == 'ContractDefinition':
                owner = node['name']
            for child in node.values():
                yield from reference(child, owner)
        elif isinstance(node, list):
            for child in node:
                yield from reference(child, owner)

    for node, expected in reference(ast):
        assert gate.enclosing_contract_name(ast, node) == expected
    assert gate.enclosing_contract_name(ast, {}) == '?'
    other = compile_source('contract Other { uint z; }')
    for node, expected in reference(other):
        assert gate.enclosing_contract_name(other, node) == expected
    for node, expected in reference(ast):
        assert gate.enclosing_contract_name(ast, node) == expected
