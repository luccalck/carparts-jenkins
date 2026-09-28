$ErrorActionPreference = 'Stop'
$project = $PSScriptRoot
$evidence = Join-Path (Split-Path $PSScriptRoot -Parent) 'evidencias\aws'
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
$bytes = New-Object byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
$env:WEBHOOK_SECRET = [Convert]::ToHexString($bytes)
$env:GITHUB_REPOSITORY = 'luccalck/carparts-jenkins'
$env:JENKINS_WEBHOOK_URL = 'http://controller:8080/github-webhook/'
$env:RELAY_BIND = '0.0.0.0'
try {
    foreach ($name in @('carparts-webhook-tunnel','carparts-webhook-relay')) {
        $existing = docker ps -a --filter "name=^/$name$" --format '{{.Names}}'
        if ($existing -eq $name) { docker rm -f $name | Out-Null }
    }
    $relay = Join-Path $project 'tools\webhook-relay.mjs'
    docker run -d --name carparts-webhook-relay --network carparts-jenkins_ci --network-alias webhook-relay `
      --memory 128m --cpus 0.25 --read-only --cap-drop ALL --security-opt no-new-privileges `
      -e WEBHOOK_SECRET -e GITHUB_REPOSITORY -e JENKINS_WEBHOOK_URL -e RELAY_BIND `
      --mount "type=bind,source=$relay,target=/app/relay.mjs,readonly" node:24-bookworm-slim node /app/relay.mjs | Out-Null
    if ($LASTEXITCODE) { throw 'Falha ao iniciar relay.' }
    $release = gh api repos/cloudflare/cloudflared/releases/latest --jq .tag_name
    if ($LASTEXITCODE -or $release -notmatch '^\d{4}\.\d+\.\d+$') { throw 'Versao Cloudflare invalida.' }
    docker run -d --name carparts-webhook-tunnel --network carparts-jenkins_ci --memory 128m --cpus 0.25 `
      "cloudflare/cloudflared:$release" tunnel --no-autoupdate --protocol http2 --url http://webhook-relay:8083 | Out-Null
    if ($LASTEXITCODE) { throw 'Falha ao iniciar tunnel.' }
    $public = $null
    for ($attempt=0; $attempt -lt 30; $attempt++) {
        $logs = docker logs carparts-webhook-tunnel 2>&1 | Out-String
        if ($logs -match 'https://[a-z0-9-]+\.trycloudflare\.com') { $public = $matches[0]; break }
        Start-Sleep -Seconds 2
    }
    if (!$public) { throw 'Quick tunnel nao forneceu URL no prazo.' }
    $body = @{name='web';active=$true;events=@('push','pull_request');config=@{url="$public/github-webhook/";content_type='json';insecure_ssl='0';secret=$env:WEBHOOK_SECRET}} | ConvertTo-Json -Depth 5 -Compress
    $hooks = gh api repos/luccalck/carparts-jenkins/hooks | ConvertFrom-Json
    $old = @($hooks | Where-Object { $_.config.url -match '\.trycloudflare\.com/github-webhook/$' })
    if ($old.Count -gt 1) { throw 'Mais de um hook de laboratorio: investigar antes de atualizar.' }
    if ($old.Count -eq 1) { $result = $body | gh api --method PATCH "repos/luccalck/carparts-jenkins/hooks/$($old[0].id)" --input - | ConvertFrom-Json }
    else { $result = $body | gh api --method POST repos/luccalck/carparts-jenkins/hooks --input - | ConvertFrom-Json }
    if ($LASTEXITCODE) { throw 'GitHub rejeitou a configuracao do webhook.' }
    $record = @{id=$result.id;url=$result.config.url;events=$result.events;configured_at=[DateTime]::UtcNow.ToString('o');endpoint='temporario; depende dos dois containers';secret='gerado em memoria, nao exportado'}
    $record | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $evidence 'webhook-configuracao.json') -Encoding utf8
    Write-Host "Webhook configurado: $($result.id), $public/github-webhook/"
    Write-Host 'Somente webhook assinado; Jenkins nao publicado. O segredo nao foi salvo em arquivo.'
} finally {
    foreach ($name in @('WEBHOOK_SECRET','GITHUB_REPOSITORY','JENKINS_WEBHOOK_URL','RELAY_BIND')) { [Environment]::SetEnvironmentVariable($name,$null,'Process') }
    $body = $null
}
