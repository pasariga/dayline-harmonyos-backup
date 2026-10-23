$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'
$env:PYTHONUTF8='1'
$taskNode='C:\Program Files\Huawei\DevEco Studio\tools\node\node.exe'
$taskHvigor='C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js'
$taskOut='validation\experience-2026-10-18'
& $taskNode $taskHvigor --mode module -p product=default -p module=entry@default test --no-daemon *> "$taskOut\test-final.log"
if ($LASTEXITCODE -ne 0) {Get-Content "$taskOut\test-final.log" -Tail 30; exit 1}
Copy-Item -LiteralPath entry/.test/default/intermediates/test/coverage_data/test_result.txt -Destination "$taskOut\test-final-result.txt"
if ((Get-Content -Raw "$taskOut\test-final-result.txt") -notmatch 'Tests run: 237, Failure: 0, Error: 0, Pass: 237') {throw 'Tests did not all pass'}
python "$taskOut\audit.py" *> "$taskOut\audit.log"
if ($LASTEXITCODE -ne 0) {Get-Content "$taskOut\audit.log"; exit 1}
& $taskNode $taskHvigor clean --no-daemon *> "$taskOut\clean-final.log"
if ($LASTEXITCODE -ne 0) {exit 1}
& $taskNode $taskHvigor --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon *> "$taskOut\build-final.log"
if ($LASTEXITCODE -ne 0) {Get-Content "$taskOut\build-final.log" -Tail 35; exit 1}
$taskHap='entry\build\default\outputs\default\entry-default-signed.hap'
Get-FileHash -LiteralPath $taskHap -Algorithm SHA256 | ConvertTo-Json | Set-Content -Encoding utf8 "$taskOut\signed-hap.json"
Copy-Item -LiteralPath $taskHap -Destination "$taskOut\Dayline-experience-signed.hap"
& 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' -t 127.0.0.1:5555 install -r $taskHap *> "$taskOut\install-final.log"
if ($LASTEXITCODE -ne 0) {exit 1}
python "$taskOut\ui.py" restart
Write-Output '237/237 passed; clean/full debug assembleHap/SignHap succeeded; final signed HAP installed.'
