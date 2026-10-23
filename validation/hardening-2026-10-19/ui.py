"""HDC UI acceptance for synthetic overdue fixtures. No account interaction."""
from pathlib import Path
import subprocess,json,re,tempfile,time,sys,uuid,os
OUT=Path(__file__).parent
HDC=r'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
def run(*args):
    limit=150 if args[0]=='shell' and len(args)>1 and str(args[1]).startswith('aa test ') else 40
    p=subprocess.run([HDC,'-t',os.environ.get('DAYLINE_TEST_TARGET','127.0.0.1:5555'),*map(str,args)],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=limit)
    if p.returncode or '[Fail]' in p.stdout: raise RuntimeError('Device command failed: '+p.stdout+p.stderr)
    return p.stdout
def nodes(all_surfaces=False):
    remote='/data/local/tmp/dayline-overdue-ui-'+uuid.uuid4().hex+'.json'
    with tempfile.TemporaryDirectory(prefix='dayline-overdue-') as folder:
        local=Path(folder)/'layout.json'
        run('shell','uitest dumpLayout '+('' if all_surfaces else '-b com.gary.ddl ')+'-p '+remote)
        run('file','recv',remote,str(local)); tree=json.loads(local.read_text(encoding='utf-8'))
        run('shell','rm '+remote)
    values=[]
    def walk(node):
        a=node.get('attributes',{})
        if a.get('visible')=='true':values.append(a)
        for child in node.get('children',[]):walk(child)
    walk(tree);return values
def texts():return [n.get('text','') for n in nodes() if n.get('text')]
def decline_input_consent():
    observed=nodes(True)
    if any(n.get('text')=='小艺输入法' for n in observed):
        cancel=[n for n in observed if n.get('text')=='取消']
        assert cancel, 'Do not accept input method consent.'
        run('shell','uitest uiInput click %d %d'%center(cancel[-1]['bounds']));time.sleep(1)
def center(bounds):
    x1,y1,x2,y2=map(int,re.findall(r'\d+',bounds));return (x1+x2)//2,(y1+y2)//2
def tap(label,scroll=False):
    for i in range(10 if scroll else 1):
        observed=nodes()
        found=[n for n in observed if label==n.get('text') and n.get('type')!='AlertDialog']
        if scroll:
            h=int(os.environ.get('DAYLINE_TEST_HEIGHT','2856'))
            found=[n for n in found if int(re.findall(r'\d+',n['bounds'])[3]) < h*.95]
        if found:
            run('shell','uitest uiInput click %d %d'%center(found[0]['bounds']));time.sleep(.7);return
        if scroll:
            w=int(os.environ.get('DAYLINE_TEST_WIDTH','1320'));h=int(os.environ.get('DAYLINE_TEST_HEIGHT','2856'))
            scrollers=[n for n in observed if n.get('type')=='Scroll']
            left,top=0,0
            if scrollers:left,top,_,_=map(int,re.findall(r'\d+',scrollers[0]['bounds']))
            # Swipe the page edge, outside an internally scrolling note field.
            x=left+4
            run('shell','uitest uiInput swipe %d %d %d %d 500'%(x,max(top+90,int(h*.82)),x,max(top+35,int(h*.26))));time.sleep(.4)
    raise RuntimeError('Observed control unavailable: '+label)
def back():run('shell','uitest uiInput keyEvent Back');time.sleep(.8)
def restart():
    run('shell','aa force-stop com.gary.ddl');run('shell','aa start -a EntryAbility -b com.gary.ddl');time.sleep(2)
def capture(name):
    value='\n'.join(texts())
    assert '账号与云同步' not in value and '登录华为账号' not in value, 'Do not capture account screens'
    (OUT/(name+'.txt')).write_text(value,encoding='utf-8')
    remote='/data/local/tmp/dayline-overdue.jpeg'
    run('shell','snapshot_display -f '+remote);run('file','recv',remote,str(OUT/(name+'.jpeg')));run('shell','rm '+remote)
    print(name+'\n'+value,flush=True);return value
if __name__=='__main__':
    cmd=sys.argv[1]
    if cmd=='dump':
        for n in nodes():
            if n.get('text'):print(n.get('type'),n['text'],n.get('bounds'))
    elif cmd=='global':
        for n in nodes(True):
            if n.get('text') or n.get('type') in ['Toggle','Switch']:print(n.get('type'),n.get('text'),n.get('bounds'),n.get('checked'))
    elif cmd=='globaltap':
        matches=[n for n in nodes(True) if n.get('text')==sys.argv[2]]
        assert matches, 'Observed system control unavailable'
        run('shell','uitest uiInput click %d %d'%center(matches[-1]['bounds']));time.sleep(1)
    elif cmd=='capture':capture(sys.argv[2])
    elif cmd=='tap':tap(sys.argv[2],len(sys.argv)>3)
    elif cmd=='back':back()
    elif cmd=='restart':restart()
