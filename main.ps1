function Install-Ansible{
    # see https://docs.ansible.com/ansible/latest/installation_guide/installation_distros.html
    function Install-Ansible-Ubuntu-Debian {
        Write-Host "Installing Ansible on Debian-based system..."
        sudo apt update
        sudo apt install -y software-properties-common
        sudo add-apt-repository --yes --update ppa:ansible/ansible
        sudo apt install -y ansible
    }

    function Install-Ansible-RHEL {
        Write-Host "Installing Ansible on RHEL-based system..."
        sudo dnf install -y ansible
    }

    function Install-Ansible-Arch {
        Write-Host "Installing Ansible on Arch-based system..."
        sudo pacman -Sy ansible
    }

    if (Get-Command dnf -ErrorAction SilentlyContinue) {
        Install-Ansible-RHEL
    } elseif (Get-Command apt -ErrorAction SilentlyContinue) {
        Install-Ansible-Ubuntu-Debian
    } elseif (Get-Command pacman -ErrorAction SilentlyContinue) {
        Install-Ansible-Arch
    } elseif ($IsWindows) {
        Write-Host "Windows not supported. Please use WSL." -ForegroundColor Red
    } else {
        Write-Host "Unsupported Linux distribution. Please install Ansible manually." -ForegroundColor Red
        exit 1
    }

    # verify installation
    if (-Not (Get-Command ansible -ErrorAction SilentlyContinue)) {
        Write-Host "Ansible installation failed. Please install Ansible manually." -ForegroundColor Red
        exit 1
    } else {
        Write-Host "Ansible installed successfully." -ForegroundColor Green
    }
}

# install ansible locally
if (-Not (Get-Command ansible -ErrorAction SilentlyContinue)) {
    Write-Host "Ansible is not installed. Installing Ansible..."
    Install-Ansible
} else {
    Write-Host "Ansible is already installed." -ForegroundColor Green
}

# temp folder to store hosts information for pwsh remoting
New-Item -Path "./temp" -ItemType Directory -Force
# install pwsh, docker on the remote host and get hosts
Write-Host "Install dependencies on the remote host..."
ansible-playbook -i ./inventory.ini ./ansible/master.yml --ask-become-pass

# get host information from ansible
$servers = Get-Content -Path "./temp/host_info.csv"
# cleanup
Remove-Item -Path "./temp" -Recurse -Force

function Get-Data {
    [hashtable]$data = Import-PowerShellDataFile -Path "./main.psd1"
    [hashtable]$defaultValues = @{
        restartPolicy = "unless-stopped"
        stackName = "auto_deployed"
        containerNetwork = "bridge"

        piholeImage = "pihole/pihole:latest"
        piholePort = "80"
        piholePassword = "admin"

        unboundEnabled = $true
        unboundImage = "mvance/unbound:latest"
        unboundPort = "53"
        unboundConfig = "/etc/unbound/unbound.conf"

        cloudflaredEnabled = $true
        cloudflaredImage = "cloudflare/cloudflared:latest"
        cloudflaredPort = "5053"
        cloudflaredConfig = "/etc/cloudflared/config.yml"

        piholeVolumes = [array]@("/etc/pihole:/etc/pihole", "/etc-dnsmasq.d:/etc/dnsmasq.d")
        unboundVolumes = [array]@("/etc/unbound:/etc/unbound")
        cloudflaredVolumes = [array]@("/etc/cloudflared:/etc/cloudflared")

        commonFlags = ""
        piholeFlags = ""
        unboundFlags = ""
        cloudflaredFlags = ""
    }

    
    # set default values for .psd1 if not provided
    foreach ($key in $defaultValues.Keys) {
        if (-Not $data.ContainsKey($key)) {
            $data.Add($key, $defaultValues[$key])
        }
    }

    return $data
}


function Deploy-Container {
    param(
        [string]$name,
        [string]$image,
        [string]$network,
        [string]$restartPolicy,
        [string]$portMapping,
        [array]$volumes,
        [string]$flags
        )
        Write-Host "Deploying $name..."
        $command = "docker run -d --name $name --restart $restartPolicy --network $network $portMapping $flags"
        foreach ($volume in $volumes) {
            $command += " -v $volume"
        }
        $command += " $image"
        
        Invoke-Expression $command
}
    
function Deploy-Pihole {
    param($data)
    Deploy-Container -name "$($data['stackName'])_pihole" `
    -image "pihole/pihole" `
    -network $data['containerNetwork'] `
    -restartPolicy $data['restartPolicy'] `
    -portMapping "-p $($data['piholePort']):80" `
    -volumes $data['piholeVolumes'] `
    -flags $data['piholeFlags']
}

function Deploy-Unbound {
    param($data)
    $image = if ((uname -m) -eq "x86_64") { "mvance/unbound" } else { "mvance/unbound-rpi" }
    Deploy-Container -name "$($data['stackName'])_unbound" `
    -image $image `
    -network $data['containerNetwork'] `
    -restartPolicy $data['restartPolicy'] `
    -portMapping "-p $($data['unboundPort']):53" `
    -volumes $data['unboundVolumes'] `
    -flags $data['unboundFlags']
}

function Deploy-Cloudflared {
    param($data)
    Deploy-Container -name "$($data['stackName'])_cloudflared" `
    -image "cloudflare/cloudflared" `
    -network $data['containerNetwork'] `
    -restartPolicy $data['restartPolicy'] `
    -portMapping "-p $($data['cloudflaredPort']):5053" `
    -volumes $data['cloudflaredVolumes'] `
    -flags $data['cloudflaredFlags']
}

# store the functions in variables to send them to the remote host
# based on https://stackoverflow.com/questions/11367367/how-do-i-include-a-locally-defined-function-when-using-powershells-invoke-comma#:~:text=%24fooDef%20%3D%20%22function%20foo%20%7B%20%24%7Bfunction%3Afoo%7D%20%7D%22%0A%0AInvoke%2DCommand%20%2DArgumentList%20%24fooDef%20%2DComputerName%20someserver.example.com%20%2DScriptBlock%20%7B%0A%20%20%20%20Param(%20%24fooDef%20)%0A%0A%20%20%20%20.%20(%5BScriptBlock%5D%3A%3ACreate(%24fooDef))%0A%0A%20%20%20%20Write%2DHost%20%22You%20can%20call%20the%20function%20as%20often%20as%20you%20like%3A%22%0A%20%20%20%20foo%20%22Bye%22%0A%20%20%20%20foo%20%22Adieu!%22%0A%7D
$deployContainer = "function Deploy-Container {`n" + 
                   (Get-Command Deploy-Container).ScriptBlock.ToString() + 
                   "`n}"
$deployPihole = "function Deploy-Pihole {`n" + 
                (Get-Command Deploy-Pihole).ScriptBlock.ToString() + 
                "`n}"
$deployUnbound = "function Deploy-Unbound {`n" + 
                 (Get-Command Deploy-Unbound).ScriptBlock.ToString() + 
                 "`n}"
$deployCloudflared = "function Deploy-Cloudflared {`n" + 
                     (Get-Command Deploy-Cloudflared).ScriptBlock.ToString() + 
                     "`n}"

# deploy the stack on each host
# deploying itself could be done trough ansible, but we will use PowerShell to make further changes
foreach ($server in $servers) {
    # make an ssh connection to the remote host
    $hostname = ($server -split ',')[0]
    $username = ($server -split ',')[1]
    $session = New-PSSession -HostName $hostname -UserName $username -SSHTransport
    
    # get the data from the .psd1 file
    $data = Get-Data
    
    # deploy the stack on the remote host
    Invoke-Command -Session $session -ScriptBlock {
        param($data, $deployContainer, $deployPihole, $deployUnbound, $deployCloudflared)
        # recreate the functions on the remote host
        . ([ScriptBlock]::Create($deployContainer))
        . ([ScriptBlock]::Create($deployPihole))
        . ([ScriptBlock]::Create($deployUnbound))
        . ([ScriptBlock]::Create($deployCloudflared))

        # pihole
        Deploy-Pihole -data $data
        
        # unbound
        if ($data['unboundEnabled']) {
            Deploy-Unbound -data $data
        } else {
            Write-Host "Unbound is disabled."
        }
        
        # cloudflared
        if ($data['cloudflaredEnabled']) {
            Deploy-Cloudflared -data $data
        } else {
            Write-Host "Cloudflared is disabled."
        }
    } -ArgumentList $data, $deployContainer, $deployPihole, $deployUnbound, $deployCloudflared
    
    # cleanup
    Remove-PSSession -Session $session
}