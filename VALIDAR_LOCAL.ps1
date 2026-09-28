$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$password = $null
Get-Content -LiteralPath '.env' | ForEach-Object {
    if ($_ -match '^JENKINS_ADMIN_PASSWORD=(.*)$') { $password = $matches[1].Trim().Trim('"').Trim("'") }
}
if (!$password) { throw 'Senha administrativa ausente no .env.' }
$headers = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('admin:' + $password)) }
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$base = 'http://127.0.0.1:8082'
$crumb = Invoke-RestMethod -Uri "$base/crumbIssuer/api/json" -Headers $headers -WebSession $session
$headers[$crumb.crumbRequestField] = $crumb.crumb
function Post-Xml($url, $xml) {
    Invoke-WebRequest -UseBasicParsing -Uri $url -Method Post -ContentType 'application/xml; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($xml)) -Headers $headers -WebSession $session | Out-Null
}
try { Invoke-WebRequest -UseBasicParsing -Uri "$base/job/carparts-release/api/json" -Headers $headers | Out-Null }
catch { Post-Xml "$base/createItem?name=carparts-release" '<com.cloudbees.hudson.plugins.folder.Folder><description>Release de laboratorio</description></com.cloudbees.hudson.plugins.folder.Folder>' }
$script = [Security.SecurityElement]::Escape((Get-Content -Raw 'Jenkinsfile.local'))
$xml = @"
<flow-definition plugin="workflow-job">
  <description>Validacao local real. Nao representa deploy Azure.</description>
  <properties><org.jenkinsci.plugins.authorizeproject.AuthorizeProjectProperty>
    <strategy class="org.jenkinsci.plugins.authorizeproject.strategy.SpecificUsersAuthorizationStrategy"><userid>release-manager</userid><dontRestrictJobConfiguration>false</dontRestrictJobConfiguration></strategy>
  </org.jenkinsci.plugins.authorizeproject.AuthorizeProjectProperty></properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition"><script>$script</script><sandbox>true</sandbox></definition>
  <triggers/><disabled>false</disabled>
</flow-definition>
"@
$job = "$base/job/carparts-release/job/validacao-local"
try { Invoke-WebRequest -UseBasicParsing -Uri "$job/api/json" -Headers $headers | Out-Null; Post-Xml "$job/config.xml" $xml }
catch { Post-Xml "$base/job/carparts-release/createItem?name=validacao-local" $xml }
$bundle = Join-Path ([IO.Path]::GetTempPath()) ('carparts-source-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $bundle | Out-Null
foreach ($file in @('package.json','package-lock.json','Dockerfile','src','scripts','test','tools')) { Copy-Item -LiteralPath $file -Destination $bundle -Recurse }
foreach ($service in @('quality-1','quality-2','release')) {
    docker cp "$bundle/." "carparts-jenkins-${service}-1:/home/jenkins/lab-src"
    if ($LASTEXITCODE -ne 0) { throw "Falha ao copiar codigo para $service." }
}
Invoke-WebRequest -UseBasicParsing -Uri "$job/build" -Method Post -Headers $headers -WebSession $session | Out-Null
Write-Host "Validacao iniciada: $job/"
Write-Host "Fonte temporaria sem senhas: $bundle"
