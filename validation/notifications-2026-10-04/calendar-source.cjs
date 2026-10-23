// Executes the actual production policy with Node's timezone-aware Date. No
// system clock or device timezone changes. Not a device notification test.
const fs=require('fs'),vm=require('vm'),assert=require('assert'),cp=require('child_process');
const out=__dirname;
if(!process.argv[2]){
  const results=['Asia/Hong_Kong','America/New_York'].map(zone=>{
    const run=cp.spawnSync(process.execPath,[__filename,zone],{env:{...process.env,TZ:zone},encoding:'utf8'});
    assert.equal(run.status,0,run.stderr);return JSON.parse(run.stdout);
  });
  fs.writeFileSync(out+'/calendar-source-results.json',JSON.stringify(results,null,2));
  console.log(JSON.stringify(results));process.exit(0);
}
const ts=require('C:/Program Files/Huawei/DevEco Studio/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js');
const source=fs.readFileSync('entry/src/main/ets/services/NotificationPolicy.ets','utf8').replace(/^import[^;]*;\s*/gm,'');
const compiled=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2020,module:ts.ModuleKind.CommonJS}}).outputText;
const context={exports:{},Date,Number,JSON,Array};vm.runInNewContext(compiled,context);const P=context.exports.NotificationPolicy;
let checks=0;
function eq(a,b){assert.equal(a,b);checks++;}
const spring=new Date(2026,2,8),autumn=new Date(2026,10,1);
eq(P.calendarDay(+spring,1),+new Date(2026,2,9));eq(P.calendarDay(+autumn,1),+new Date(2026,10,2));
eq(P.calendarDay(+new Date(2026,11,31,23),1),+new Date(2027,0,1));
eq(P.calendarDay(+new Date(2026,1,28),1),+new Date(2026,2,1));
const quiet={quietEnabled:true,quietStartMinutes:1350,quietEndMinutes:480};
eq(P.inQuiet(+new Date(2026,9,4,22,30),quiet),true);eq(P.inQuiet(+new Date(2026,9,5,8),quiet),false);
eq(P.afterQuiet(+new Date(2026,9,4,23),quiet),+new Date(2026,9,5,8));
eq(P.basicTime(+new Date(2026,9,5,6),+new Date(2026,9,5,7),quiet,+new Date(2026,9,4,20)),+new Date(2026,9,4,22,29));
quiet.quietStartMinutes=0;
eq(P.basicTime(+new Date(2026,9,5,6),+new Date(2026,9,5,7),quiet,+new Date(2026,9,4,21)),+new Date(2026,9,4,23,59));
if(process.argv[2]==='America/New_York'){
  eq(P.calendarDay(+spring,1)-spring,23*3600000);eq(P.calendarDay(+autumn,1)-autumn,25*3600000);
}else{eq(P.calendarDay(+spring,1)-spring,24*3600000);eq(P.calendarDay(+autumn,1)-autumn,24*3600000);}
console.log(JSON.stringify({timezone:process.argv[2],passed:checks,springHours:(P.calendarDay(+spring,1)-spring)/3600000,autumnHours:(P.calendarDay(+autumn,1)-autumn)/3600000}));
