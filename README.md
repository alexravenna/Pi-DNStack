# Pi-DNStack

## Overview

Pi-DNStack is an automated solution for deploying a containerized DNS management stack, including:

-   **Pi-hole**: Network-wide ad blocking and DNS management
-   **Unbound**: Recursive DNS resolver
-   **Cloudflared**: DNS-over-HTTPS (DoH) proxy

## Features

-   Automated Preconfigured Deployment
-   Declarative Configuration: Compares your .psd1 with the current state and only applies necessary changes
-   Multi-host deployment support
-   Automatic dependency installation
-   Optional Windows DHCP configuration

## Prerequisites

### System Requirements

-   **Target Server(s)**:

    -   Linux-based operating system
        -   Debian-based (Ubuntu, Debian, etc.)
        -   RedHat-based (RHEL, CentOS, Fedora, etc.)
        -   Other distributions if dependencies are pre-installed
    -   Sufficient privileges

-   **Management Workstation**:
    -   PowerShell 7+
    -   SSH access to the target server(s) through [public key authentication](https://www.digitalocean.com/community/tutorials/how-to-configure-ssh-key-based-authentication-on-a-linux-server)
    -   Supported platforms:
        -   Linux Workstation (Physical or Virtual)
            -   Debian-based: use `apt`
            -   RedHat-based: use `dnf`
            -   Arch-based: use `pacman`
        -   Windows users can use [WSL2](https://docs.microsoft.com/en-us/windows/wsl/install)

## Quick Start

1. **Clone Repository**

    ```bash
    git clone https://github.com/IGLADI/Pi-DNStack && cd Pi-DNStack
    ```

2. **Configure Target Hosts**

    Create an inventory file ([`inventory.ini`](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/ini_inventory.html)) listing your target servers:

    ```bash
    nano inventory.ini
    ```

    Example `inventory.ini`:

    ```ini
    192.168.1.10 ansible_user=ansible
    ```

3. **Configure Deployment**

    Copy and modify the configuration template:

    ```bash
    cp main.psd1.example main.psd1
    nano main.psd1
    ```

    > ⚠️ At minimum, change the default Pi-hole password in the configuration file!

4. **Deploy the Stack**

    ```bash
    pwsh ./main.ps1 -ConfigPath ./main.psd1
    ```

5. **Enjoy!**

    After deployment, access the Pi-hole web interface at: `http://<server-ip>:<port>/admin/login.php` and enjoy your new DNS management stack!

## Windows DHCP Configuration

Pi-DNStack can automatically configure a Windows DHCP server to use Pi-hole. This feature requires:

### Prerequisites

-   Windows Server with DHCP role installed
-   [Powershell SSH remoting access](https://learn.microsoft.com/th-th/powershell/scripting/security/remoting/ssh-remoting-in-powershell?view=powershell-7.4) to the target server(s)
-   Network connectivity between:
    -   Windows DHCP server and Pi-hole server
    -   Management workstation and Windows DHCP server

### Network Considerations

1. **Firewall Rules**:

    - Allow DNS traffic (TCP/UDP 53) between DHCP clients and Pi-hole
    - Allow PowerShell remoting (TCP 5985/5986) from management workstation to DHCP server

2. **Docker Network Mode**:

    - If using `bridge` mode, ensure Pi-hole's DNS port is published (`piholeDnsPort = "53"`)
    - If using `host` mode (recommended for this feature), ensure the host's firewall allows DNS traffic

3. **Pi-hole Listen Configuration**:
    - Ensure Pi-hole is configured to listen to the required interfaces.
