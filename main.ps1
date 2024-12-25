param(
    [Parameter(Mandatory = $false)]
    [ValidateScript({
            # with help of qwen to use system.io.path
            $fullPath = [System.IO.Path]::GetFullPath($_)
            [System.IO.File]::Exists($fullPath) -and [System.IO.Directory]::Exists([System.IO.Path]::GetDirectoryName($fullPath))
        })]
    [string]$ConfigPath = "./main.psd1",

    [Parameter(Mandatory = $false)]
    [ValidateScript({
            $fullPath = [System.IO.Path]::GetFullPath($_)
            [System.IO.File]::Exists($fullPath) -and [System.IO.Directory]::Exists([System.IO.Path]::GetDirectoryName($fullPath))
        })]
    [string]$InventoryPath = "./inventory.ini",

    [Parameter(Mandatory = $false)]
    [ValidateScript({
            $fullPath = [System.IO.Path]::GetFullPath($_)
            [System.IO.Directory]::Exists($fullPath)
        })]
    [string]$TempPath = "./temp",

    [Parameter(Mandatory = $false)]
    # become method for ansible: https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_privilege_escalation.html
    [string]$become = "ask-become-pass"
)

Import-Module ./main.psm1

# get the data from the .psd1 file
[hashtable]$data = Get-Data -ConfigPath $ConfigPath

# install ansible locally
Install-Ansible

# install docker and pwsh on the remote host
Install-DependenciesRemotely -TempPath $TempPath -InventoryPath $InventoryPath -become $become

# get host information from ansible (outputted during remote dependencies installation)
[Array]$servers = Get-Content -Path "$TempPath/host_info.csv"
# cleanup
Remove-Item -Path $TempPath -Recurse -Force

# store the needed functions from the module in variables to send them to the remote host
$functions = @("Deploy-Container", 
    "Deploy-Pihole", 
    "Deploy-Unbound", 
    "Deploy-Cloudflared", 
    "Set-PiholeConfiguration", 
    "Invoke-CommandWithCheck", 
    "ConfigDifferent", 
    "Get-CurrentContainerConfig", 
    "Remove-OldContainers")
$functionsDefinitions = Get-FunctionDefinitions -functions $functions

# deploy the stack on each host
# deploying itself could be done trough ansible, but we will use PowerShell to make further changes
$serverDeploymentJobs = @()
foreach ($server in $servers) {
    $serverDeploymentJobs += Start-ThreadJob -ScriptBlock {
        param([Parameter(Mandatory = $true)]
            [string]$server,
            [Parameter(Mandatory = $true)]
            [hashtable]$data,
            [Parameter(Mandatory = $true)]
            [array]$functionsDefinitions)

        # make an ssh connection to the remote host
        [string]$hostname, $username = $server -split ','
        $session = New-PSSession -HostName $hostname -UserName $username -SSHTransport
    
        # deploy the stack on the remote host
        Invoke-Command -Session $session -ScriptBlock {
            param([Parameter(Mandatory = $true)]        
                [hashtable]$data,
                [Parameter(Mandatory = $true)]
                [array]$functionDefinitions)

            # recreate the functions on the remote host, this can not be multi-threaded due to pwsh scoping see https://stackoverflow.com/questions/77900019/piping-to-where-object-and-foreach-object-not-working-in-module-delayed-loaded-i/77903771#77903771 unless doing dirty hacks
            $functionDefinitions | ForEach-Object {
                . ([ScriptBlock]::Create($_))
            }

            # get the body of the function to recreate it in the thread
            # see https://stackoverflow.com/questions/75609709/start-threadjob-is-not-detecting-my-variables-i-pass-to-it for passing variables to the thread
            $deployContainerAst = ${function:Deploy-Container}.Ast.Body
            $deployPiholeAst = ${function:Deploy-Pihole}.Ast.Body
            $getContainerConfigAst = ${function:Get-CurrentContainerConfig}.Ast.Body
            $configDifferenceAst = ${function:ConfigDifferent}.Ast.Body
            $deployUnboundAst = ${function:Deploy-Unbound}.Ast.Body
            $deployCloudflaredAst = ${function:Deploy-Cloudflared}.Ast.Body
            @(  # remove unbound/cloudflared containers if they are disabled
                Start-ThreadJob ${function:Remove-OldContainers} -ArgumentList $data
                # all deployments are declarative
                Start-ThreadJob -ScriptBlock {
                    param($data, $deployContainerAst, $getContainerConfigAst, $configDifferenceAst, $deployPiholeAst)
                    ${function:Deploy-Container} = $deployContainerAst.GetScriptBlock()
                    ${function:Get-CurrentContainerConfig} = $getContainerConfigAst.GetScriptBlock()
                    ${function:ConfigDifferent} = $configDifferenceAst.GetScriptBlock()
                    & $deployPiholeAst.GetScriptBlock() -data $data
                } -ArgumentList  $data, $deployContainerAst, $getContainerConfigAst, $configDifferenceAst, $deployPiholeAst
                Start-ThreadJob -ScriptBlock {
                    param($data, $deployContainerAst, $getContainerConfigAst, $configDifferenceAst, $deployUnboundAst)
                    if ($data['unboundEnabled']) {
                        ${function:Deploy-Container} = $deployContainerAst.GetScriptBlock()
                        ${function:Get-CurrentContainerConfig} = $getContainerConfigAst.GetScriptBlock()
                        ${function:ConfigDifferent} = $configDifferenceAst.GetScriptBlock()
                        & $deployUnboundAst.GetScriptBlock() -data $data
                    }
                    else {
                        Write-Host "Skipping Unbound deployment..."
                    }
                } -ArgumentList $data, $deployContainerAst, $getContainerConfigAst, $configDifferenceAst, $deployUnboundAst
                Start-ThreadJob -ScriptBlock {
                    param($data, $deployContainerAst, $getContainerConfigAst, $configDifferenceAst, $deployCloudflaredAst)
                    if ($data['cloudflaredEnabled']) {
                        ${function:Deploy-Container} = $deployContainerAst.GetScriptBlock()
                        ${function:Get-CurrentContainerConfig} = $getContainerConfigAst.GetScriptBlock()
                        ${function:ConfigDifferent} = $configDifferenceAst.GetScriptBlock()
                        & $deployCloudflaredAst.GetScriptBlock() -data $data
                    }
                    else {
                        Write-Host "Skipping Cloudflared deployment..."
                    }
                } -ArgumentList $data, $deployContainerAst, $getContainerConfigAst, $configDifferenceAst, $deployCloudflaredAst
            )  | Wait-Job | Receive-Job | Remove-Job

            Set-PiholeConfiguration -data $data

        } -ArgumentList $data, $functionsDefinitions
    
        Write-Host "Stack deployed on $hostname"
        # cleanup
        Remove-PSSession -Session $session
    } -ArgumentList $server, $data, $functionsDefinitions
}

$serverDeploymentJobs | ForEach-Object {
    $job = Wait-Job $_
    # cath the output of the remote host and print it
    $job.Information | ForEach-Object { Write-Host $_ }
    # cleanup
    Remove-Job $_
}