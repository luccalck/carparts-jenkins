$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$settings = @{}
Get-Content -LiteralPath (Join-Path $PSScriptRoot '.env') | ForEach-Object {
    if ($_ -match '^\s*([A-Z0-9_]+)\s*=(.*)$') {
        $settings[$matches[1]] = $matches[2].Trim().Trim('"').Trim("'")
    }
}
if (!$settings['JENKINS_ADMIN_PASSWORD']) { throw 'Preencha JENKINS_ADMIN_PASSWORD no .env.' }
$basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('admin:' + $settings['JENKINS_ADMIN_PASSWORD']))
$headers = @{ Authorization = 'Basic ' + $basic }
$nodes = @{ 'quality-1' = 'QUALITY1_SECRET'; 'quality-2' = 'QUALITY2_SECRET'; 'release' = 'RELEASE_SECRET' }
foreach ($name in $nodes.Keys) {
    $response = Invoke-WebRequest -UseBasicParsing -TimeoutSec 20 -Uri "http://127.0.0.1:8082/computer/$name/jenkins-agent.jnlp" -Headers $headers
    $content = $response.Content
    if ($content -is [byte[]]) { $content = [Text.Encoding]::UTF8.GetString($content) }
    [xml]$jnlp = $content
    $secret = [string]$jnlp.jnlp.'application-desc'.argument[0]
    if ($secret -notmatch '^[a-fA-F0-9]{64}$') { throw "Jenkins nao forneceu uma chave valida para $name." }
    [Environment]::SetEnvironmentVariable($nodes[$name], $secret, 'Process')
}
try {
    docker compose --profile agents up -d --no-build
    if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel iniciar os containers.' }
    Write-Host 'Agents iniciados. As chaves nao foram gravadas em arquivos.'
} finally {
    foreach ($variable in $nodes.Values) { [Environment]::SetEnvironmentVariable($variable, $null, 'Process') }
}
