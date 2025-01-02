param(
    # Path to the configuration file
    [Parameter(Mandatory = $true,
        HelpMessage = "Path to the .psd1 configuration file containing stack deployment settings")]
    [ValidateScript({
            $fullPath = [System.IO.Path]::GetFullPath($_)
        
            # Validate file existence and configuration values
            # With help of Qwen
            if (![System.IO.File]::Exists($fullPath)) {
                throw "The specified file path '$fullPath' does not exist."
            }

            $config = Import-PowerShellDataFile -Path $fullPath

            # Prevent default password usage
            if ($config.piholePassword -eq "admin") {
                throw "The default password 'admin' is not allowed. Please change the password in the configuration file."
            }

            # Validate restart policy
            $validRestartPolicies = @("no", "always", "unless-stopped", "on-failure")
            if ($config.restartPolicy -notin $validRestartPolicies) {
                throw "The 'restartPolicy' in the configuration file is invalid. Accepted values are: $($validRestartPolicies -join ', ')."
            }

            # Validate network configuration
            $validContainerNetwork = @("bridge", "host", "none")
            if ($config.containerNetwork -notin $validContainerNetwork) {
                throw "The 'containerNetwork' in the configuration file is invalid. Accepted values are: $($validContainerNetwork -join ', ')."
            }

            # Validate DNS listening mode
            $validListenValues = @("local", "all", "bind", "single", "")
            if ($config.listen -notin $validListenValues) {
                throw "The 'listen' in the configuration file is invalid. Accepted values are: $($validListenValues -join ', ')."
            }

            # Validate port numbers
            $portParams = @{
                'piholeUiPort'    = $config.piholeUiPort
                'piholeDnsPort'   = $config.piholeDnsPort
                'cloudflaredPort' = $config.cloudflaredPort
                'unboundPort'     = $config.unboundPort
            }
            foreach ($param in $portParams.GetEnumerator()) {
                if ($param.Value -ne "" -and (-not [int]::TryParse($param.Value, [ref]$null) -or [int]$param.Value -lt 1 -or [int]$param.Value -gt 65535)) {
                    throw "The '$($param.Key)' in the configuration file is invalid. Accepted values are between 1 and 65535 or empty."
                }
            }

            # Validate boolean flags
            $boolParams = @('DNSSECEnabled', 'cloudflaredEnabled', 'unboundEnabled')
            foreach ($param in $boolParams) {
                if ($config.$param -notin @($true, $false)) {
                    throw "The '$param' in the configuration file is invalid. Accepted values are: `$true, `$false."
                }
            }

            # Validate adlist format
            if ($config.adlists -isnot [array]) {
                throw "The 'adlists' in the configuration file is invalid. It should be an array of strings."
            }

            # Validate DNS IP addresses
            foreach ($dns in $config.extraDNS) {
                if (-not [System.Net.IPAddress]::TryParse($dns, [ref]$null)) {
                    throw "The 'extraDNS' value '$dns' is not a valid IP address."
                }
            }

            # Validate volume paths, with help of copilot
            foreach ($volume in $config.piholeVolumes) {
                $volume = $volume -replace " ", ""
                if ($volume -notmatch "^/[^/]+(/[^/]+)*$") {
                    throw "The 'piholeVolumes' value '$volume' is not a valid volume path."
                }
            }

            # Validate DHCP settings (with help of copilot)
            if ($config.configureDHCP) {
                if ($config.dhcpServer -isnot [array]) {
                    throw "The 'dhcpServer' in the configuration file is invalid. It should be an array of strings."
                }
                foreach ($server in $config.dhcpServer) {
                    if ($server -isnot [string] -or [string]::IsNullOrWhiteSpace($server)) {
                        throw "Each 'dhcpServer' value in the configuration file should be a non-empty string."
                    }
                }
            }

            return $true
        })]
    [string]$ConfigPath,

    # Path to the Ansible inventory file
    [Parameter(Mandatory = $false,
        HelpMessage = "Path to the Ansible inventory file listing target hosts")]
    [ValidateScript({
            $fullPath = [System.IO.Path]::GetFullPath($_)
            [System.IO.File]::Exists($fullPath) -and [System.IO.Directory]::Exists([System.IO.Path]::GetDirectoryName($fullPath))
        })]
    [string]$InventoryPath = "./inventory.ini",

    # Ansible privilege escalation method
    # For more information, see: https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_privilege_escalation.html
    [Parameter(Mandatory = $false,
        HelpMessage = "Ansible privilege escalation method (e.g., 'ask-become-pass' or 'become-method=sudo')")]
    [string]$become = "ask-become-pass"
)

Import-Module ./main.psm1
[hashtable]$data = Import-PowerShellDataFile -Path $ConfigPath

# Ensure Ansible is available locally
Install-Ansible

# Prepare remote hosts with required dependencies (Docker, PowerShell)
Install-DependenciesRemotely -TempPath ./temp -InventoryPath $InventoryPath -become $become

# Get host information from Ansible
[Array]$servers = Get-Content -Path "./temp/host_info.csv"
Remove-Item -Path ./temp -Recurse -Force

# Prepare function definitions for remote execution
$functions = @(
    "Deploy-Container",
    "Deploy-Pihole",
    "Deploy-Unbound",
    "Deploy-Cloudflared",
    "Set-PiholeConfiguration",
    "Invoke-CommandWithCheck",
    "ConfigDifferent",
    "Get-CurrentContainerConfig",
    "Remove-OldContainers",
    "Get-DnsIp"
)
$functionsDefinitions = Get-FunctionDefinitions -functions $functions

#region Remote deployment
# Deploy stack to all hosts in parallel
$serverDeploymentJobs = @()
foreach ($server in $servers) {
    $serverDeploymentJobs += Start-ThreadJob -ScriptBlock {
        param(
            [Parameter(Mandatory = $true)]
            [string]$server,
            [Parameter(Mandatory = $true)]
            [hashtable]$data,
            [Parameter(Mandatory = $true)]
            [array]$functionsDefinitions,
            [Parameter(Mandatory = $true)]
            [string]$firstServer
        )

        # SSH connection
        [string]$hostname, $username = $server -split ','
        try {
            $session = New-PSSession -HostName $hostname -UserName $username -SSHTransport -ErrorAction Stop
        }
        catch {
            throw "Failed to create SSH session, please check the DHCP server credentials."
        }
    
        # Execute deployment on remote host
        Invoke-Command -Session $session -ScriptBlock {
            param(
                [Parameter(Mandatory = $true)]        
                [hashtable]$data,
                [Parameter(Mandatory = $true)]
                [array]$functionDefinitions,
                [Parameter(Mandatory = $true)]
                [string]$firstServer
            )

            # Initialize functions in remote session
            # https://stackoverflow.com/questions/77900019/piping-to-where-object-and-foreach-object-not-working-in-module-delayed-loaded-i/77903771#77903771
            $functionDefinitions | ForEach-Object {
                . ([ScriptBlock]::Create($_))
            }

            # Prepare function for thread jobs
            # https://stackoverflow.com/questions/75609709/start-threadjob-is-not-detecting-my-variables-i-pass-to-it
            $deployContainerAst = ${function:Deploy-Container}.Ast.Body
            $deployPiholeAst = ${function:Deploy-Pihole}.Ast.Body
            $getContainerConfigAst = ${function:Get-CurrentContainerConfig}.Ast.Body
            $configDifferenceAst = ${function:ConfigDifferent}.Ast.Body
            $deployUnboundAst = ${function:Deploy-Unbound}.Ast.Body
            $deployCloudflaredAst = ${function:Deploy-Cloudflared}.Ast.Body

            # Execute deployment jobs in parallel
            @(
                # Remove disabled containers
                Start-ThreadJob ${function:Remove-OldContainers} -ArgumentList $data

                # Deploy Pi-hole
                Start-ThreadJob -ScriptBlock {
                    param($data, $deployContainerAst, $getContainerConfigAst, $configDifferenceAst, $deployPiholeAst)
                    ${function:Deploy-Container} = $deployContainerAst.GetScriptBlock()
                    ${function:Get-CurrentContainerConfig} = $getContainerConfigAst.GetScriptBlock()
                    ${function:ConfigDifferent} = $configDifferenceAst.GetScriptBlock()
                    & $deployPiholeAst.GetScriptBlock() -data $data
                } -ArgumentList $data, $deployContainerAst, $getContainerConfigAst, $configDifferenceAst, $deployPiholeAst

                # Deploy Unbound (if enabled)
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

                # Deploy Cloudflared (if enabled)
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
            ) | Wait-Job | Receive-Job | Remove-Job

            # Configure Pi-hole
            Set-PiholeConfiguration -data $data

            # If it's the first server we deploy it to, get its DNS IP for dhcp settings
            if ($data['configureDHCP'] -and ($using:server -eq $firstServer)) {
                return Get-DnsIp -data $data
            }

        } -ArgumentList $data, $functionsDefinitions, $firstServer

        Write-Host "Stack deployed on $hostname"

        Remove-PSSession -Session $session
    } -ArgumentList $server, $data, $functionsDefinitions, $servers[0]
}
# endregion

# Write job information to console
$serverDeploymentJobs | ForEach-Object {
    $job = Wait-Job $_
    $job.Information | ForEach-Object { Write-Host $_ }
    # Update DHCP settings to use Pi-hole as DNS server
    if ($data['configureDHCP']) {
        Update-DHCPSettings -data $data -dnsServer $job.Output[0]
    }
    Remove-Job $job
}