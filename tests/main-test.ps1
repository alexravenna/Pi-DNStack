# This test script is ment to be launched from the root directory trough CI/CD

param(
    [Parameter(Mandatory = $true, HelpMessage = "Sudo password for Ansible privilege escalation")]
    [string]$password,
    [Parameter(HelpMessage = "Directory containing test configuration files")]
    [string]$configDir = "./tests/configs",
    [Parameter(HelpMessage = "Path to the main script to be tested")]
    [string]$scriptPath = "./main.ps1",
    [Parameter(HelpMessage = "Path to the Ansible inventory file")]
    [string]$InventoryPath = "./tests/inventory.ini",
    [Parameter(HelpMessage = "Ansible privilege escalation method using GitHub secrets")]
    [string]$become = "extra-vars 'ansible_become_password=$password'"
)

# Removes all containers with the stack name
function CleanUpContainers {
    param(
        $session,
        [string]$path
    )

    $config = Import-PowerShellDataFile -Path $path
    [string]$stackName = if ($config.stackName) { $config.stackName } else { 'Pi-DNStack' }

    Invoke-Command -Session $session -ScriptBlock {
        param([string]$stackName)
        [string]$command = "docker ps -a --filter name=$stackName -q"
        [string[]]$containers = Invoke-Expression $command

        if ($containers) {
            $containers | ForEach-Object {
                docker rm -f $_
            }
        }
    } -ArgumentList $stackName
}

# Get host and username from inventory file
[string[]]$servers = Get-Content $InventoryPath
[string]$server = $servers[-1]
[string]$hostname, [string]$username = $server -split ' '
$username = $username -replace "ansible_user=", ""

$session = New-PSSession -HostName $hostname -UserName $username -SSHTransport


#region Pester tests
Describe "Docker Container Tests" {
    Context "Default Configuration" {
        BeforeAll {
            # run the main script
            pwsh -File $scriptPath -ConfigPath "$configDir/default.psd1" -InventoryPath $InventoryPath -become $become
        }

        It "Should ensure the pihole container is running correctly" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker ps --filter "name=Pi-DNStack_pihole" --format "{{.Names}}"
            }
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should ensure the pihole container is bound to port 80 and 53" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect Pi-DNStack_pihole --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}'
            }
            $result | Should -Match "80"
            $result | Should -Match "53"
        }

        It "Should ensure the pihole container has the correct mount for /etc/pihole" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect Pi-DNStack_pihole --format '{{range .Mounts}}{{.Source}}{{end}}'
            }
            $result | Should -Match "/etc/pihole"
        }

        It "Should ensure the restart policy is set to 'unless-stopped'" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect Pi-DNStack_pihole --format '{{.HostConfig.RestartPolicy.Name}}'
            }
            $result | Should -Match "unless-stopped"
        }

        It "Should ensure the container network is set to 'bridge'" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect Pi-DNStack_pihole --format '{{.HostConfig.NetworkMode}}'
            }
            $result | Should -Match "bridge"
        }

        It "Should ensure the unbound container is running correctly" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker ps --filter "name=Pi-DNStack_pihole" --format "{{.Names}}"
            }
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should ensure the cloudflared container is running correctly" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker ps --filter "name=Pi-DNStack_cloudflared" --format "{{.Names}}"
            }
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should ensure the pihole container is resolving correctly" {
            [string]$server = Invoke-Command -Session $session -ScriptBlock { 
                docker inspect Pi-DNStack_pihole --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
            }
            [string]$result = Invoke-Command -Session $session -ScriptBlock { 
                nslookup google.com $server
            } -ArgumentList $server
            $result | Should -Match "Non-authoritative answer"
        }

        It "Should ensure DNSSEC is enabled" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker exec Pi-DNStack_pihole cat /etc/pihole/setupVars.conf
            }
            $result | Should -Match "DNSSEC=true"
        }

        It "Should ensure the adlists are set correctly" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker exec Pi-DNStack_pihole pihole-FTL sqlite3 /etc/pihole/gravity.db "SELECT * FROM adlist"
            }
            $result | Should -Match "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
        }

        It "Should ensure interface is set to eth0" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker exec Pi-DNStack_pihole cat /etc/pihole/setupVars.conf
            }
            $result | Should -Match "PIHOLE_INTERFACE=eth0"
        }

        It "Should ensure pihole listens on local" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker exec Pi-DNStack_pihole cat /etc/pihole/setupVars.conf
            }
            $result | Should -Match "DNSMASQ_LISTENING=local"
        }
    }

    Context "Unbound Disabled" {
        BeforeAll {
            # run the main script
            pwsh -File $scriptPath -ConfigPath "$configDir/unbound_disabled.psd1" -InventoryPath $InventoryPath -become $become
        }

        It "Should ensure the unbound container is not running" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker ps --filter "name=Pi-DNStack_unbound" --format "{{.Names}}" | wc -l
            }
            $result | Should -Be "0"
        }

        It "Should ensure the cloudflared container is still running correctly" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker ps --filter "name=Pi-DNStack_cloudflared" --format "{{.Names}}"
            }
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should ensure the pihole container is still running correctly" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker ps --filter "name=Pi-DNStack_pihole" --format "{{.Names}}"
            }
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should ensure the pihole container is resolving correctly" {
            [string]$server = Invoke-Command -Session $session -ScriptBlock { 
                docker inspect Pi-DNStack_pihole --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
            }
            [string]$result = Invoke-Command -Session $session -ScriptBlock { 
                nslookup google.com $server
            } -ArgumentList $server
            $result | Should -Match "Non-authoritative answer"
        }
    }

    Context "Cloudflared Disabled" {
        BeforeAll {
            # run the main script
            pwsh -File $scriptPath -ConfigPath "$configDir/cloudflared_disabled.psd1" -InventoryPath $InventoryPath -become $become
        }
        It "Should ensure the cloudflared container is not running" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker ps --filter "name=Pi-DNStack_cloudflared" --format "{{.Names}}" | wc -l
            }
            $result | Should -Be "0"
        }

        It "Should ensure the unbound container is still running correctly" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker ps --filter "name=Pi-DNStack_unbound" --format "{{.Names}}"
            }
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should ensure the pihole container is still running correctly" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker ps --filter "name=Pi-DNStack_pihole" --format "{{.Names}}"
            }
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should ensure the pihole container is resolving correctly" {
            [string]$server = Invoke-Command -Session $session -ScriptBlock { 
                docker inspect Pi-DNStack_pihole --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
            }
            [string]$result = Invoke-Command -Session $session -ScriptBlock { 
                nslookup google.com $server
            } -ArgumentList $server
            $result | Should -Match "Non-authoritative answer"
        }
    }

    Context "StackName Changed" {
        BeforeAll {
            # as we change stackname we need to clear old containers to avoid port conflicts
            CleanUpContainers -session $session "$configDir/cloudflared_disabled.psd1"
            # run the main script
            pwsh -File $scriptPath -ConfigPath "$configDir/stackName_changed.psd1" -InventoryPath $InventoryPath -become $become
        }
        It "Should ensure the stack name is set to 'custom_stack'" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker ps | grep "custom_stack"
            }
            $result | Should -Not -BeNullOrEmpty
        }

        # remove the containers after the context
        AfterAll {
            CleanUpContainers -session $session "$configDir/stackName_changed.psd1"
        }
    }

    Context "Multiple Changes" {
        BeforeAll {
            # run the main script
            pwsh -File $scriptPath -ConfigPath "$configDir/changes.psd1" -InventoryPath $InventoryPath -become $become
        }
        It "Should ensure the restart policy is set to 'always'" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect Pi-DNStack_pihole --format '{{.HostConfig.RestartPolicy.Name}}'
            }
            $result | Should -Match "always"
        }

        It "Should ensure the Pi-hole container is bound to port 8081 and 5356" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect Pi-DNStack_pihole --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}'
            }
            $result | Should -Match "8081"
            $result | Should -Match "5356"
        }

        It "Should ensure the unbound container is bound to port 5353" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect Pi-DNStack_unbound --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}'
            }
            $result | Should -Match "5353"
        }

        It "Should ensure the cloudflared container is bound to port 5054" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect Pi-DNStack_cloudflared --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}'
            }
            $result | Should -Match "5054"
        }

        It "Should ensure the Pi-hole password is changed" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect Pi-DNStack_pihole --format '{{range .Config.Env}}{{println .}}{{end}}'
            }
            $result | Should -Match "WEBPASSWORD=secret"
        }

        It "Should ensure volume path is changed" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect Pi-DNStack_pihole --format '{{range .Mounts}}{{.Source}}{{end}}'
            }
            $result | Should -Match "/etc/test/pihole"
            $result | Should -Match "/etc/test/dnsmasq.d"
        }

        It "Should ensure DNSSEC is disabled" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker exec Pi-DNStack_pihole cat /etc/pihole/setupVars.conf
            }
            $result | Should -Match "DNSSEC=false"
        }

        It "Should ensure the adlists are set correctly" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker exec Pi-DNStack_pihole pihole-FTL sqlite3 /etc/pihole/gravity.db "SELECT * FROM adlist"
            }
            $result | Should -Match "https://test.com"
            $result | Should -Not -Match "https://v.firebog.net/hosts/static/w3kbl.txt"
        }

        It "Should ensure interface is set to eth1" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker exec Pi-DNStack_pihole cat /etc/pihole/setupVars.conf
            }
            $result | Should -Match "PIHOLE_INTERFACE=eth1"
        }

        It "Should ensure pihole listens on all" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker exec Pi-DNStack_pihole cat /etc/pihole/setupVars.conf
            }
            $result | Should -Match "DNSMASQ_LISTENING=all"
        }
    }

    Context "Host Network" {
        BeforeAll {
            # run the main script
            pwsh -File $scriptPath -ConfigPath "$configDir/host_network.psd1" -InventoryPath $InventoryPath -become $become
        }

        It "Should ensure the container network is set to 'host'" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect Pi-DNStack_pihole --format '{{.HostConfig.NetworkMode}}'
            }
            $result | Should -Match "host"
        }

        It "Should ensure the pihole container has no ports bound" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect Pi-DNStack_pihole --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}'
            }
            $result | Should -BeNullOrEmpty
        }

        It "Should ensure the cloudflared container has no ports bound" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect Pi-DNStack_cloudflared --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}'
            }
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Password not changed" {
        It "Should throw an error if the password is not changed" {
            pwsh -File $scriptPath -ConfigPath "$configDir/password_not_changed.psd1" -InventoryPath $InventoryPath -become $become 2>&1
            $LastExitCode | Should -Not -Be 0
        }

        # remove the containers after the last context
        AfterAll {
            CleanUpContainers -session $session "$configDir/password_not_changed.psd1"
        }
    }
}
#endregion

# cleanup
Remove-PSSession $session
