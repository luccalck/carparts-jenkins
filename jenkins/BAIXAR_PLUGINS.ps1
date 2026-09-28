$ErrorActionPreference = 'Stop'
$cache = Join-Path $PSScriptRoot '.plugin-cache'
New-Item -ItemType Directory -Force -Path $cache | Out-Null
$center = Invoke-RestMethod -TimeoutSec 30 'https://updates.jenkins.io/current/update-center.actual.json'
$items = foreach ($line in Get-Content (Join-Path $PSScriptRoot 'plugins.txt')) {
    if ($line -match '^([^:#]+):(.+)$') {
        $id = $matches[1]; $version = $matches[2]
        $metadata = $center.plugins.$id
        if ($metadata.version -ne $version) { throw "A versao de $id mudou. Revise o lock antes de baixar." }
        [pscustomobject]@{ Id=$id; Version=$version; Sha=$metadata.sha256; Cache=$cache }
    }
}
$items | ForEach-Object -ThrottleLimit 6 -Parallel {
    $ErrorActionPreference = 'Stop'
    $path = Join-Path $_.Cache ($_.Id + '.jpi')
    $url = 'https://ftp.halifax.rwth-aachen.de/jenkins/plugins/' + $_.Id + '/' + $_.Version + '/' + $_.Id + '.hpi'
    if (!(Test-Path $path)) { Invoke-WebRequest -TimeoutSec 45 -Uri $url -OutFile $path }
    $bytes = [Convert]::FromHexString((Get-FileHash -Algorithm SHA256 $path).Hash)
    if ([Convert]::ToBase64String($bytes) -ne $_.Sha) { throw "Integridade invalida: $($_.Id)" }
    Write-Host "Verificado: $($_.Id)"
}
