"""Whitelisted UI observations only; never persist full account layouts."""
import json, re, subprocess, tempfile, sys
from pathlib import Path

HDC = r'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
REMOTE = '/data/local/tmp/dayline-account-probe.json'
SAFE = {'Dayline', '设置', '华为账号与云同步', '账号与云同步', '账户与云同步',
        '未登录', '华为账号登录', '取消', '确定', '登录', '授权', '同意',
        '华为账号', '登录华为账号', '同步失败', '返回'}
def call(*args):
    return subprocess.run([HDC, *args], capture_output=True, text=True, encoding='utf-8', errors='replace')
with tempfile.TemporaryDirectory(prefix='dayline-account-ui-') as folder:
    local = Path(folder) / 'layout.json'
    result = call('shell', 'uitest dumpLayout -p ' + REMOTE)
    assert result.returncode == 0, 'UI layout unavailable'
    call('file', 'recv', REMOTE, str(local))
    tree = json.loads(local.read_text(encoding='utf-8'))
    call('shell', 'rm ' + REMOTE)
nodes = []
def walk(node):
    a = node.get('attributes', {})
    if a.get('visible') == 'true':
        nodes.append(a)
    for child in node.get('children', []):
        walk(child)
walk(tree)
if len(sys.argv) > 1:
    text = sys.argv[1]
    assert text in SAFE, 'Only an observed static label may be selected'
    matches = [n for n in nodes if n.get('text') == text]
    assert matches, 'Requested static control not currently visible'
    numbers = list(map(int, re.findall(r'\d+', matches[-1]['bounds'])))
    result = call('shell', 'uitest uiInput click %d %d' % ((numbers[0]+numbers[2])//2, (numbers[1]+numbers[3])//2))
    print('Selected static control:', text, 'exit:', result.returncode)
else:
    for n in nodes:
        text = n.get('text', '')
        if text in SAFE:
            print(text, n.get('bounds'))
        elif '模拟器' in text and len(text) < 200 and not re.search(r'[0-9@]', text):
            print('Platform simulator message:', text)
    print('Other content omitted; visible node count:', len(nodes))
    print('Static indicators:', json.dumps({
        'simulation_word_present': any('模拟' in n.get('text', '') for n in nodes),
        'unsupported_word_present': any('不支持' in n.get('text', '') for n in nodes),
        'password_prompt_present': any('密码' in n.get('text', '') for n in nodes),
        'verification_code_prompt_present': any('验证码' in n.get('text', '') for n in nodes),
        'test_account_word_present': any('测试账号' in n.get('text', '') for n in nodes),
        'input_controls': sum(n.get('type') in ['TextInput', 'TextArea'] for n in nodes)
    }))
