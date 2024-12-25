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
foreach ($server in $servers) {
    # make an ssh connection to the remote host
    [string]$hostname, $username = $server -split ','
    $session = New-PSSession -HostName $hostname -UserName $username -SSHTransport
    
    # deploy the stack on the remote host
    Invoke-Command -Session $session -ScriptBlock {
        param([Parameter(Mandatory = $true)]        
            [hashtable]$data,
            [Parameter(Mandatory = $true)]
            [array]$functionDefinitions)
        # recreate the functions on the remote host
        foreach ($functionDef in $functionDefinitions) {
            . ([ScriptBlock]::Create($functionDef))
        }

        # remove unbound/cloudflared containers if they are disabled
        Remove-OldContainers -data $data

        # all deployments are declarative
        Deploy-Pihole -data $data
        
        if ($data['unboundEnabled']) {
            Deploy-Unbound -data $data
        }
        else {
            Write-Host "Skipping Unbound deployment..."
        }
        
        if ($data['cloudflaredEnabled']) {
            Deploy-Cloudflared -data $data
        }
        else {
            Write-Host "Skipping Cloudflared deployment..."
        }

        Set-PiholeConfiguration -data $data

        Write-Host "Stack deployed successfully on $hostname" -ForegroundColor Green
    } -ArgumentList $data, $functionsDefinitions
    
    # cleanup
    Remove-PSSession -Session $session
}