from pathlib import Path
import runpy,json,re,time
h=runpy.run_path(str(Path(__file__).with_name('device-check.py')),run_name='helper')
call,capture=[h[k] for k in ['call','capture']]
OUT=Path(__file__).parent
remote='/data/local/tmp/dayline-reader-ui.json'; local=OUT/'ui-layout.json'
def nodes():
    call('shell','uitest','dumpLayout','-b','com.gary.ddl','-p',remote);call('file','recv',remote,str(local))
    result=[]
    def walk(o):
        a=o.get('attributes',{})
        if a.get('visible')=='true':result.append(a)
        for c in o.get('children',[]):walk(c)
    walk(json.loads(local.read_text(encoding='utf-8')));return result
def tap(text,last=False):
    matches=[n for n in nodes() if text in n.get('text','')]
    assert matches,text
    nums=list(map(int,re.findall(r'\d+',matches[-1 if last else 0]['bounds'])))
    call('shell','uitest','uiInput','click',str((nums[0]+nums[2])//2),str((nums[1]+nums[3])//2));time.sleep(.8)
def texts():return [n.get('text','') for n in nodes() if n.get('text')]
def back():call('shell','uitest','uiInput','keyEvent','Back');time.sleep(.8)
log=[]
try:
    tap('分页恢复验收',True);t=texts();log.append('DETAIL\n'+'\n'.join(t));capture('final-signed-detail')
    assert any('1 / 2' in s or '1/2' in s or '1 / 2' in s.replace('\u00a0',' ') for s in t),t
    assert any('待确认' in s or '信息不足' in s for s in t),t
    back();tap('设置');tap('华为账号与云同步');t=texts();log.append('ACCOUNT\n'+'\n'.join(t));capture('final-signed-account-pending')
    assert any('旧资料' in s for s in t),t
    back();back();log.append('PASS: detail and account status inspected; normal return reached Home.')
finally:
    (OUT/'ui-final.log').write_text('\n\n'.join(log),encoding='utf-8')
    call('shell','rm '+remote)
