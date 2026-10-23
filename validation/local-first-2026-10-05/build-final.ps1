$ErrorActionPreference = 'Continue'
$env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'
$taskNode = 'C:\Program Files\Huawei\DevEco Studio\tools\node\node.exe'
$taskHvigor = 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js'
$taskOut = 'validation\local-first-2026-10-05'
& $taskNode $taskHvigor --mode module -p product=default -p module=entry@default test --no-daemon *> "$taskOut\test-final.log"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Copy-Item -LiteralPath 'entry\.test\default\intermediates\test\coverage_data\test_result.txt' -Destination "$taskOut\test-final-result.txt"
if ((Get-Content -Raw -Encoding utf8 "$taskOut\test-final-result.txt") -notmatch 'Tests run: 230, Failure: 0, Error: 0, Pass: 230') { Write-Error 'Directional tests failed.'; exit 1 }
& $taskNode "$taskOut\release-check.cjs" *> "$taskOut\release-check.log"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $taskNode "$taskOut\business-time.cjs" *> "$taskOut\business-time.log"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $taskNode $taskHvigor clean --no-daemon *> "$taskOut\clean-final.log"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $taskNode $taskHvigor --mode module -p product=default -p module=entry@default -p buildMode=release assembleHap --no-daemon *> "$taskOut\build-final.log"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$taskHap = 'entry\build\default\outputs\default\entry-default-signed.hap'
Get-FileHash -LiteralPath $taskHap -Algorithm SHA256 | ConvertTo-Json | Set-Content -Encoding utf8 "$taskOut\signed-hap.json"
Copy-Item -LiteralPath $taskHap -Destination 'release\Dayline-1.0.0-release-signed.hap'
$env:PYTHONUTF8='1'
python "$taskOut\audit.py" *> "$taskOut\audit.log"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' -t 127.0.0.1:5555 install -r $taskHap *> "$taskOut\install-final.log"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Output '230 tests passed; clean, full release assembleHap, SignHap; final signed HAP installed. Existing debug signing profile preserved.'
