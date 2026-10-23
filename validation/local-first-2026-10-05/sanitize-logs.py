"""Sanitize public catch logs only; preserve exception/transaction behavior."""
from pathlib import Path
import json, re
changes={}
for path in Path('entry/src/main/ets').rglob('*.ets'):
    text=path.read_text(encoding='utf-8')
    count=0
    lines=[]
    for line in text.splitlines(keepends=True):
        if 'console.error' in line:
            line,n=re.subn(r'JSON\.stringify\((\w*[Ee]rror)\)',
                          r'CloudDiagnostic.code(\1 as Object)',line)
            count+=n
        lines.append(line)
    if count:
        text=''.join(lines)
        import_path='./CloudDiagnostic' if path.parent.name=='services' else '../services/CloudDiagnostic'
        if "import { CloudDiagnostic }" not in text:
            text="import { CloudDiagnostic } from '"+import_path+"';\n"+text
        path.write_text(text,encoding='utf-8')
        changes[str(path)]=count
Path(__file__).with_name('log-sanitization.json').write_text(json.dumps(changes,indent=2),encoding='utf-8')
print('Sanitized',sum(changes.values()),'public catch logs in',len(changes),'files; no error-flow changes.')
