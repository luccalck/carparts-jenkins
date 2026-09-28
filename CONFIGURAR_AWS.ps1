param(
    [ValidateSet('Configure','Start','Status','Approve','Collect')][string]$Action = 'Configure',
    [switch]$Preflight,
    [switch]$Rollback,
    [int]$Build = 0
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$password = $null
Get-Content -LiteralPath '.env' | ForEach-Object {
    if ($_ -match '^JENKINS_ADMIN_PASSWORD=(.*)$') { $password = $matches[1].Trim().Trim('"').Trim("'") }
}
if (!$password) { throw 'Senha administrativa ausente no .env local.' }
$headers = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('admin:' + $password)) }
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$base = 'http://127.0.0.1:8082'
$job = "$base/job/carparts-release/job/aws-release"
$crumb = Invoke-RestMethod -Uri "$base/crumbIssuer/api/json" -Headers $headers -WebSession $session
$headers[$crumb.crumbRequestField] = $crumb.crumb
function Post-Xml($url, $xml) {
    Invoke-WebRequest -UseBasicParsing -Uri $url -Method Post -ContentType 'application/xml; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($xml)) -Headers $headers -WebSession $session | Out-Null
}
function Save-Job($url, $create, $xml) {
    $exists = $false
    try { Invoke-RestMethod -Uri "$url/api/json" -Headers $headers | Out-Null; $exists = $true } catch {
        if ([int]$_.Exception.Response.StatusCode -ne 404) { throw }
    }
    if ($exists) { Post-Xml "$url/config.xml" $xml } else { Post-Xml $create $xml }
}
switch ($Action) {
    Configure {
        $ids = (Invoke-RestMethod -Uri "$base/job/carparts-release/credentials/store/folder/domain/_/api/json?tree=credentials[id,typeName]" -Headers $headers).credentials.id
        foreach ($id in @('aws-lab-access-key','aws-lab-secret-key','aws-lab-session-token')) {
            if ($id -notin $ids) { throw "Credencial $id nao encontrada no store Folder da pasta carparts-release." }
        }
        $xml = @'
<flow-definition plugin="workflow-job">
 <description>Publicacao AWS Academy por digest, com homologacao, aprovacao e rollback.</description>
 <properties><org.jenkinsci.plugins.authorizeproject.AuthorizeProjectProperty>
  <strategy class="org.jenkinsci.plugins.authorizeproject.strategy.SpecificUsersAuthorizationStrategy"><userid>release-manager</userid><dontRestrictJobConfiguration>false</dontRestrictJobConfiguration></strategy>
 </org.jenkinsci.plugins.authorizeproject.AuthorizeProjectProperty>
 <hudson.model.ParametersDefinitionProperty><parameterDefinitions>
  <hudson.model.BooleanParameterDefinition><name>PREFLIGHT_ONLY</name><defaultValue>false</defaultValue></hudson.model.BooleanParameterDefinition>
  <hudson.model.BooleanParameterDefinition><name>ROLLBACK</name><defaultValue>false</defaultValue></hudson.model.BooleanParameterDefinition>
 </parameterDefinitions></hudson.model.ParametersDefinitionProperty></properties>
 <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition">
  <scm class="hudson.plugins.git.GitSCM"><configVersion>2</configVersion><userRemoteConfigs><hudson.plugins.git.UserRemoteConfig><url>https://github.com/luccalck/carparts-jenkins.git</url></hudson.plugins.git.UserRemoteConfig></userRemoteConfigs><branches><hudson.plugins.git.BranchSpec><name>*/main</name></hudson.plugins.git.BranchSpec></branches><doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations><submoduleCfg class="empty-list"/><extensions/></scm>
  <scriptPath>Jenkinsfile.aws</scriptPath><lightweight>true</lightweight>
 </definition><triggers/><disabled>false</disabled>
</flow-definition>
'@
        Save-Job $job "$base/job/carparts-release/createItem?name=aws-release" $xml
        $ci = @'
<org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject>
 <description>CI de branches e PRs; sem credenciais AWS; polling enquanto Jenkins for local.</description>
 <properties/>
 <sources class="jenkins.branch.MultiBranchProject$BranchSourceList"><data><jenkins.branch.BranchSource>
  <source class="org.jenkinsci.plugins.github_branch_source.GitHubSCMSource"><id>carparts-github</id><repoOwner>luccalck</repoOwner><repository>carparts-jenkins</repository><traits>
   <org.jenkinsci.plugins.github__branch__source.BranchDiscoveryTrait><strategyId>3</strategyId></org.jenkinsci.plugins.github__branch__source.BranchDiscoveryTrait>
   <org.jenkinsci.plugins.github__branch__source.OriginPullRequestDiscoveryTrait><strategyId>1</strategyId></org.jenkinsci.plugins.github__branch__source.OriginPullRequestDiscoveryTrait>
  </traits></source>
  <strategy class="jenkins.branch.DefaultBranchPropertyStrategy"><properties class="empty-list"/></strategy>
 </jenkins.branch.BranchSource></data><owner class="org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject" reference="../.."/></sources>
 <factory class="org.jenkinsci.plugins.workflow.multibranch.WorkflowBranchProjectFactory"><owner class="org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject" reference="../.."/><scriptPath>Jenkinsfile.ci</scriptPath></factory>
 <orphanedItemStrategy class="com.cloudbees.hudson.plugins.folder.computed.DefaultOrphanedItemStrategy"><pruneDeadBranches>true</pruneDeadBranches><daysToKeep>7</daysToKeep><numToKeep>20</numToKeep></orphanedItemStrategy>
 <triggers><com.cloudbees.hudson.plugins.folder.computed.PeriodicFolderTrigger><spec>H/5 * * * *</spec><interval>300000</interval></com.cloudbees.hudson.plugins.folder.computed.PeriodicFolderTrigger></triggers>
</org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject>
'@
        Save-Job "$base/job/carparts-ci" "$base/createItem?name=carparts-ci" $ci
        Invoke-WebRequest -UseBasicParsing -PreserveAuthorizationOnRedirect -Uri "$base/job/carparts-ci/build" -Method Post -Headers $headers -WebSession $session | Out-Null
        Write-Host 'Jobs configurados. Tres IDs de credenciais conferidos sem ler seus valores.'
        Write-Host "$job/"
    }
    Start {
        $body = @{PREFLIGHT_ONLY=$Preflight.IsPresent.ToString().ToLower();ROLLBACK=$Rollback.IsPresent.ToString().ToLower()}
        Invoke-WebRequest -UseBasicParsing -Uri "$job/buildWithParameters" -Method Post -Body $body -Headers $headers -WebSession $session | Out-Null
        Write-Host 'Execucao solicitada.'
    }
    Status {
        $state = Invoke-RestMethod -Uri "$job/api/json?tree=lastBuild[number,building,result,url],queueItem[id]" -Headers $headers
        $state | ConvertTo-Json -Depth 5
        if ($state.lastBuild) {
            $n = $state.lastBuild.number
            Invoke-RestMethod -Uri "$job/$n/wfapi/describe" -Headers $headers | ConvertTo-Json -Depth 8
        }
    }
    Approve {
        if (!$Build) { throw 'Informe -Build com o numero exato da execucao a aprovar.' }
        Invoke-WebRequest -UseBasicParsing -Uri "$job/$Build/input/promover/proceedEmpty" -Method Post -Headers $headers -WebSession $session | Out-Null
        Write-Host "Aprovacao registrada como admin na execucao $Build, sob autorizacao do usuario."
    }
    Collect {
        if (!$Build) { throw 'Informe -Build para coletar a execucao real.' }
        $destination = Join-Path (Split-Path $PSScriptRoot -Parent) 'evidencias\aws'
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Invoke-WebRequest -UseBasicParsing -Uri "$job/$Build/consoleText" -Headers $headers -OutFile (Join-Path $destination "jenkins-aws-build-$Build.txt")
        $data = Invoke-RestMethod -Uri "$job/$Build/api/json?tree=number,result,timestamp,duration,artifacts[fileName,relativePath]" -Headers $headers
        $data | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $destination "jenkins-aws-build-$Build.json") -Encoding utf8
        foreach ($artifact in $data.artifacts) {
            $path = $artifact.relativePath
            Invoke-WebRequest -UseBasicParsing -Uri "$job/$Build/artifact/$path" -Headers $headers -OutFile (Join-Path $destination "build-$Build-$($artifact.fileName)")
        }
        Write-Host "Evidencias reais salvas em $destination"
    }
}
$password = $null
$headers.Clear()
