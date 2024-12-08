# this test script is ment to be launched from the root directory trough CI/CD

param(
    # ? not a secure string right now as it is parsed in become, might make both a secure string later
    $password,
    [string]$configDir = "./tests/configs",
    [string]$scriptPath = "./main.ps1",
    [string]$InventoryPath = "./tests/inventory.ini",
    # become sudo for ansible trough github secrets
    [string]$become = "extra-vars 'ansible_become_password=$password'"
)

$testCases = @(
    @{
        Name         = "Default"
        ConfigPath   = "$configDir/default.psd1"
        TestCommands = @(
            # with help of https://chatgpt.com/share/67559dde-14f4-8011-92ad-a50ad047b36b
            {
                # check that the pihole container is running correctly
                docker ps --filter "name=auto_deployed_pihole" --format "{{.Names}}"
            },
            {
                # check that the pihole container is bound to the correct port (80)
                docker inspect auto_deployed_pihole --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}' | grep "80"
            },
            {
                # check that the pihole container has the correct mount for /etc/pihole
                docker inspect auto_deployed_pihole --format '{{range .Mounts}}{{.Source}}{{end}}' | grep "/etc/pihole"
            },
            {
                # check that the restart policy is correctly set to "unless-stopped"
                docker inspect auto_deployed_pihole --format '{{.HostConfig.RestartPolicy.Name}}' | grep "unless-stopped"
            },
            {
                # check that the container network is set to "bridge"
                docker inspect auto_deployed_pihole --format '{{.HostConfig.NetworkMode}}' | grep "bridge"
            },
            {
                # check that the unbound container is running correctly
                docker ps --filter "name=auto_deployed_unbound" --format "{{.Names}}"
            },
            {
                # check that the cloudflared container is running correctly
                docker ps --filter "name=auto_deployed_cloudflared" --format "{{.Names}}"
            },
            {
                # check that the cloudflared container is bound to the correct port (5053)
                docker inspect auto_deployed_cloudflared --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}' | grep "5053"
            }
        )
    },
    @{
        Name         = "Unbound Disabled"
        ConfigPath   = "$configDir/unbound_disabled.psd1"
        TestCommands = @(
            {
                # check that the unbound container is not running
                docker ps --filter "name=auto_deployed_unbound" --format "{{.Names}}" | wc -l | grep -q '^0$' && Write-Output "container is not running" || Write-Output "Error"
            },
            {
                # check that the cloudflared container is still running correctly
                docker ps --filter "name=auto_deployed_cloudflared" --format "{{.Names}}"
            },
            {
                # check that the pihole container is still running correctly
                docker ps --filter "name=auto_deployed_pihole" --format "{{.Names}}"
            }
        )
    },
    @{
        Name         = "Cloudflared Disabled"
        ConfigPath   = "$configDir/cloudflared_disabled.psd1"
        TestCommands = @(
            {
                # check that the cloudflared container is not running
                docker ps --filter "name=auto_deployed_cloudflared" --format "{{.Names}}" | wc -l | grep -q '^0$' && Write-Output "container is not running" || Write-Output "Error"
            },
            {
                # check that the unbound container is still running correctly
                docker ps --filter "name=auto_deployed_unbound" --format "{{.Names}}"
            },
            {
                # check that the pihole container is still running correctly
                docker ps --filter "name=auto_deployed_pihole" --format "{{.Names}}"
            }
        )
    },
    @{
        Name         = "StackName Changed"
        ConfigPath   = "$configDir/stackName_changed.psd1"
        TestCommands = @(
            {
                # check that the stack name is set to "custom_stack"
                docker ps | grep "custom_stack"
            }
        )
    },
    @{
        Name         = "Multiple Changes"
        ConfigPath   = "$configDir/changes.psd1"
        TestCommands = @(
            # with help of https://chatgpt.com/share/67559dcb-6f98-8011-8b79-3e33b53092bf
            {
                # check that the restart policy is correctly set to "always"
                docker inspect auto_deployed_pihole --format '{{.HostConfig.RestartPolicy.Name}}' | grep "always"
            },
            {
                # check that the Pi-hole container is bound to the correct port (8081)
                docker inspect auto_deployed_pihole --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}' | grep "8081"
            },
            {
                # check that the unbound container is bound to the correct port (5353)
                docker inspect auto_deployed_unbound --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}' | grep "5353"
            },
            {
                # check that the cloudflared container is bound to the correct port (5054)
                docker inspect auto_deployed_cloudflared --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}' | grep "5054"
            },
            {
                # check that the Pi-hole password is changed
                docker inspect auto_deployed_pihole --format '{{range .Config.Env}}{{println .}}{{end}}' | grep "WEBPASSWORD=secret"
            }
        )
    },
    @{
        Name         = "Host Network"
        ConfigPath   = "$configDir/host_network.psd1"
        TestCommands = @(
            {
                # check that the container network is set to "host"
                docker inspect auto_deployed_pihole --format '{{.HostConfig.NetworkMode}}' | grep "host"
            }
        )
    }
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
                                        
# get host and username from inventory file directly, works as it's the test inventory path and avoids to recall the ansible playbook which takes time
$servers = Get-Content $InventoryPath
$server = $servers[-1]
[string]$hostname, $username = $server -split ' '
$username = $username -replace "ansible_user=", ""
                                        
$session = New-PSSession -HostName $hostname -UserName $username -SSHTransport
# clean up in case there are any containers left from previous faild runs
CleanUpContainers -session $session "$configDir/default.psd1"
CleanUpContainers -session $session "$configDir/stackName_changed.psd1"

$passed = $true
foreach ($test in $testCases) {
    Write-Host "Running test: $($test.Name)"
                                            
                                            
    # run the main script w test config
    pwsh -File $scriptPath -ConfigPath $test.ConfigPath -InventoryPath $InventoryPath -become $become
                                            
    $testPassed = $true
                                            
    foreach ($command in $test.TestCommands) {
        try {
            $result = Invoke-Command -Session $session -ScriptBlock {
                param($command)
                $result = Invoke-Expression $command
                return $result
            } -ArgumentList $command

            if (-not $result -or $result -match "Error") {
                $testPassed = $false
                Write-Error "Test '$($test.Name)' failed at command: $command"
            }
        }
        catch {
            $testPassed = $false
            Write-Error "Test '$($test.Name)' crashed at command: $command"
        }
    }

    if ($testPassed) {
        Write-Host "Test '$($test.Name)' passed!" -ForegroundColor Green
    }
    else {
        Write-Error "Test '$($test.Name)' failed."
        # continue instead so that all tests are run and we can see all failures at once
        $passed = $false
    }

    # this will be removed once the stack is declarative
    CleanUpContainers -session $session $test.ConfigPath
}

# cleanup
Remove-PSSession -Session $session

if ($passed) {
    Write-Host "All tests passed!" -ForegroundColor Green
}
else {
    Write-Error "Some tests failed."
    # needed if you don't run the script in a CI/CD pipeline
    exit 1
}
