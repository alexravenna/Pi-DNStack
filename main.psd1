# to edit the configuration, remove uncomment the lines you want to change and edit the values as needed

@{
    # restartPolicy      = "unless-stopped"
    # stackName          = "auto_deployed"
    # containerNetwork   = "bridge"

    # piholeImage        = "pihole/pihole:latest"
    # piholeUiPort       = "80"
    # piholeDnsPort      = "53"
    
    # # ! change the password !
    # piholePassword     = "admin"
    # # empty by default, just an example
    # extraDNS = @("8.8.8.8", "1.1.1.1")

    # unboundEnabled     = $true
    # unboundImage       = "mvance/unbound:latest"
    # # external port, not necessary if you wont use unbound outside this stack
    # unboundPort        = ""

    # cloudflaredEnabled = $true
    # cloudflaredImage   = "cloudflare/cloudflared:latest"
    # # external port, not necessary if you wont use cloudflared outside this stack
    # cloudflaredPort    = ""

    # piholeVolumes      = [array]@("/etc/pihole:/etc/pihole", "/etc-dnsmasq.d:/etc/dnsmasq.d")

    # commonFlags        = ""
    # piholeFlags        = ""
    # unboundFlags       = ""
    # cloudflaredFlags   = ""
}