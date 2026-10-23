$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'
$env:PYTHONUTF8='1'
$taskNode='C:\Program Files\Huawei\DevEco Studio\tools\node\node.exe'
$taskHvigor='C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js'
$taskOut='validation/hardening-2026-10-19'
& $taskNode $taskHvigor --mode module -p product=default -p module=entry@default test --no-daemon *> "$taskOut/test-candidate.log"
if($LASTEXITCODE -ne 0){Get-Content "$taskOut/test-candidate.log" -Tail 25;exit 1}
Copy-Item entry/.test/default/intermediates/test/coverage_data/test_result.txt "$taskOut/test-candidate-result.txt"
python "$taskOut/audit.py" *> "$taskOut/audit.log"
if($LASTEXITCODE -ne 0){Get-Content "$taskOut/audit.log";exit 1}
& $taskNode $taskHvigor clean --no-daemon *> "$taskOut/clean-candidate.log"
if($LASTEXITCODE -ne 0){exit 1}
& $taskNode $taskHvigor --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon *> "$taskOut/build-candidate.log"
if($LASTEXITCODE -ne 0){Get-Content "$taskOut/build-candidate.log" -Tail 30;exit 1}
Get-FileHash entry/build/default/outputs/default/entry-default-signed.hap -Algorithm SHA256 | ConvertTo-Json | Set-Content -Encoding utf8 "$taskOut/candidate-hap.json"
Copy-Item entry/build/default/outputs/default/entry-default-signed.hap "$taskOut/Dayline-hardening-candidate-signed.hap"
& 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' -t 127.0.0.1:5555 shell 'bm uninstall -n com.gary.ddl -m entry_test' *> "$taskOut/uninstall-test-module.log"
& 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' -t 127.0.0.1:5555 install -r entry/build/default/outputs/default/entry-default-signed.hap *> "$taskOut/install-candidate.log"
if($LASTEXITCODE -ne 0){exit 1}
python "$taskOut/ui.py" restart
Write-Output 'Directed tests, clean, complete debug assembleHap/SignHap and candidate install succeeded.'
