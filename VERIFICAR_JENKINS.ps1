$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$password = $null
Get-Content -LiteralPath '.env' | ForEach-Object {
    if ($_ -match '^JENKINS_ADMIN_PASSWORD=(.*)$') { $password = $matches[1].Trim().Trim('"').Trim("'") }
}
$headers = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('admin:' + $password)) }
$base = 'http://127.0.0.1:8082'
$plugins = Invoke-RestMethod -TimeoutSec 20 -Headers $headers "$base/pluginManager/api/json?tree=plugins[shortName,version,active,enabled]"
$invalid = @($plugins.plugins | Where-Object { $_.enabled -and !$_.active })
Write-Host "Plugins habilitados e inativos: $($invalid.Count)"
$invalid | Select-Object shortName,version | Format-Table
$nodes = Invoke-RestMethod -TimeoutSec 20 -Headers $headers "$base/computer/api/json?tree=computer[displayName,offline,numExecutors]"
$nodes.computer | Select-Object displayName,offline,numExecutors | Format-Table
try {
    $build = Invoke-RestMethod -TimeoutSec 20 -Headers $headers "$base/job/carparts-release/job/validacao-local/lastBuild/api/json?tree=number,result,building,duration,url"
    $build | Select-Object number,result,building,duration,url | Format-List
    if (!$build.building) {
        $tests = Invoke-RestMethod -TimeoutSec 20 -Headers $headers "$base/job/carparts-release/job/validacao-local/lastBuild/testReport/api/json?tree=passCount,failCount,skipCount"
        $tests | Format-List
    }
} catch { Write-Host 'Validacao local ainda nao disponivel ou sem relatorio de testes.' }
