@{
    # restartPolicy      = "unless-stopped"
    # stackName          = "auto_deployed"
    # containerNetwork   = "bridge"

    # piholeImage        = "pihole/pihole:latest"
    # piholePort         = "80"
    # # ! change the password !
    # piholePassword     = "admin"

    # unboundEnabled     = $true
    # unboundImage       = "mvance/unbound:latest"
    # unboundPort        = "53"

    # cloudflaredEnabled = $true
    # cloudflaredImage   = "cloudflare/cloudflared:latest"
    # cloudflaredPort    = "5053"

    # piholeVolumes      = [array]@("/etc/pihole:/etc/pihole", "/etc-dnsmasq.d:/etc/dnsmasq.d")

    # commonFlags        = ""
    # piholeFlags        = ""
    # unboundFlags       = ""
    # cloudflaredFlags   = ""
}