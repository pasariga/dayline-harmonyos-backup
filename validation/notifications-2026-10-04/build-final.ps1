$ErrorActionPreference = 'Continue'
$env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'
$taskNode = 'C:\Program Files\Huawei\DevEco Studio\tools\node\node.exe'
$taskHvigor = 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js'
$taskOut = 'validation\notifications-2026-10-04'
& $taskNode $taskHvigor --mode module -p product=default -p module=entry@default test --no-daemon *> "$taskOut\test-final.log"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Copy-Item -LiteralPath 'entry\.test\default\intermediates\test\coverage_data\test_result.txt' -Destination "$taskOut\test-final-result.txt"
$taskResult = Get-Content -Raw -Encoding utf8 "$taskOut\test-final-result.txt"
if ($taskResult -notmatch 'Tests run: 200, Failure: 0, Error: 0, Pass: 200') { Write-Error 'Directional tests did not all pass.'; exit 1 }
& $taskNode $taskHvigor clean --no-daemon *> "$taskOut\clean-final.log"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $taskNode $taskHvigor --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon *> "$taskOut\build-final.log"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$taskHap = 'entry\build\default\outputs\default\entry-default-signed.hap'
Get-FileHash -LiteralPath $taskHap -Algorithm SHA256 | ConvertTo-Json | Set-Content -Encoding utf8 "$taskOut\signed-hap.json"
& 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' -t 127.0.0.1:5555 install -r $taskHap *> "$taskOut\install-final.log"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Output '200 tests passed; clean, full debug assembleHap, SignHap and latest signed HAP installation finished.'
exit 0
