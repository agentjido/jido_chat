"""Check the library sources for retired public communication paths.

Run from integration with Python 3. This source scan complements compiled tests.
It does not replace operation, schema, trace, or transport acceptance tests.
"""
import json
import pathlib
import re
import sys

gate = sys.argv[1] if len(sys.argv) > 1 else "G2"
if gate not in ["G2", "G3", "G7"]:
    raise SystemExit("Use G2, G3, or G7")
core = pathlib.Path(__file__).resolve().parents[2]
provider = core.parent / 'jido_chat_signal'
retired = json.loads((core / 'docs/migration/core-retired-modules.json').read_text())['modules']
checks = {
    'retired_core_definition': re.compile(r'^defmodule\s+(?:' + '|'.join(map(re.escape, retired)) + r')\s+do', re.M),
    'retired_core_reference': re.compile(r'\b(?:' + '|'.join(map(re.escape, retired)) + r')(?:\.|\s|\{)'),
    'old_chat_object': re.compile(r'%Jido\.Chat\s*\{'),
    'old_facade_route': re.compile(r'Jido\.Chat\.(?:new|process_message|process_event|route_event|route_request|handle_webhook|handle_webhook_request)\('),
    'old_public_adapter_mapper': re.compile(r'^\s*def\s+(?:transform_incoming|parse_event|handle_webhook)\(', re.M),
    'generic_public_signal_constructor': re.compile(r'Jido\.Signal\.new!?\('),
    'legacy_context_extension': re.compile(r'Jido\.Signal\.Ext\.|["\']correlationid["\']'),
    'custom_domain_catalog': re.compile(r'^defmodule\s+Jido\.(?:Chat|Messaging)\.(?:Signal\.)?Catalog\s+do', re.M),
}
findings = []
files = []
for repo in [core, provider]:
    for file in sorted((repo / 'lib').rglob('*.ex')):
        files.append(str(file.relative_to(core.parent)))
        source = file.read_text()
        for rule, pattern in checks.items():
            for match in pattern.finditer(source):
                findings.append({'rule': rule, 'file': str(file.relative_to(core.parent)), 'line': source[:match.start()].count('\n') + 1})
        if repo == core and re.search(r'^defmodule\s+Jido\.Chat\.Signal\s+do', source, re.M):
            findings.append({'rule': 'provider_parent_owned_by_core', 'file': str(file.relative_to(core.parent))})
parents = [file for file in (provider / 'lib').rglob('*.ex') if re.search(r'^defmodule\s+Jido\.Chat\.Signal\s+do', file.read_text(), re.M)]
if len(parents) != 1:
    findings.append({'rule': 'provider_parent_count', 'count': len(parents)})
result = {'gate': gate, 'state': 'pass' if not findings else 'fail', 'scope': ['jido_chat/lib', 'jido_chat_signal/lib'], 'checked_files': len(files), 'rules': list(checks) + ['provider_parent_owned_by_core', 'provider_parent_count'], 'findings': findings}
out = core / f'docs/migration/evidence/{gate.lower()}/prohibited-core-boundary-scan.json'
if gate == 'G2':
    out = core / 'docs/migration/evidence/g2/prohibited-boundary-scan.json'
out.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
sys.exit(bool(findings))
