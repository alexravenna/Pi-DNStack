#region Helper Functions
<#
.SYNOPSIS
    Executes a command and validates its exit code.
.DESCRIPTION
    Wrapper function that executes external commands and checks their exit codes.
    Powershell does not support -ErrorAction Stop for external commands so we need to check the exit code manually.
.PARAMETER Command
    The command string to execute.
.EXAMPLE
    Invoke-CommandWithCheck "docker ps"
#>
function Invoke-CommandWithCheck {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )
    try {
        # $($_.Exception.Message) does not work properly with external commands so we need to store the whole output to print it on error
        # 2>&1 redirects stderr to stdout see https://www.youtube.com/watch?v=zMKacHGuIHI as "=" only takes the stdout stream
        $output = Invoke-Expression "$Command 2>&1"
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code $LASTEXITCODE : $Command"
        }
        return $output
    }
    catch {
        throw "Error executing command: `"$Command`" Error: `"$output`""
    }
}

<#
.SYNOPSIS
    Gets function definitions for remote execution.
.DESCRIPTION
    Prepares function definitions to be sent to remote hosts for execution.
    Required for PowerShell remoting when functions need to be recreated on target hosts (aka import the local module to the remote session).
    Based on https://stackoverflow.com/questions/11367367/how-do-i-include-a-locally-defined-function-when-using-powershells-invoke-comma#:~:text=%24fooDef%20%3D%20%22function%20foo%20%7B%20%24%7Bfunction%3Afoo%7D%20%7D%22%0A%0AInvoke%2DCommand%20%2DArgumentList%20%24fooDef%20%2DComputerName%20someserver.example.com%20%2DScriptBlock%20%7B%0A%20%20%20%20Param(%20%24fooDef%20)%0A%0A%20%20%20%20.%20(%5BScriptBlock%5D%3A%3ACreate(%24fooDef))%0A%0A%20%20%20%20Write%2DHost%20%22You%20can%20call%20the%20function%20as%20often%20as%20you%20like%3A%22%0A%20%20%20%20foo%20%22Bye%22%0A%20%20%20%20foo%20%22Adieu!%22%0A%7D
.PARAMETER functions
    Array of function names to prepare for remote execution.
.EXAMPLE
    Get-FunctionDefinitions -functions @("Deploy-Container", "Deploy-Pihole")
#>
function Get-FunctionDefinitions {
    param(
        [Parameter(Mandatory = $true)]
        [array]$functions)
    [array]$functionsDefinitions = @()
    foreach ($function in $functions) {
        $functionsDefinitions += "function $function { `n" + 
            (Get-Command $function).ScriptBlock.ToString() +
        "`n}"
    }

    return $functionsDefinitions
}
#endregion

#region Configuration Management
<#
.SYNOPSIS
    Checks if container configuration differs from desired state.
.DESCRIPTION
    Compares current container configuration with desired configuration parameters.
    Used for declarative container management.
.PARAMETER CurrentConfig
    Hashtable containing current container configuration.
.PARAMETER image, restartPolicy, containerNetwork, ports, volumes, envs
    Desired configuration parameters to compare against.
.EXAMPLE
    ConfigDifferent -CurrentConfig $config -image "nginx:latest" -restartPolicy "always"
#>
function ConfigDifferent {
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$CurrentConfig,
        [Parameter(Mandatory = $true)]
        [string]$image,
        [Parameter(Mandatory = $true)]
        [string]$restartPolicy,
        [Parameter(Mandatory = $true)]
        [string]$containerNetwork,
        [Parameter(Mandatory = $false)]
        [array]$ports = @(),
        [Parameter(Mandatory = $false)]
        [array]$volumes = @(),
        [Parameter(Mandatory = $false)]
        [array]$envs = @()
    )

    if ($CurrentConfig.Image -ne $image) {
        return $true
    }

    if ($CurrentConfig.RestartPolicy -ne $restartPolicy) {
        return $true
    }

    if ($CurrentConfig.ContainerNetwork -ne $containerNetwork) {
        return $true
    }

    # check if all ports we want are mapped
    foreach ($port in $ports) {
        if (-Not ($CurrentConfig.Ports -Match $port)) {
            if ($port -match '^\d+:') {
                return $true
            }
        }
    }
    # check if no extra ports are mapped
    foreach ($port in ($CurrentConfig.Ports -split ' ')) {
        if (-Not ($ports -Match $port)) {
            return $true
        }
    }

    # check if all volumes we want are mounted
    foreach ($volume in $volumes) {
        if (-Not ($CurrentConfig.Volumes -Match $volume)) {
            return $true
        }
    }
    # check if no extra volumes are mounted
    foreach ($volume in ($CurrentConfig.Volumes -split ' ')) {
        if (-Not ($volumes -Match $volume)) {
            return $true
        }
    }

    # check if all env variables we want are set
    foreach ($env in $envs) {
        if (-Not ($CurrentConfig.EnvironmentVariables -Match $env)) {
            return $true
        }
    }
    # we don't need to check visa versa as as there is only the pihole password as env variable

    return $false
}

<#
.SYNOPSIS
    Retrieves current container configuration.
.DESCRIPTION
    Gets configuration details of an existing container using Docker inspect commands.
.PARAMETER ContainerName
    Name of the container to inspect.
.EXAMPLE
    Get-CurrentContainerConfig -ContainerName "pihole"
#>
function Get-CurrentContainerConfig {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ContainerName
    )

    if ($null -eq (docker ps --filter "name=$name" --format "{{.Names}}")) {
        return $null
    }

    [string]$image = docker inspect --format='{{.Config.Image}}' $ContainerName
    # with help of https://chatgpt.com/share/6766e1f1-a8a0-8011-b306-59da137b7359
    [string]$ports = docker inspect --format '{{range $p, $conf := .NetworkSettings.Ports}}{{if $conf}}{{(index $conf 0).HostPort}}:{{(index $conf 0).HostPort}} {{end}}{{end}}' $ContainerName
    [string]$volumes = docker inspect --format '{{range .Mounts}}{{if .Source}}{{.Source}}:{{.Destination}} {{end}}{{end}}' $ContainerName
    [string]$environmentVariables = docker inspect --format='{{range .Config.Env}}{{.}}{{end}}' $ContainerName
    [string]$restartPolicy = docker inspect --format='{{.HostConfig.RestartPolicy.Name}}' $ContainerName
    [string]$containerNetwork = docker inspect --format '{{.HostConfig.NetworkMode}}' $ContainerName

    [hashtable]$currentConfig = @{
        Image                = $image
        Ports                = $ports
        Volumes              = $volumes
        EnvironmentVariables = $environmentVariables
        RestartPolicy        = $restartPolicy
        ContainerNetwork     = $containerNetwork
    }

    return $currentConfig
}
#endregion

#region Deployment Functions
<#
.SYNOPSIS
    Generic container deployment function.
.DESCRIPTION
    Handles container deployment with support for various configuration options.
    Implements declarative deployment pattern.
.PARAMETER name, image, network, restartPolicy, ports, volumes, flags, extra
    Container configuration parameters.
.EXAMPLE
    Deploy-Container -name "pihole" -image "pihole/pihole:latest" -network "bridge"
#>
function Deploy-Container {
    param(
        [Parameter(Mandatory = $true)]
        [string]$name,
        [Parameter(Mandatory = $true)]
        [string]$image,
        [Parameter(Mandatory = $false)]
        [string]$network,
        [Parameter(Mandatory = $false)]
        [string]$restartPolicy,
        [Parameter(Mandatory = $false)]
        [array]$ports,
        [Parameter(Mandatory = $false)]
        [array]$volumes,
        [Parameter(Mandatory = $false)]
        [string]$flags = "",
        [Parameter(Mandatory = $false)]
        [string]$extra = ""
    )
    
    # declarative checks
    $currentConfig = Get-CurrentContainerConfig -ContainerName $name
    $envs = @()
    if ($name -match "pihole") {
        $envs += "WEBPASSWORD=$($data['piholePassword'])"
    }
    # check if the container runs
    if ($null -eq $currentConfig) {
        Write-Host "Deploying $name..." 
    }
    # checks if there are configuration differences between the current and desired state
    elseif (ConfigDifferent -CurrentConfig $currentConfig -image $image -ports $ports -volumes $volumes -envs $envs -restartPolicy $restartPolicy -containerNetwork $network) {
        Write-Host "Container $name exists but configuration differs. Replacing container..."
        docker rm -f $name
    }
    else {
        Write-Host "Container $name is already deployed with the correct configuration."
        return
    }

    [string]$command = "docker run -d --name $name"
    if ($restartPolicy) { 
        $command += " --restart $restartPolicy" 
    }
    if ($network) { 
        $command += " --network $network" 
    }

    foreach ($port in $ports) {
        # with help of https://chatgpt.com/share/67669ebb-9d50-8011-a317-88c6aa993d1d
        # if there is an outwards port map it
        if ($port -match '^\d+:') {
            $command += " -p $port"
        }
    }

    foreach ($volume in $volumes) {
        $command += " -v $volume"
    }

    $command += " $flags $image $extra >/dev/null"

    Invoke-Expression $command
}

<#
.SYNOPSIS
    Deploys Pi-hole container.
.DESCRIPTION
    Specialized deployment function for Pi-hole.
.PARAMETER data
    Configuration hashtable containing Pi-hole specific settings.
.EXAMPLE
    Deploy-Pihole -data $config
#>
function Deploy-Pihole {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$data)

    [string]$password = $data['piholePassword']

    Deploy-Container -name "$($data['stackName'])_pihole" `
        -image "pihole/pihole" `
        -network $data['containerNetwork'] `
        -restartPolicy $data['restartPolicy'] `
        -ports @(
        "$($data['piholeUiPort']):80",
        "$($data['piholeDnsPort']):53"
    ) `
        -volumes $data['piholeVolumes'] `
        -flags "$($data['piholeFlags']) -e WEBPASSWORD=$password"
}

<#
.SYNOPSIS
    Deploys Unbound DNS resolver.
.DESCRIPTION
    Specialized deployment function for Unbound .
.PARAMETER data
    Configuration hashtable containing Unbound specific settings.
.EXAMPLE
    Deploy-Unbound -data $config
#>
function Deploy-Unbound {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$data)
    # Choose the correct image based on cpu architecture
    [string]$image = if ((uname -m) -eq "x86_64") { $data['unboundImage'] } else { $data['unboundArmImage'] }

    Deploy-Container -name "$($data['stackName'])_unbound" `
        -image $image `
        -network $data['containerNetwork'] `
        -restartPolicy $data['restartPolicy'] `
        -ports @("$($data['unboundPort']):53") `
        -volumes $data['unboundVolumes'] `
        -flags $data['unboundFlags']
}  

<#
.SYNOPSIS
    Deploys Cloudflared DNS-over-HTTPS proxy.
.DESCRIPTION
    Specialized deployment function for Cloudflared.
.PARAMETER data
    Configuration hashtable containing Cloudflared specific settings.
.EXAMPLE
    Deploy-Cloudflared -data $config
#>
function Deploy-Cloudflared {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$data)

    $extra = "proxy-dns --port 5053 --address 0.0.0.0"
    if (-not $data['cloudflaredUpstream'] -eq "") {
        $extra += " --upstream $data['cloudflaredUpstream']"
    }
    
    Deploy-Container -name "$($data['stackName'])_cloudflared" `
        -image "cloudflare/cloudflared" `
        -network $data['containerNetwork'] `
        -restartPolicy $data['restartPolicy'] `
        -ports @("$($data['cloudflaredPort']):5053") `
        -volumes $data['cloudflaredVolumes'] `
        -flags $data['cloudflaredFlags'] `
        -extra $extra
}

<#
.SYNOPSIS
    Removes disabled containers.
.DESCRIPTION
    Removes Unbound and Cloudflared containers if they are disabled in configuration.
.PARAMETER data
    Configuration hashtable containing service enable/disable flags.
.EXAMPLE
    Remove-OldContainers -data $config
#>
function Remove-OldContainers {
    param(
        [Parameter(Mandatory = $false)]
        [hashtable]$data
    )

    if (-Not $data['unboundEnabled']) {
        Write-Host "Removing old unbound container..."
        # remove the container silently
        docker rm -f "$($data['stackName'])_unbound" 2>&1 >/dev/null
    }

    if (-Not $data['cloudflaredEnabled']) {
        Write-Host "Removing old cloudflared container..."
        docker rm -f "$($data['stackName'])_cloudflared" 2>&1 >/dev/null
    }
}
#endregion

#region Configuration Functions
<#
.SYNOPSIS
    Configures Pi-hole settings.
.DESCRIPTION
    Applies Pi-hole configuration including DNS servers, DNSSEC, adlists, and interface settings.
.PARAMETER data
    Configuration hashtable containing Pi-hole settings.
.EXAMPLE
    Set-PiholeConfiguration -data $config
#>
function Set-PiholeConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$data)

    Write-Host "Configuring Pi-hole..."

    function Get-DockerNetwork {
        param([hashtable]$data,
            [string]$container,
            [string]$port)
        
        # https://stackoverflow.com/questions/17157721/how-to-get-a-docker-containers-ip-address-from-the-host
        [string]$IP = Invoke-CommandWithCheck "docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ""$($data['stackName'])_$container"""
        # inner port so no need to take it from the .psd1 file
        [string]$Network = "$IP#$port"
        return $Network
    }

    # region upsteam DNS
    function Set-DnsConfiguration {
        param(
            [Parameter(Mandatory = $true)]
            [hashtable]$data,
            [Parameter(Mandatory = $true)]
            [string]$nr,
            [Parameter(Mandatory = $true)]
            [string]$dnsNetwork
        )

        # update pihole's upstream DNS servers
        # add line if it doesn't exist else update it
        # with help of https://chatgpt.com/share/67604d61-1d44-8011-99dd-83e8538cd7af
        $command = @"
    if grep -q '^PIHOLE_DNS_$nr=' /etc/pihole/setupVars.conf; then
        sed -i '/^PIHOLE_DNS_$nr=/c\PIHOLE_DNS_$nr=$dnsNetwork' /etc/pihole/setupVars.conf
    else
        echo 'PIHOLE_DNS_$nr=$dnsNetwork' >> /etc/pihole/setupVars.conf
    fi
"@
        docker exec "$($data['stackName'])_pihole" /bin/bash -c $command
    }

    # get ips of upstream DNS servers as pihole needs ip addresses and not docker hostnames
    try {
        if ($data['unboundEnabled']) {
            [string]$unboundNetwork = Get-DockerNetwork -data $data -container "unbound" -port "53"
        }
        if ($data['cloudflaredEnabled']) {
            [string]$cloudflaredNetwork = Get-DockerNetwork -data $data -container "cloudflared" -port "5053"
        }
    }
    catch {
        throw "Error getting IP addresses: $_"
    }

    [int]$nr = 1

    try {
        foreach ($dns in $data['extraDNS']) {
            Set-DnsConfiguration -data $data -nr $nr -dnsNetwork $dns
            $nr++
        }
        if ($data['unboundEnabled']) {
            Set-DnsConfiguration -data $data -nr $nr -dnsNetwork $unboundNetwork
            $nr++
        }
        if ($data['cloudflaredEnabled']) {
            Set-DnsConfiguration -data $data -nr $nr -dnsNetwork $cloudflaredNetwork
            $nr++
        }
    }
    catch {
        throw "Get-Error updating Pi-hole configuration: $_"
    }
    
    # remove all dns with a nr higher than $nr aka outdated upstream DNS servers
    # with help of https://chatgpt.com/share/676050bc-c4bc-8011-aeec-5efcce256287
    do {
        [string]$command = "sed -i '/^PIHOLE_DNS_$nr=/d' /etc/pihole/setupVars.conf"
        [string]$output = docker exec "$($data['stackName'])_pihole" /bin/bash -c "grep '^PIHOLE_DNS_$nr=' /etc/pihole/setupVars.conf"

        if ($output) {
            docker exec "$($data['stackName'])_pihole" /bin/bash -c $command
            $nr++
        }
    } while ($output)
    # endregion

    #region dnssec
    $dnssecValue = if ($data['DNSSECEnabled']) { 'true' } else { 'false' }

    # w help of https://chatgpt.com/share/676ad29c-8da4-8011-bb80-e9c2b8ed9019
    $command = @"
if grep -q '^DNSSEC=' /etc/pihole/setupVars.conf; then
    sed -i 's/^DNSSEC=.*/DNSSEC=$dnssecValue/' /etc/pihole/setupVars.conf
else
    echo 'DNSSEC=$dnssecValue' >> /etc/pihole/setupVars.conf
fi
"@
    docker exec "$($data['stackName'])_pihole" /bin/bash -c $command
    #endregion

    #region adlist
    # update gravity in case the db is not yet created
    docker exec "$($data['stackName'])_pihole" pihole updateGravity 2>&1 >/dev/null
    # remove deprecated adlists
    $existingAdlists = docker exec "$($data['stackName'])_pihole" sqlite3 /etc/pihole/gravity.db "SELECT address FROM adlist;"
    $existingAdlists = $existingAdlists -split "`n"

    foreach ($adlist in $existingAdlists) {
        if ($adlist -notin $data['adlists']) {
            docker exec "$($data['stackName'])_pihole" sqlite3 /etc/pihole/gravity.db "DELETE FROM adlist WHERE address='$adlist';"
        }
    }
    # add new ones
    foreach ($adlist in $data['adlists']) {
        $command = @"
INSERT OR IGNORE INTO adlist (address, enabled, date_added, date_modified, comment, date_updated, number, invalid_domains, status)
VALUES ('$adlist', 1, cast(strftime('%s', 'now') as int), cast(strftime('%s', 'now') as int), 'Added via Pi-DNStack', NULL, 0, 0, 0);
"@
        docker exec "$($data['stackName'])_pihole" sqlite3 /etc/pihole/gravity.db "$command"

    }
    docker exec "$($data['stackName'])_pihole" pihole updateGravity 2>&1 >/dev/null
    #endregion

    #region set pihole interface
    # w help of https://chatgpt.com/share/676c02af-26f4-8011-8766-8374c08aeb23
    $command = $command = @"
if [[ -n "$($data['interface'])" ]]; then
    if grep -q "^PIHOLE_INTERFACE=" /etc/pihole/setupVars.conf; then
        sed -i "s/^PIHOLE_INTERFACE=.*/PIHOLE_INTERFACE=$($data['interface'])/" /etc/pihole/setupVars.conf
    else
        echo "PIHOLE_INTERFACE=$($data['interface'])" >> /etc/pihole/setupVars.conf
    fi
fi

if [[ -n "$($data['listen'])" ]]; then
    if grep -q "^DNSMASQ_LISTENING=" /etc/pihole/setupVars.conf; then
        sed -i "s/^DNSMASQ_LISTENING=.*/DNSMASQ_LISTENING=$($data['listen'])/" /etc/pihole/setupVars.conf
    else
        echo "DNSMASQ_LISTENING=$($data['listen'])" >> /etc/pihole/setupVars.conf
    fi
fi
"@

    docker exec "$($data['stackName'])_pihole" /bin/bash -c $command
    #endregion
}

<#
.SYNOPSIS
    Installs Ansible if not present.
.DESCRIPTION
    Detects operating system and installs Ansible using appropriate package manager.
    Supports apt, dnf, and pacman package managers.
.EXAMPLE
    Install-Ansible
#>
function Install-Ansible {
    # https://docs.ansible.com/ansible/latest/installation_guide/installation_distros.html
    if (-Not (Get-Command ansible -ErrorAction SilentlyContinue)) {
        Write-Host "Ansible is not installed. Installing Ansible..."
        if (Get-Command dnf -ErrorAction SilentlyContinue) {
            Write-Host "Installing Ansible on RHEL-based system..."
            Invoke-CommandWithCheck "sudo dnf install -y ansible"
        }
        elseif (Get-Command apt -ErrorAction SilentlyContinue) {
            Write-Host "Installing Ansible on Debian-based system..."
            try {
                Invoke-CommandWithCheck "sudo apt update"
                Invoke-CommandWithCheck "sudo apt install -y software-properties-common"
                Invoke-CommandWithCheck "sudo add-apt-repository --yes --update ppa:ansible/ansible"
                Invoke-CommandWithCheck "sudo apt install -y ansible"
            }
            catch {
                throw "Error installing Ansible with apt."
            }
        }
        elseif (Get-Command pacman -ErrorAction SilentlyContinue) {
            Write-Host "Installing Ansible on Arch-based system..."
            try {
                Invoke-CommandWithCheck "sudo pacman -Sy ansible"
            }
            catch {
                throw "Error installing Ansible with pacman."
            }
        }
        elseif ($IsWindows) {
            throw "Windows not supported. Please use WSL."
        }
        else {
            throw "Unsupported Linux distribution. Please install Ansible manually."
        }

        # verify installation
        if (-Not (Get-Command ansible -ErrorAction SilentlyContinue)) {
            throw "Ansible installation failed. Please install Ansible manually."
        }
        else {
            Write-Host "Ansible installed successfully." -ForegroundColor Green
        }
    }
    else {
        Write-Host "Ansible is already installed." -ForegroundColor Green
    }
}

<#
.SYNOPSIS
    Installs dependencies on remote hosts.
.DESCRIPTION
    Uses Ansible to install required dependencies (Docker, PowerShell) on remote hosts.
.PARAMETER TempPath
    Path for temporary files.
.PARAMETER InventoryPath
    Path to Ansible inventory file.
.PARAMETER become
    Ansible privilege escalation method.
.EXAMPLE
    Install-DependenciesRemotely -TempPath "./temp" -InventoryPath "./inventory.ini" -become "ask-become-pass"
#>
function Install-DependenciesRemotely { 
    param(
        [Parameter(Mandatory = $true)]
        [string]$TempPath,
        [Parameter(Mandatory = $true)]
        [string]$InventoryPath,
        [Parameter(Mandatory = $true)]
        [string]$become
    )

    # temp folder to store hosts information for pwsh remoting
    New-Item -Path $TempPath -ItemType Directory -Force
    # Install Powershell & Docker on the remote host and get hosts information
    Write-Host "Install dependencies on the remote host..."
    [string]$command = "ansible-playbook -i $InventoryPath ./ansible/master.yml --$become"
    try {
        Invoke-CommandWithCheck $command
    }
    catch {
        if ($_.Exception.Message -match "Incorrect sudo password") {
            throw "Error: Incorrect sudo password"
        }
        else {
            throw $($_.Exception.Message)
        }
    }
}
#endregion

# Export all functions
Export-ModuleMember -Function *