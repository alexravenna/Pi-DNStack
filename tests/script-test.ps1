# this test script is ment to be launched from the root directory trough CI/CD

param(
    [string]$password,
    [string]$configDir = "./tests/configs",
    [string]$scriptPath = "./main.ps1",
    [string]$InventoryPath = "./tests/inventory.ini",
    # become sudo for ansible through GitHub secrets
    [string]$become = "extra-vars 'ansible_become_password=$password'"
)

# removes all containers with the stack name
function CleanUpContainers {
    param(
        $session,
        $path
    )

    $config = Import-PowerShellDataFile -Path $path
    $stackName = if ($config.stackName) { $config.stackName } else { 'auto_deployed' }

    Invoke-Command -Session $session -ScriptBlock {
        param($stackName)
        $command = "docker ps -a --filter name=$stackName -q"
        $containers = Invoke-Expression $command

        if ($containers) {
            $containers | ForEach-Object {
                docker rm -f $_
            }
        }
    } -ArgumentList $stackName
}

# get host and username from inventory file
$servers = Get-Content $InventoryPath
$server = $servers[-1]
[string]$hostname, $username = $server -split ' '
$username = $username -replace "ansible_user=", ""

$session = New-PSSession -HostName $hostname -UserName $username -SSHTransport

# remove left containers from previous runs
CleanUpContainers -session $session "$configDir/default.psd1"
CleanUpContainers -session $session "$configDir/stackName_changed.psd1"

# pester tests
Describe "Docker Container Tests" {
    Context "Default Configuration" {
        BeforeAll {
            # run the main script
            pwsh -File $scriptPath -ConfigPath "$configDir/default.psd1" -InventoryPath $InventoryPath -become $become
        }

        It "Should ensure the pihole container is running correctly" {
            $result = Invoke-Command -Session $session -ScriptBlock {
                docker ps --filter "name=auto_deployed_pihole" --format "{{.Names}}"
            }
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should ensure the pihole container is bound to port 80" {
            $result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect auto_deployed_pihole --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}'
            }
            $result | Should -Match "80"
        }

        It "Should ensure the pihole container has the correct mount for /etc/pihole" {
            $result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect auto_deployed_pihole --format '{{range .Mounts}}{{.Source}}{{end}}'
            }
            $result | Should -Match "/etc/pihole"
        }

        It "Should ensure the restart policy is set to 'unless-stopped'" {
            $result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect auto_deployed_pihole --format '{{.HostConfig.RestartPolicy.Name}}'
            }
            $result | Should -Match "unless-stopped"
        }

        It "Should ensure the container network is set to 'bridge'" {
            $result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect auto_deployed_pihole --format '{{.HostConfig.NetworkMode}}'
            }
            $result | Should -Match "bridge"
        }

        It "Should ensure the unbound container is running correctly" {
            $result = Invoke-Command -Session $session -ScriptBlock {
                docker ps --filter "name=auto_deployed_unbound" --format "{{.Names}}"
            }
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should ensure the cloudflared container is running correctly" {
            $result = Invoke-Command -Session $session -ScriptBlock {
                docker ps --filter "name=auto_deployed_cloudflared" --format "{{.Names}}"
            }
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should ensure the cloudflared container is bound to port 5053" {
            $result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect auto_deployed_cloudflared --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}'
            }
            $result | Should -Match "5053"
        }

        # remove the containers after the context
        AfterAll {
            CleanUpContainers -session $session "$configDir/default.psd1"
        }
    }

    Context "Unbound Disabled" {
        BeforeAll {
            # run the main script
            pwsh -File $scriptPath -ConfigPath "$configDir/unbound_disabled.psd1" -InventoryPath $InventoryPath -become $become
        }

        It "Should ensure the unbound container is not running" {
            $result = Invoke-Command -Session $session -ScriptBlock {
                docker ps --filter "name=auto_deployed_unbound" --format "{{.Names}}" | wc -l
            }
            $result | Should -Be "0"
        }

        It "Should ensure the cloudflared container is still running correctly" {
            $result = Invoke-Command -Session $session -ScriptBlock {
                docker ps --filter "name=auto_deployed_cloudflared" --format "{{.Names}}"
            }
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should ensure the pihole container is still running correctly" {
            $result = Invoke-Command -Session $session -ScriptBlock {
                docker ps --filter "name=auto_deployed_pihole" --format "{{.Names}}"
            }
            $result | Should -Not -BeNullOrEmpty
        }

        # remove the containers after the context
        AfterAll {
            CleanUpContainers -session $session "$configDir/unbound_disabled.psd1"
        }
    }

    Context "Cloudflared Disabled" {
        BeforeAll {
            # run the main script
            pwsh -File $scriptPath -ConfigPath "$configDir/cloudflared_disabled.psd1" -InventoryPath $InventoryPath -become $become
        }
        It "Should ensure the cloudflared container is not running" {
            $result = Invoke-Command -Session $session -ScriptBlock {
                docker ps --filter "name=auto_deployed_cloudflared" --format "{{.Names}}" | wc -l
            }
            $result | Should -Be "0"
        }

        It "Should ensure the unbound container is still running correctly" {
            $result = Invoke-Command -Session $session -ScriptBlock {
                docker ps --filter "name=auto_deployed_unbound" --format "{{.Names}}"
            }
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should ensure the pihole container is still running correctly" {
            $result = Invoke-Command -Session $session -ScriptBlock {
                docker ps --filter "name=auto_deployed_pihole" --format "{{.Names}}"
            }
            $result | Should -Not -BeNullOrEmpty
        }

        # remove the containers after the context
        AfterAll {
            CleanUpContainers -session $session "$configDir/cloudflared_disabled.psd1"
        }
    }

    Context "StackName Changed" {
        BeforeAll {
            # run the main script
            pwsh -File $scriptPath -ConfigPath "$configDir/stackName_changed.psd1" -InventoryPath $InventoryPath -become $become
        }
        It "Should ensure the stack name is set to 'custom_stack'" {
            $result = Invoke-Command -Session $session -ScriptBlock {
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
            $result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect auto_deployed_pihole --format '{{.HostConfig.RestartPolicy.Name}}'
            }
            $result | Should -Match "always"
        }

        It "Should ensure the Pi-hole container is bound to port 8081" {
            $result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect auto_deployed_pihole --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}'
            }
            $result | Should -Match "8081"
        }

        It "Should ensure the unbound container is bound to port 5353" {
            $result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect auto_deployed_unbound --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}'
            }
            $result | Should -Match "5353"
        }

        It "Should ensure the cloudflared container is bound to port 5054" {
            $result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect auto_deployed_cloudflared --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}'
            }
            $result | Should -Match "5054"
        }

        It "Should ensure the Pi-hole password is changed" {
            $result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect auto_deployed_pihole --format '{{range .Config.Env}}{{println .}}{{end}}'
            }
            $result | Should -Contain "WEBPASSWORD=secret"
        }

        # remove the containers after the context
        AfterAll {
            CleanUpContainers -session $session "$configDir/changes.psd1"
        }
    }

    Context "Host Network" {
        BeforeAll {
            # run the main script
            pwsh -File $scriptPath -ConfigPath "$configDir/host_network.psd1" -InventoryPath $InventoryPath -become $become
        }
        It "Should ensure the container network is set to 'host'" {
            $result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect auto_deployed_pihole --format '{{.HostConfig.NetworkMode}}'
            }
            $result | Should -Match "host"
        }

        # remove the containers after the context
        AfterAll {
            CleanUpContainers -session $session "$configDir/host_network.psd1"
        }
    }

    Context "Empty Ports" {
        BeforeAll {
            # run the main script
            pwsh -File $scriptPath -ConfigPath "$configDir/empty_ports.psd1" -InventoryPath $InventoryPath -become $become
        }
        It "Should ensure the pihole container has no ports bound" {
            $result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect auto_deployed_pihole --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}'
            }
            $result | Should -BeNullOrEmpty
        }

        It "Should ensure the unbound container has no ports bound" {
            $result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect auto_deployed_unbound --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}'
            }
            $result | Should -BeNullOrEmpty
        }

        It "Should ensure the cloudflared container has no ports bound" {
            $result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect auto_deployed_cloudflared --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}'
            }
            $result | Should -BeNullOrEmpty
        }

        # remove the containers after the context
        AfterAll {
            CleanUpContainers -session $session "$configDir/empty_ports.psd1"
        }
    }
}

# cleanup
Remove-PSSession $session
