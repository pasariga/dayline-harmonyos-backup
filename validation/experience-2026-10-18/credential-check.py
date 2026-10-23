"""Never print or persist a credential; report only match counts."""
from pathlib import Path
import re, json, zipfile
OUT = Path(__file__).parent
config = Path('build-profile.json5').read_text(encoding='utf-8')
secrets = []
for name in ['storePassword', 'keyPassword', 'clientSecret', 'token']:
    for match in re.finditer(r'"'+name+r'"\s*:\s*("(?:[^"\\]|\\.)*")', config):
        value = json.loads(match.group(1))
        if value:
            secrets.append(value.encode())
matches = []
for path in list(OUT.rglob('*')) + list(Path('.').glob('*.md')):
    if path.is_file() and path.suffix.lower() in ['.log', '.json', '.txt', '.md', '.xml']:
        data = path.read_bytes()
        if any(secret in data or secret.decode().encode('utf-16-le') in data for secret in secrets):
            matches.append(path.name)
hap = Path('entry/build/default/outputs/default/entry-default-signed.hap')
with zipfile.ZipFile(hap) as package:
    for name in package.namelist():
        if any(secret in package.read(name) for secret in secrets):
            matches.append('HAP: ' + name)
assert not matches, 'A local signing credential appears in an output; suppress values and fix output'
result = {'local_signing_credential_fields_checked': len(secrets),
          'credential_matches_in_validation_or_packaged_files': 0,
          'signing_identity_changed': False,
          'real_account_credentials_obtained_this_round': False}
(OUT/'credential-check.json').write_text(json.dumps(result, indent=2))
print('PASS: no local signing credential value in validation text or packaged files.')

