@{
    # docker restart policy for the whole stack
    # see https://docs.docker.com/engine/containers/start-containers-automatically/#use-a-restart-policy
    restartPolicy      = "unless-stopped"
    # prefix added to all the containers, when executing the script we will only change and deploy containers with this prefix
    stackName          = "auto_deployed"
    # network to use for the containers
    # see https://docs.docker.com/engine/network/
    containerNetwork   = "bridge"

    # pihole docker image
    piholeImage        = "pihole/pihole:latest"
    # external web ui port (you can then access the pihole web ui at http://localhost/admin/login.php:port)
    piholeUiPort       = "80"
    # external dns port
    piholeDnsPort      = "53"
    DNSSECEnabled      = $true
    adlists            = @("https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts",
        "https://adaway.org/hosts.txt",
        "https://v.firebog.net/hosts/AdguardDNS.txt",
        "https://v.firebog.net/hosts/Admiral.txt",
        "https://raw.githubusercontent.com/anudeepND/blacklist/master/adservers.txt",
        "https://v.firebog.net/hosts/Easylist.txt",
        "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext",
        "https://raw.githubusercontent.com/FadeMind/hosts.extras/master/UncheckyAds/hosts",
        "https://raw.githubusercontent.com/bigdargon/hostsVN/master/hosts",
        "https://v.firebog.net/hosts/Easyprivacy.txt",
        "https://v.firebog.net/hosts/Prigent-Ads.txt",
        "https://raw.githubusercontent.com/FadeMind/hosts.extras/master/add.2o7Net/hosts",
        "https://raw.githubusercontent.com/crazy-max/WindowsSpyBlocker/master/data/hosts/spy.txt",
        "https://hostfiles.frogeye.fr/firstparty-trackers-hosts.txt",
        "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/Alternate%20versions%20Anti-Malware%20List/AntiMalwareHosts.txt",
        "https://osint.digitalside.it/Threat-Intel/lists/latestdomains.txt",
        "https://v.firebog.net/hosts/Prigent-Crypto.txt",
        "https://raw.githubusercontent.com/FadeMind/hosts.extras/master/add.Risk/hosts",
        "https://bitbucket.org/ethanr/dns-blacklists/raw/8575c9f96e5b4a1308f2f12394abd86d0927a4a0/bad_lists/Mandiant_APT1_Report_Appendix_D.txt",
        "https://phishing.army/download/phishing_army_blocklist_extended.txt",
        "https://gitlab.com/quidsup/notrack-blocklists/raw/master/notrack-malware.txt",
        "https://v.firebog.net/hosts/RPiList-Malware.txt",
        "https://v.firebog.net/hosts/RPiList-Phishing.txt",
        "https://raw.githubusercontent.com/Spam404/lists/master/main-blacklist.txt",
        "https://raw.githubusercontent.com/AssoEchap/stalkerware-indicators/master/generated/hosts",
        "https://urlhaus.abuse.ch/downloads/hostfile/",
        "https://zerodot1.gitlab.io/CoinBlockerLists/hosts_browser",
        "https://raw.githubusercontent.com/PolishFiltersTeam/KADhosts/master/KADhosts.txt",
        "https://raw.githubusercontent.com/FadeMind/hosts.extras/master/add.Spam/hosts",
        "https://v.firebog.net/hosts/static/w3kbl.txt")
    
    
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
    cloudflaredEnabled = $false
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