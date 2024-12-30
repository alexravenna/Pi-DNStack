# Pi-DNStack

## Overview

Pi-DNStack is an automated solution for deploying a containerized DNS management stack, including:

-   **Pi-hole**: Network-wide ad blocking and DNS management
-   **Unbound**: Recursive DNS resolver
-   **Cloudflared**: DNS-over-HTTPS (DoH) proxy

## Features

-   Automated Deployment
-   Declarative Configuration: Compares your .psd1 with the current state and only applies necessary changes
-   Multi-host deployment support
-   Automatic dependency installation

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
    -   SSH access to target server(s) through public key authentication
    -   Supported platforms:
        -   Linux (Debian, RedHat, or Arch based) (Physical or Virtual)
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
