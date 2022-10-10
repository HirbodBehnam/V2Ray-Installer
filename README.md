# V2Ray Installer
A simple script to install v2fly on Ubuntu or Debian servers.

## Features

* Automatically install service for v2fly
* Support for VMess, VLess, Shadowsocks, Socks5 as protocols
* Support for TCP, TLS, websocket, gRPC as transports
* User management for VMess and VLess
* Generate config files for VMess and VLess
* Generate self signed certificates or use existing certificates
* Ability to manually add rules to config file

## Drawbacks

* This script cannot configure reverse proxies like Nginx or Caddy to work with v2fly. You need to configure them yourself.
* This script will not install firewall; But it will use it if it's installed. For Debian it uses iptables and for Ubuntu it uses ufw.

## Install

On your server run the following command:

```bash
curl -o v2fly.sh https://raw.githubusercontent.com/HirbodBehnam/V2Ray-Installer/master/v2fly.sh && bash v2fly.sh
```
At first, it installs v2fly as service and then it shows you options to manage it.

### Installed Service and Files

The service is installed as `v2ray.service`. The executable itself is installed in `/usr/local/bin/`. The config file is also available in `/usr/local/etc/v2ray/config.json`.

The config file can be freely edited. You can add protocol/transports which are not supported by script to it. Script will not delete them however it's unable to create client configs for them.

### Installed v2ray Version

Script always installs the latest [v2fly release](https://github.com/v2fly/v2ray-core/releases/latest) from GitHub.


## Guides

There are some guides to do some stuff which script is not capable of (for example using a CDN). You can read them from [guides folder](https://github.com/HirbodBehnam/V2Ray-Installer/tree/master/Guides).