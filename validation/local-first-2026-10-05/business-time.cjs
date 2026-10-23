// Actual production ArkTS transpilation. Kit I/O stubs only; Date/Intl and all
// planning, capacity, workload and notification calculations are real source.
// A fresh process per zone avoids the mixed Date/TZ runtime of Hvigor's runner.
const fs=require('fs'),path=require('path'),vm=require('vm'),cp=require('child_process'),assert=require('assert');
const zones=['Asia/Shanghai','Asia/Tokyo','Europe/Berlin','America/New_York'];
if(!process.argv[2]){
  const result=zones.map(zone=>{const r=cp.spawnSync(process.execPath,[__filename,zone],{env:{...process.env,TZ:zone},encoding:'utf8'});assert.equal(r.status,0,r.stdout+r.stderr);return JSON.parse(r.stdout);});
  fs.writeFileSync(path.join(__dirname,'business-time-results.json'),JSON.stringify(result,null,2));
  console.log(JSON.stringify({scenarios:result.reduce((s,r)=>s+r.passed,0),zones:result}));process.exit(0);
}
const ts=require('C:/Program Files/Huawei/DevEco Studio/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js');
const cache=new Map();let locale='en-US',military=true;
const dummy=new Proxy(function(){},{get:(_,key)=>key==='then'?undefined:dummy,apply:()=>undefined});
function load(file){
 file=path.resolve(file);if(!path.extname(file))file+='.ets';if(cache.has(file))return cache.get(file).exports;
 const module={exports:{}};cache.set(file,module);
 const code=ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2020,module:ts.ModuleKind.CommonJS}}).outputText;
 const require=(id)=>id.startsWith('.')?load(path.resolve(path.dirname(file),id)):id==='@kit.LocalizationKit'?{i18n:{getTimeZone:()=>({getID:()=>process.argv[2]}),System:{getAppPreferredLanguage:()=>locale,is24HourClock:()=>military}}}:dummy;
 vm.runInNewContext(code,{module,exports:module.exports,require,Date,Intl,Math,Number,Map,Set,JSON,Array,String,console,Error,Promise},{filename:file});return module.exports;
}
const root='entry/src/main/ets/';const {Deadline}=load(root+'models/Deadline.ets');
const {DeadlineTime:T}=load(root+'services/DeadlineTime.ets'),{DeadlineInsightService:I}=load(root+'services/DeadlineInsightService.ets');
const {DeadlineScheduleService:S}=load(root+'services/DeadlineScheduleService.ets'),{TodayActionService:A}=load(root+'services/TodayActionService.ets');
const {AppSettings,AppSettingsRuntime:R}=load(root+'services/AppSettingsService.ets'),{NotificationPolicy:P}=load(root+'services/NotificationPolicy.ets');
const {NotificationSettings:N,NotificationRuntimeState:U}=load(root+'services/NotificationSettingsService.ets');
const {DeadlineReminderService:M}=load(root+'services/DeadlineReminderService.ets'),{DeadlineDataSnapshot:Snapshot}=load(root+'services/DeadlineDatabaseService.ets');
const {DeadlineOverdueRuntime:O}=load(root+'services/DeadlineOverdueService.ets'),{LocalizationService:L}=load(root+'services/LocalizationService.ets');
const zone=process.argv[2],dst=zone==='America/New_York'||zone==='Europe/Berlin';
const cases=[];function check(name,fn){fn();cases.push(name);}
function d(due,now,h=20,id='date'){return new Deadline(id,id,'项目',T.dateKey(due),T.timeKey(due),'',now,due,false,h,0,'manual',0,1440,h,'confirmed',now);}
function setup(){R.apply(new AppSettings('system','manual',3,true,'23:59',3));O.restore('[]');}
function reminders(ds,now,settings=new N(),states=[],runtime=new U()){return M.buildDesiredReminders(new Snapshot(ds,[]),states,settings,runtime,now);}
function verifyDay(start){
 setup();const now=+start,due=+new Date(start.getFullYear(),start.getMonth(),start.getDate()+2,23);const item=d(due,now);
 const plan=S.buildPlan(item,[],now);assert.equal(plan.days.length,3);assert.equal(new Set(plan.days.map(r=>T.dateKey(r.dateAt))).size,3);
 const agenda=S.buildAgenda([item,d(due,now,20,'other')],[],3,now);assert.equal(agenda.length,3);
 assert(agenda.every(r=>r.capacityHours===3&&r.estimatedHours<=3));assert.equal(R.getAvailableHoursBetween(now,T.calendarDay(now,1)),3);
 assert(A.buildPlan([item],[],now).actions.length>0);assert.equal(T.daysBetween(now,due),2);
 return (T.calendarDay(now,1)-now)/3600000;
}
const spring=zone==='Europe/Berlin'?new Date(2026,2,29):new Date(2026,2,8);
const autumn=zone==='Europe/Berlin'?new Date(2026,9,25):new Date(2026,10,1);
check('spring: full business plan has all three dates and one daily budget',()=>assert.equal(verifyDay(spring),dst?23:24));
check('autumn: full business plan has no repeated date or capacity',()=>assert.equal(verifyDay(autumn),dst?25:24));
check('UTC+8 or local ordinary date capacity',()=>assert.equal(verifyDay(new Date(2026,9,5)),24));
check('midnight: agenda, risk, action and overdue recalculate',()=>{
 const before=+new Date(2026,9,5,23,59),after=+new Date(2026,9,6);const item=d(before+30000,before);
 assert.notEqual(I.analyze(item,before).riskLevel,'overdue');assert.equal(I.analyze(item,after).riskLevel,'overdue');
 assert.equal(S.buildAgenda([item],[],1,after)[0].dateAt,after);assert.equal(S.buildPlan(item,[],after).days.length,0);
 assert.equal(A.buildPlan([item],[],after).actions[0].kind,'overdue-review');assert.equal(T.refreshDelay(after-1000,[]),1001);
});
check('today past input: create rejected, historical edit allowed',()=>{
 const now=+new Date(2026,9,5,12);assert.equal(T.inputError('2026-10-05','11:00',false,now),'validation_time_past');assert.equal(T.inputError('2026-10-05','11:00',true,now),'');
});
check('same-day deadline allocation uses actual chronological instant',()=>{
 const now=+new Date(2026,9,5,7);const early=d(now+3600000,now,3,'early'),late=d(now+7200000,now,3,'late');assert.equal(S.buildAgenda([late,early],[],1,now)[0].items[0].deadlineId,'early');
});
check('two natural dates through DST',()=>assert.equal(T.daysBetween(+spring,+new Date(spring.getFullYear(),spring.getMonth(),spring.getDate()+2)),2));
check('14 natural dates: freshness deliberately remains 336 elapsed hours',()=>{
 const now=+new Date(spring.getFullYear(),spring.getMonth(),spring.getDate()-7,12);const after=+new Date(spring.getFullYear(),spring.getMonth(),spring.getDate()+7,12);
 const item=d(after+5*86400000,now);assert.equal(T.daysBetween(now,after),14);assert.equal(after-now,(dst?335:336)*3600000);assert.equal(I.analyze(item,after).workloadConfidence,'rough');
 assert.equal(I.analyze(item,now+336*3600000+1).workloadConfidence,'stale');assert.equal(item.remainingHours,20);
});
check('autumn 14 calendar dates do not extend the elapsed-age policy',()=>{
 const now=+new Date(autumn.getFullYear(),autumn.getMonth(),autumn.getDate()-7,12);const after=+new Date(autumn.getFullYear(),autumn.getMonth(),autumn.getDate()+7,12);
 const item=d(after+5*86400000,now);assert.equal(T.daysBetween(now,after),14);assert.equal(I.analyze(item,after).workloadConfidence,dst?'stale':'rough');
});
const fixed=Date.parse('2026-10-20T15:00:00Z');
check('Shanghai to Tokyo to Berlin to New York keeps the fixed cutoff',()=>{
 const item=d(fixed,Date.parse('2026-10-19T00:00:00Z'));const original=JSON.stringify(item);S.buildPlan(item,[],item.createdAt);A.buildPlan([item],[],item.createdAt);
 assert.equal(JSON.stringify(item),original);assert.equal(item.deadlineAt,fixed);
 assert.equal(T.timeKey(fixed),{'Asia/Shanghai':'23:00','Asia/Tokyo':'00:00','Europe/Berlin':'17:00','America/New_York':'11:00'}[zone]);
});
check('forward wall clock expires old risk and schedule',()=>{
 const now=+new Date(2026,9,5,12),item=d(now+3600000,now);assert.equal(I.analyze(item,now+7200000).riskLevel,'overdue');assert.equal(S.buildPlan(item,[],now+7200000).days.length,0);
});
check('backward wall clock cannot make a future confirmation fresh',()=>{
 const now=+new Date(2026,9,5,12),item=d(now+86400000,now);assert.equal(I.analyze(item,now-3600000).workloadConfidence,'stale');assert.equal(I.analyze(item,now).workloadConfidence,'rough');
});
check('long background uses the new natural date',()=>{
 const now=+new Date(2026,9,5,12),resume=+new Date(2026,9,8,12),item=d(resume+86400000,now);assert.equal(S.buildAgenda([item],[],1,resume)[0].dateAt,T.calendarDay(resume));assert(A.buildPlan([item],[],resume).actions.length>0);
});
check('strict overdue instant and no old-cutoff plan',()=>{
 const now=+new Date(2026,9,5,12),item=d(now,now);assert.notEqual(I.analyze(item,now).riskLevel,'overdue');assert.equal(I.analyze(item,now+1).riskLevel,'overdue');assert.equal(S.buildPlan(item,[],now+1).days.length,0);
});
for(const [name,day]of[['spring',spring],['autumn',autumn]]){
 check(name+': actual one-day and three-day reminder candidates keep clock time',()=>{
  const due=+new Date(day.getFullYear(),day.getMonth(),day.getDate()+1,8,30),now=+new Date(day.getFullYear(),day.getMonth(),day.getDate()-5,12);const item=d(due,now);const settings=new N();settings.quietEnabled=false;
  for(const days of[1,3]){item.reminderOffsetMinutes=days*1440;const actual=reminders([item],now,settings).find(r=>r.key===item.id);assert(actual);assert.equal(actual.scheduledAt,+new Date(day.getFullYear(),day.getMonth(),day.getDate()+1-days,8,30));}
  item.reminderOffsetMinutes=60;assert.equal(reminders([item],now,settings).find(r=>r.key===item.id).scheduledAt,due-3600000);
 });
 check(name+': actual daily summary candidates keep local clock and unique day keys',()=>{
  const now=+new Date(day.getFullYear(),day.getMonth(),day.getDate()-1,7),item=d(T.calendarDay(+day,8),now);const settings=new N();settings.quietEnabled=false;
  const daily=reminders([item],now,settings).filter(r=>r.key.startsWith('smart:daily:'));assert.equal(daily.length,3);assert.equal(new Set(daily.map(r=>r.key)).size,3);
  assert(daily.every(r=>T.timeKey(r.scheduledAt)==='08:30'&&r.autoDeletedAt===T.calendarDay(r.scheduledAt,1)));
  const later=+new Date(day.getFullYear(),day.getMonth(),day.getDate(),9);assert(!reminders([item],later,settings).some(r=>r.key==='smart:daily:'+T.dateKey(later)));
 });
 check(name+': overnight quiet interval ends at local morning',()=>{
  const at=+new Date(day.getFullYear(),day.getMonth(),day.getDate()-1,23),settings=new N();assert.equal(P.afterQuiet(at,settings),+new Date(day.getFullYear(),day.getMonth(),day.getDate(),8));assert.equal(P.inQuiet(P.afterQuiet(at,settings),settings),false);
 });
}
check('nonexistent spring input cannot silently shift the deadline',()=>{
 const date=T.dateKey(+spring),key=T.inputError(date,'02:30',true,+spring);assert.equal(key,dst?'validation_time_missing':'');
});
check('ambiguous autumn input requires an unambiguous selection',()=>{
 const date=T.dateKey(+autumn),time=zone==='America/New_York'?'01:30':'02:30';assert.equal(T.inputError(date,time,true,+autumn),dst?'validation_time_ambiguous':'');
});
if(dst)check('quiet end in repeated hour chooses the still-future occurrence',()=>{
 const hour=zone==='America/New_York'?1:2;const first=+new Date(autumn.getFullYear(),autumn.getMonth(),autumn.getDate(),hour,15);const second=first+3600000;const settings=new N();settings.quietStartMinutes=0;settings.quietEndMinutes=hour*60+30;
 assert.equal(P.afterQuiet(second,settings),second+15*60000);assert.equal(P.inQuiet(P.afterQuiet(second,settings),settings),false);
});
if(dst)check('Calendar encoding blocks the second repeated instant rather than shifting it',()=>{
 const first=+new Date(autumn.getFullYear(),autumn.getMonth(),autumn.getDate(),zone==='America/New_York'?1:2,30);
 assert.equal(T.calendarCanRepresent(first),true);assert.equal(T.calendarCanRepresent(first+3600000),false);
});
check('zh/en/de/fr formatting and 12/24 hours use Intl in production',()=>{
 const instant=+new Date(2026,9,20,23);for(const language of['zh-CN','en-US','de-DE','fr-FR']){locale=language;military=true;assert.equal(L.formatDateTime(new Date(instant)),new Intl.DateTimeFormat(language,{dateStyle:'medium',timeStyle:'short',hour12:false}).format(instant));assert.equal(L.formatClockTime('23:00'),new Intl.DateTimeFormat(language,{hour:'numeric',minute:'2-digit',hour12:false,timeZone:'UTC'}).format(Date.UTC(2000,0,1,23)));military=false;assert.equal(L.formatTime(new Date(instant)),new Intl.DateTimeFormat(language,{hour:'numeric',minute:'2-digit',hour12:true}).format(instant));}
});
console.log(JSON.stringify({timezone:zone,passed:cases.length,springHours:(T.calendarDay(+spring,1)-spring)/3600000,autumnHours:(T.calendarDay(+autumn,1)-autumn)/3600000,fixedCutoff:fixed,localDisplay:T.dateKey(fixed)+' '+T.timeKey(fixed),cases}));
