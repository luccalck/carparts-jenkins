param([int]$WatchSeconds=0)
# Publica apenas resultados reais. Token GitHub continua no cofre local da CLI,
# fora do Jenkins, dos agents e do código de PRs.
$ErrorActionPreference='Stop'
$password=(Get-Content (Join-Path $PSScriptRoot '.env') | Where-Object {$_ -match '^JENKINS_CI_PASSWORD='}) -replace '^JENKINS_CI_PASSWORD=', ''
$headers=@{Authorization='Basic '+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('ci-user:'+$password.Trim()))}
$deadline=[DateTime]::UtcNow.AddSeconds($WatchSeconds)
$published=@{}
$records=@()
try {
    do {
        $ci=Invoke-RestMethod 'http://localhost:8082/job/carparts-ci/api/json?tree=jobs[name,url,lastBuild[number,building,result]]' -Headers $headers
        foreach($branch in $ci.jobs) {
            if(!$branch.lastBuild -or $branch.lastBuild.building) {continue}
            $build=Invoke-RestMethod "$($branch.url)$($branch.lastBuild.number)/api/json?tree=number,result,url,actions[lastBuiltRevision[SHA1]]" -Headers $headers
            $commit=@($build.actions | Where-Object {$_.lastBuiltRevision})[0].lastBuiltRevision.SHA1
            if($commit -notmatch '^[0-9a-f]{40}$') {continue}
            $key="$commit/$($build.number)/$($build.result)"
            if($published.ContainsKey($key)) {continue}
            $state=if($build.result -eq 'SUCCESS'){'success'}elseif($build.result -eq 'FAILURE'){'failure'}else{'error'}
            $result=gh api --method POST "repos/luccalck/carparts-jenkins/statuses/$commit" -f "state=$state" -f 'context=Jenkins/CI' -f "target_url=$($build.url)" -f "description=Jenkins: $($build.result), build $($build.number)" --jq '{id,sha,state,context,target_url,created_at}'
            if($LASTEXITCODE) {throw 'GitHub rejeitou status.'}
            $records+=($result | ConvertFrom-Json)
            $published[$key]=$true
            Write-Host "Status real publicado: $($branch.name), build $($build.number), $state"
        }
        if([DateTime]::UtcNow -lt $deadline) {Start-Sleep -Seconds 10}
    } while([DateTime]::UtcNow -lt $deadline)
    $destination=Join-Path (Split-Path $PSScriptRoot -Parent) 'evidencias\aws'
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    $records | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $destination 'github-status-jenkins.json') -Encoding utf8
} finally {$headers.Clear();$password=$null}
