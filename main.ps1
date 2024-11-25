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
ansible-playbook -i ./inventory.ini ./master.yml --ask-become-pass

# get host information from ansible
$servers = Get-Content -Path "./temp/host_info.csv"
# cleanup
Remove-Item -Path "./temp" -Recurse -Force

function Get-Data {
    [hashtable]$data = Import-PowerShellDataFile -Path "./main.psd1"
    [hashtable]$defaultValues = @{
        restartPolicy = 'unless-stopped'
        stackName = 'auto_deployed'
    }
    
    # set default values for .psd1 if not provided
    foreach ($key in $defaultValues.Keys) {
        if (-Not $data.ContainsKey($key)) {
            $data.Add($key, $defaultValues[$key])
        }
    }

    return $data
}

# deploy the stack on each host
# deploying could be done trough ansible, but we will use PowerShell to make further changes
foreach ($server in $servers) {
    $hostname = ($server -split ',')[0]
    $username = ($server -split ',')[1]
    Write-Host "Deploying stack on $hostname..."
    $session = New-PSSession -HostName $hostname -UserName $username -SSHTransport

    # get data from .psd1 file
    $data = Get-Data

    Invoke-Command -Session $session -ScriptBlock {
        param($data)
        # pihole
        Write-Host "Deploying pihole..."
        docker run -d --name "$($data['stackName'])_pihole" --restart $data['restartPolicy'] pihole/pihole
        
        # unbound
        Write-Host "Deploying unbound..."
        # use a different image for arm devices (like Raspberry Pi)
        if ((uname -m) -eq "x86_64") {
            $unbound_image = "mvance/unbound"
        } else {
            $unbound_image = "mvance/unbound-rpi"
        }
        docker run -d --name "$($data['stackName'])_unbound" --restart $data['restartPolicy'] $unbound_image
        
        # cloudflared
        Write-Host "Deploying cloudflared..."
        docker run -d --name "$($data['stackName'])_cloudflared" --restart $data['restartPolicy'] cloudflare/cloudflared
    } -ArgumentList $data

    Remove-PSSession -Session $session
}
