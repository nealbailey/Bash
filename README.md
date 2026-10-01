# Baileysoft Bash Scripts

[![Linux](https://img.shields.io/badge/Linux-supported-FCC624?logo=linux&logoColor=black)](https://www.linux.org/)
[![Bash](https://img.shields.io/badge/Bash-shell-4EAA25?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)

A collection of Linux Bash scripts used on the `baileysoft.lan` intranet. These scripts support system administration, backups, network shares, VPN access, media management, and other local workflows.

## Scripts

| Script | Purpose | Usage |
| --- | --- | --- |
| [`bash_template.sh`](bash_template.sh) | Bash script format template that all shell scripts should utilize. | `./bash_template.sh` |
| [`dnsmasq_hosts.sh`](dnsmasq_hosts.sh) | Updates the dnsmasq hosts file to block ads for all network devices. | `./dnsmasq_hosts.sh` |
| [`killswitch.sh`](killswitch.sh) | Establish or terminate a VPN connection killswitch. | `./killswitch.sh [options]` |
| [`kiosk.sh`](kiosk.sh) | Terminal client for the Kitchen-Kiosk Recipes API. | `./kiosk.sh [options]` |
| [`map-shares.sh`](map-shares.sh) | Provides a graphical user interface to mount Windows shares. | `./map-shares.sh` |
| [`nordvpn.sh`](nordvpn.sh) | Creates a nordvpn split VPN tunnel. | `./nordvpn.sh [options]` |
| [`rsync-incremental.sh`](rsync-incremental.sh) | Nightly incremental mdadm RAID backups to USB. | `./rsync-incremental.sh [options]` |
| [`trade_setup.sh`](trade_setup.sh) | Create and manage various trade setups. | `./trade_setup.sh [options]` |
| [`unmount-all-shares.sh`](unmount-all-shares.sh) | Automatically unmount all mounts Windows samba shares. | `./unmount-all-shares.sh` |
| [`zotify_runner.sh`](zotify_runner.sh) | Rips hi-quality mp3s from Spotify and copies them to a file server. | `./zotify_runner.sh` |

Run a script with `-h` to view each scripts's available options and examples.
Run a script with `-v` to view each script's version infomation.

## Installation

Clone the repository on a Linux system:

```bash
git clone https://github.com/nealbailey/Bash.git
cd Bash
```

Make all scripts executable:

```bash
chmod +x ./*.sh
```

Alternatively, make only the scripts you intend to use executable:

```bash
chmod +x nordvpn.sh killswitch.sh
```

Run a script from the repository:

```bash
./script-name.sh [options]
```

To make selected scripts available system-wide, copy them to a directory on `PATH`, such as `/usr/local/bin`:

```bash
sudo install -m 0755 script-name.sh /usr/local/bin/script-name
```

Review each script's header and configurable variables before installing it. Several scripts reference `baileysoft.lan` hosts, local paths, credentials, services, or configuration files and may require additional packages or root privileges.

## License

Licensed under the [GNU General Public License v3.0](LICENSE).
