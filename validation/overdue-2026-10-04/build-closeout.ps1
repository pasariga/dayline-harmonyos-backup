$ErrorActionPreference = 'Continue'
$env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'
$taskNode = 'C:\Program Files\Huawei\DevEco Studio\tools\node\node.exe'
$taskHvigor = 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js'
$taskOut = 'validation\overdue-2026-10-04'
& $taskNode $taskHvigor --mode module -p product=default -p module=entry@default test --no-daemon *> "$taskOut\test-release.log"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Copy-Item -LiteralPath 'entry\.test\default\intermediates\test\coverage_data\test_result.txt' -Destination "$taskOut\test-release-result.txt"
& $taskNode $taskHvigor clean --no-daemon *> "$taskOut\clean-release.log"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $taskNode $taskHvigor --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon *> "$taskOut\build-release.log"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$taskHap = 'entry\build\default\outputs\default\entry-default-signed.hap'
Get-FileHash -LiteralPath $taskHap -Algorithm SHA256 | ConvertTo-Json | Set-Content -Encoding utf8 "$taskOut\release-hap.json"
& 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' -t 127.0.0.1:5555 install -r $taskHap *> "$taskOut\release-install.log"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Output 'Final tests, clean, complete signed build and fresh package installation finished.'
exit 0
