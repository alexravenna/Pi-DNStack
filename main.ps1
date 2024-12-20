param(
    [Parameter(Mandatory = $false)]
    [ValidateScript({
            $fileInfo = New-Object System.IO.FileInfo($_)
            $fileInfo.Exists -and $fileInfo.Directory.Exists
        })]
    [string]$ConfigPath = "./main.psd1",

    [Parameter(Mandatory = $false)]
    [ValidateScript({
            $fileInfo = New-Object System.IO.FileInfo($_)
            $fileInfo.Exists -and $fileInfo.Directory.Exists
        })]
    [string]$InventoryPath = "./inventory.ini",

    [Parameter(Mandatory = $false)]
    [ValidateScript({
            $fileInfo = New-Object System.IO.FileInfo($_)
            $fileInfo.Exists -and $fileInfo.Directory.Exists
        })]
    [string]$TempPath = "./temp",

    [Parameter(Mandatory = $false)]
    # become method for ansible: https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_privilege_escalation.html
    [string]$become = "ask-become-pass"
)

Import-Module ./main.psm1

# install ansible locally
if (-Not (Get-Command ansible -ErrorAction SilentlyContinue)) {
    Write-Host "Ansible is not installed. Installing Ansible..."
    Install-Ansible
}
else {
    Write-Host "Ansible is already installed." -ForegroundColor Green
}

# temp folder to store hosts information for pwsh remoting
New-Item -Path $TempPath -ItemType Directory -Force
# install pwsh, docker on the remote host and get hosts information
Write-Host "Install dependencies on the remote host..."
# to work with $become, we need to use Invoke-Expression to pass the variable to the command
[string]$command = "ansible-playbook -i $InventoryPath ./ansible/master.yml --$become"
$output = Invoke-Expression $command
# check if the output of ansible contains a sudo password failure message
if ($output -match "Incorrect sudo password") {
    Write-Host "Error: Incorrect sudo password." -ForegroundColor Red
    exit 1
}

# get host information from ansible
[Array]$servers = Get-Content -Path "$TempPath/host_info.csv"
# cleanup
Remove-Item -Path $TempPath -Recurse -Force

# store the functions in variables to send them to the remote host
# based on https://stackoverflow.com/questions/11367367/how-do-i-include-a-locally-defined-function-when-using-powershells-invoke-comma#:~:text=%24fooDef%20%3D%20%22function%20foo%20%7B%20%24%7Bfunction%3Afoo%7D%20%7D%22%0A%0AInvoke%2DCommand%20%2DArgumentList%20%24fooDef%20%2DComputerName%20someserver.example.com%20%2DScriptBlock%20%7B%0A%20%20%20%20Param(%20%24fooDef%20)%0A%0A%20%20%20%20.%20(%5BScriptBlock%5D%3A%3ACreate(%24fooDef))%0A%0A%20%20%20%20Write%2DHost%20%22You%20can%20call%20the%20function%20as%20often%20as%20you%20like%3A%22%0A%20%20%20%20foo%20%22Bye%22%0A%20%20%20%20foo%20%22Adieu!%22%0A%7D
[string]$deployContainer = "function Deploy-Container { `n" + 
                   (Get-Command Deploy-Container).ScriptBlock.ToString() + 
"`n}"
[string]$deployPihole = "function Deploy-Pihole { `n" + 
                (Get-Command Deploy-Pihole).ScriptBlock.ToString() + 
"`n}"
[string]$deployUnbound = "function Deploy-Unbound { `n" + 
                 (Get-Command Deploy-Unbound).ScriptBlock.ToString() + 
"`n}"
[string]$deployCloudflared = "function Deploy-Cloudflared { `n" + 
                     (Get-Command Deploy-Cloudflared).ScriptBlock.ToString() + 
"`n}"
[string]$setPiholeConfiguration = "function Set-PiholeConfiguration { `n" + 
                     (Get-Command Set-PiholeConfiguration).ScriptBlock.ToString() +
"`n}"

# deploy the stack on each host
# deploying itself could be done trough ansible, but we will use PowerShell to make further changes
foreach ($server in $servers) {
    # make an ssh connection to the remote host
    [string]$hostname, $username = $server -split ','
    $session = New-PSSession -HostName $hostname -UserName $username -SSHTransport
    
    # get the data from the .psd1 file
    [hashtable]$data = Get-Data -ConfigPath $ConfigPath
    
    # deploy the stack on the remote host
    Invoke-Command -Session $session -ScriptBlock {
        param([hashtable]$data,
            [Parameter(Mandatory = $true)]
            [string]$deployContainer, 
            [Parameter(Mandatory = $true)]
            [string]$deployPihole, 
            [Parameter(Mandatory = $true)]
            [string]$deployUnbound, 
            [Parameter(Mandatory = $true)]
            [string]$deployCloudflared,
            [Parameter(Mandatory = $true)]
            [string]$setPiholeConfiguration)
        # recreate the functions on the remote host
        . ([ScriptBlock]::Create($deployContainer))
        . ([ScriptBlock]::Create($deployPihole))
        . ([ScriptBlock]::Create($deployUnbound))
        . ([ScriptBlock]::Create($deployCloudflared))
        . ([ScriptBlock]::Create($setPiholeConfiguration))

        # pihole
        Deploy-Pihole -data $data
        
        # unbound
        if ($data['unboundEnabled']) {
            Deploy-Unbound -data $data
        }
        else {
            Write-Host "Unbound is disabled."
        }
        
        # cloudflared
        if ($data['cloudflaredEnabled']) {
            Deploy-Cloudflared -data $data
        }
        else {
            Write-Host "Cloudflared is disabled."
        }

        # config
        Set-PiholeConfiguration -data $data
    } -ArgumentList $data, $deployContainer, $deployPihole, $deployUnbound, $deployCloudflared, $setPiholeConfiguration
    
    # cleanup
    Remove-PSSession -Session $session
}