"""Check the library sources for retired public communication paths.

Run from integration with Python 3. This source scan complements compiled tests.
It does not replace operation, schema, trace, or transport acceptance tests.
"""
import json
import hashlib
import subprocess
import pathlib
import re
import sys

gate = sys.argv[1] if len(sys.argv) > 1 else "G2"
if gate not in ["G2", "G3", "G6", "G7"]:
    raise SystemExit("Use G2, G3, G6, or G7")
core = pathlib.Path(__file__).resolve().parents[2]
provider = core.parent / 'jido_chat_signal'
messaging = core.parent / 'jido_messaging'
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
retired_messaging = [
    'Jido.Messaging.PubSub', 'Jido.Messaging.CommandResult',
    'Jido.Messaging.IngressOutcome', 'Jido.Messaging.ChatActions.Result',
    'Jido.Messaging.Signal.Ext.CorrelationId',
]
checks.update({
    'retired_messaging_reference': re.compile(r'\b(?:' + '|'.join(map(re.escape, retired_messaging)) + r')(?:\.|\s|\{)'),
    'retired_messaging_definition': re.compile(r'^defmodule\s+(?:' + '|'.join(map(re.escape, retired_messaging)) + r')\s+do', re.M),
    'tuple_pubsub_mirror': re.compile(r'Phoenix\.PubSub\.(?:broadcast|subscribe|unsubscribe)\('),
    'legacy_event_option_mapping': re.compile(r'["\']legacy_event["\']\s*=>'),
})
api = json.loads((core / 'docs/migration/api-map.json').read_text())
retired_root_names = sorted({row['function'] for row in api['exports']
                             if row['module'] == 'Jido.Messaging' and row.get('implementation_state') == 'retired'})
retired_root_pattern = re.compile(r'^\s*def\s+(?:' + '|'.join(map(re.escape, retired_root_names)) + r')\(', re.M)
repos = [core, provider]
if gate == 'G3':
    repos.append(messaging)
elif gate in ['G6', 'G7']:
    matrix = json.loads((core / 'docs/migration/version-matrix.json').read_text())
    repos = [core.parent / row['package'] for row in matrix['packages'] if 'base_sha' in row]
findings = []
files = []
source_revisions = []
for repo in repos:
    digest = hashlib.sha256()
    file_count = 0
    for file in sorted((repo / 'lib').rglob('*.ex')):
        files.append(str(file.relative_to(core.parent)))
        source = file.read_text()
        digest.update(str(file.relative_to(repo)).encode() + b"\0" + file.read_bytes() + b"\0")
        file_count += 1
        for rule, pattern in checks.items():
            for match in pattern.finditer(source):
                findings.append({'rule': rule, 'file': str(file.relative_to(core.parent)), 'line': source[:match.start()].count('\n') + 1})
        if repo == messaging and file.name == 'jido_messaging.ex':
            for match in retired_root_pattern.finditer(source):
                findings.append({'rule': 'retired_messaging_root_alias', 'file': str(file.relative_to(core.parent)), 'line': source[:match.start()].count('\n') + 1})
        if repo != provider and re.search(r'^defmodule\s+Jido\.Chat\.Signal\s+do', source, re.M):
            findings.append({'rule': 'provider_parent_wrong_owner', 'file': str(file.relative_to(core.parent))})
    source_revisions.append({
        'repository': repo.name,
        'head_sha': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
        'checked_source_sha256': digest.hexdigest(),
        'checked_files': file_count,
    })
parents = [file for file in (provider / 'lib').rglob('*.ex') if re.search(r'^defmodule\s+Jido\.Chat\.Signal\s+do', file.read_text(), re.M)]
if len(parents) != 1:
    findings.append({'rule': 'provider_parent_count', 'count': len(parents)})
result = {'gate': gate, 'state': 'pass' if not findings else 'fail', 'scope': [repo.name + '/lib' for repo in repos], 'checked_files': len(files), 'source_revisions': source_revisions, 'rules': list(checks) + ['retired_messaging_root_alias', 'provider_parent_wrong_owner', 'provider_parent_count'], 'findings': findings}
out = core / f'docs/migration/evidence/{gate.lower()}/prohibited-core-boundary-scan.json'
if gate in ['G3', 'G7']:
    out = core / f'docs/migration/evidence/{gate.lower()}/prohibited-runtime-boundary-scan.json'
if gate == 'G2':
    out = core / 'docs/migration/evidence/g2/prohibited-boundary-scan.json'
if gate == 'G6':
    out = core / 'docs/migration/evidence/checkpoint-b4/prohibited-boundary-scan.json'
out.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
sys.exit(bool(findings))
