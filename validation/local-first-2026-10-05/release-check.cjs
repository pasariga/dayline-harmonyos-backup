// Execute release boundaries against real production services. Any Kit I/O is
// a failure. Synthetic secret markers never represent account credentials.
const fs=require('fs'),path=require('path'),vm=require('vm'),assert=require('assert');
const ts=require('C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const cache=new Map(),logs=[],io=[];
const forbidden=new Proxy(function(){},{get(_,key){if(key==='then')return undefined;return forbidden;},apply(){io.push('Kit access');throw new Error('Unexpected Kit I/O');}});
function load(file){
 file=path.resolve(file);if(!path.extname(file))file+='.ets';if(cache.has(file))return cache.get(file).exports;
 const module={exports:{}};cache.set(file,module);
 const code=ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2020,module:ts.ModuleKind.CommonJS}}).outputText;
 function require(id){
  if(id.startsWith('.'))return load(path.resolve(path.dirname(file),id));
  if(id==='@kit.ArkData')return {relationalStore:{ProgressCode:{SUCCESS:0}}};
  if(id==='@kit.PerformanceAnalysisKit')return {hilog:{error:(...v)=>logs.push(v.join(' '))}};
  return forbidden;
 }
 vm.runInNewContext(code,{module,exports:module.exports,require,Date,Math,Number,Map,Set,JSON,Array,String,Error,Promise,
 console:{error:(...v)=>logs.push(v.join(' ')),warn:(...v)=>logs.push(v.join(' ')),info:()=>{}},
 AppStorage:{setOrCreate(){throw new Error('Unexpected app mutation');}}},{filename:file});
 return module.exports;
}
(async()=>{
 const {CloudSyncService:S}=load('entry/src/main/ets/services/CloudSyncService.ets');
 const context=new Proxy({}, {get(){throw new Error('Unexpected context access');}});
 const result=await S.syncNow(context);assert.equal(result.code,-7);assert.equal(result.isSuccess(),false);
 assert.equal(await S.syncIfDue(context),undefined);assert.equal(await S.requestDataSyncPermission(context),false);
 assert.equal(io.length,0,'release gate accessed a native/account/permission API');
 const {AppLogger:L}=load('entry/src/main/ets/services/AppLogger.ets');
 L.error('Release','Operation failed',new Error('SYNTHETIC_PRIVATE_CONTENT'));
 L.cloudError('Release','Cloud operation failed',{code:123,message:'SYNTHETIC_PRIVATE_CONTENT',token:'SYNTHETIC_PRIVATE_CONTENT'});
 assert.equal(logs.length,2);assert(logs.every(l=>!l.includes('SYNTHETIC_PRIVATE_CONTENT')));assert(logs[1].includes('code=123'));
 const report={manual_sync_rejected:true,automatic_sync_skipped:true,permission_ui_skipped:true,
 native_io_calls:io.length,private_error_content_logged:false,numeric_diagnostics_preserved:true};
 fs.writeFileSync(path.join(__dirname,'release-check.json'),JSON.stringify(report,null,2));
 process.stdout.write('PASS: production cloud gates before Kit/context access; public logs retain codes only.\n');
})().catch(e=>{process.stderr.write(e.message+'\n');process.exitCode=1;});
