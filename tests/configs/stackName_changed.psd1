@{
    # docker restart policy for the whole stack
    # see https://docs.docker.com/engine/containers/start-containers-automatically/#use-a-restart-policy
    restartPolicy      = "unless-stopped"
    # prefix added to all the containers, when executing the script we will only change and deploy containers with this prefix
    stackName          = "custom_stack"
    # network to use for the containers
    # see https://docs.docker.com/engine/network/
    containerNetwork   = "bridge"

    # pihole docker image
    piholeImage        = "pihole/pihole:latest"
    # external web ui port (you can then access the pihole web ui at http://localhost/admin/login.php:port)
    piholeUiPort       = "80"
    # external dns port
    piholeDnsPort      = "53"
    
    # ! change the password !
    # this is the password to access the pihole web ui
    piholePassword     = "admin"
    # list of extra DNS servers to use, default is empty
    # exemple: @("8.8.8.8", "1.1.1.1")
    extraDNS           = @()

    # if you want to use unbound as upstream DNS server
    # see https://docs.pi-hole.net/guides/dns/unbound/ for more information about what unbound is
    unboundEnabled     = $true
    # unbound docker image
    unboundImage       = "mvance/unbound:latest"
    # image used for arm devices like raspberry pi's
    unboundArmImage    = "mvance/unbound-rpi"
    # external port, not necessary if you wont use unbound outside this stack
    unboundPort        = "54"

    # if you want to use cloudflared as upstream DNS server
    cloudflaredEnabled = $true
    # see https://docs.pi-hole.net/guides/dns/cloudflared/ for more information about what cloudflared is
    cloudflaredImage   = "cloudflare/cloudflared:latest"
    # external port, not necessary if you wont use cloudflared outside this stack
    cloudflaredPort    = ""

    # volumes to mount for the pihole container
    piholeVolumes      = @("/etc/pihole:/etc/pihole", "/etc-dnsmasq.d:/etc/dnsmasq.d")

    # extra docker flags to pass to all the containers
    # see https://docs.docker.com/reference/cli/docker/container/exec/
    # exemple: "--cap-add=NET_ADMIN"
    commonFlags        = ""
    # extra docker flags to pass to a specific container
    piholeFlags        = ""
    unboundFlags       = ""
    cloudflaredFlags   = ""
}