# XRayR
A Xray backend framework that can easily support many panels.

一个基于Xray的后端框架，支持V2ay,Trojan,Shadowsocks协议，极易扩展，支持多面板对接

Find the source code here: [XrayR-project/XrayR](https://github.com/XrayR-project/XrayR)

XrayR已于2022年4月27日删库，此库留作备份使用

XrayR已于7.28回归

# 详细使用教程

[教程](https://crackair.gitbook.io/xrayr-project/)

# 一键安装

> ⚠️ 官方源 `XrayR-project/XrayR` 的代码仓库已删库（release 资产仍在线），
> 且该项目的原始安装脚本长期未更新。本仓库的 `install.sh` / `XrayR.sh` 已修复下列问题：

| 问题 | 说明 |
| --- | --- |
| 下载源全部 404 | 原脚本引用的 `longyi8/XrayR-`、`261818813/XrayR` 均已不存在 |
| 分支名过期 | 仓库默认分支已由 `master` 更名为 `main` |
| `cp ruelist` | 文件名写错，实际为 `rulelist` |
| 永远提示"重启成功" | `check_status` 的返回值被 `echo` 覆盖 |
| 32 位系统拦截失效 | 判断条件写反 |

```
bash <(curl -Ls https://raw.githubusercontent.com/xhcyy1990/XrayR/main/install.sh)
```

也可以先克隆本仓库再安装（脚本会优先使用仓库内的本地副本）：

```
git clone https://github.com/xhcyy1990/XrayR.git
cd XrayR
bash install.sh
```

**可选环境变量**（用于国内服务器下载 GitHub 慢的场景）：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `XrayR_MIRROR` | 空 | GitHub 下载镜像前缀，如 `https://ghproxy.com/` |
| `XrayR_REPO` | `xhcyy1990/XrayR-project` | release 二进制主仓库 |
| `XrayR_FALLBACK_REPO` | `XrayR-project/XrayR` | 主仓库缺少对应 release 资产时的备用仓库 |
| `XrayR_SCRIPT_REPO` | `xhcyy1990/XrayR` | 脚本仓库 |
| `XrayR_SCRIPT_BRANCH` | `main` | 脚本仓库分支 |

例如：`XrayR_MIRROR=https://ghproxy.com/ bash install.sh`

> **关于下载源**：`XrayR_REPO` 默认指向 `xhcyy1990/XrayR-project`，
> 其 tag 形如 `0.9.4`（无 `v` 前缀）；备用仓库 `XrayR-project/XrayR` 的 tag 形如 `v0.9.4`。
> 脚本会自动兼容两种前缀，并在主仓库缺少对应架构资产时回退到备用仓库
> （备用仓库保留了全平台资产：`linux-64` / `linux-arm64-v8a` / `linux-arm32-*` / `linux-mips*` / `linux-s390x` 等）。
# Docker 安装

```
docker pull crackair/xrayr:latest && docker run --restart=always --name xrayr -d -v ${PATH_TO_CONFIG}/config.yml:/etc/XrayR/config.yml --network=host crackair/xrayr:latest
```

# Docker compose 安装
0. 安装docker-compose: 
```
curl -fsSL https://get.docker.com | bash -s docker
curl -L "https://github.com/docker/compose/releases/download/1.26.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
```
1. `git clone https://github.com/xhcyy1990/XrayR.git`
2. `cd XrayR`
3. 编辑config。
配置文件基本格式如下，Nodes下可以同时添加多个面板，多个节点配置信息，只需添加相同格式的Nodes item即可。
4. 启动docker：`docker-compose up -d`
```
Log:
  Level: none # Log level: none, error, warning, info, debug 
  AccessPath: # /etc/XrayR/access.Log
  ErrorPath: # /etc/XrayR/error.log
DnsConfigPath: # /etc/XrayR/dns.json Path to dns config
ConnetionConfig:
  Handshake: 4 # Handshake time limit, Second
  ConnIdle: 10 # Connection idle time limit, Second
  UplinkOnly: 2 # Time limit when the connection downstream is closed, Second
  DownlinkOnly: 4 # Time limit when the connection is closed after the uplink is closed, Second
  BufferSize: 64 # The internal cache size of each connection, kB 
Nodes:
  -
    PanelType: "SSpanel" # Panel type: SSpanel, V2board, PMpanel
    ApiConfig:
      ApiHost: "http://127.0.0.1:667"
      ApiKey: "123"
      NodeID: 41
      NodeType: V2ray # Node type: V2ray, Shadowsocks, Trojan
      Timeout: 30 # Timeout for the api request
      EnableVless: false # Enable Vless for V2ray Type
      EnableXTLS: false # Enable XTLS for V2ray and Trojan
      SpeedLimit: 0 # Mbps, Local settings will replace remote settings, 0 means disable
      DeviceLimit: 0 # Local settings will replace remote settings, 0 means disable
      RuleListPath: # /etc/XrayR/rulelist Path to local rulelist file
    ControllerConfig:
      ListenIP: 0.0.0.0 # IP address you want to listen
      SendIP: 0.0.0.0 # IP address you want to send pacakage
      UpdatePeriodic: 60 # Time to update the nodeinfo, how many sec.
      EnableDNS: false # Use custom DNS config, Please ensure that you set the dns.json well
      DNSType: AsIs # AsIs, UseIP, UseIPv4, UseIPv6, DNS strategy
      EnableProxyProtocol: false # Only works for WebSocket and TCP
      EnableFallback: false # Only support for Trojan and Vless
      FallBackConfigs:  # Support multiple fallbacks
        -
          SNI: # TLS SNI(Server Name Indication), Empty for any
          Path: # HTTP PATH, Empty for any
          Dest: 80 # Required, Destination of fallback, check https://xtls.github.io/config/fallback/ for details.
          ProxyProtocolVer: 0 # Send PROXY protocol version, 0 for dsable
      CertConfig:
        CertMode: dns # Option about how to get certificate: none, file, http, dns. Choose "none" will forcedly disable the tls config.
        CertDomain: "node1.test.com" # Domain to cert
        CertFile: /etc/XrayR/cert/node1.test.com.cert # Provided if the CertMode is file
        KeyFile: /etc/XrayR/cert/node1.test.com.key
        Provider: alidns # DNS cert provider, Get the full support list here: https://go-acme.github.io/lego/dns/
        Email: test@me.com
        DNSEnv: # DNS ENV option used by DNS provider
          ALICLOUD_ACCESS_KEY: aaa
          ALICLOUD_SECRET_KEY: bbb
  # -
  #   PanelType: "V2board" # Panel type: SSpanel, V2board
  #   ApiConfig:
  #     ApiHost: "http://127.0.0.1:668"
  #     ApiKey: "123"
  #     NodeID: 4
  #     NodeType: Shadowsocks # Node type: V2ray, Shadowsocks, Trojan
  #     Timeout: 30 # Timeout for the api request
  #     EnableVless: false # Enable Vless for V2ray Type
  #     EnableXTLS: false # Enable XTLS for V2ray and Trojan
  #     SpeedLimit: 0 # Mbps, Local settings will replace remote settings
  #     DeviceLimit: 0 # Local settings will replace remote settings
  #   ControllerConfig:
  #     ListenIP: 0.0.0.0 # IP address you want to listen
  #     UpdatePeriodic: 10 # Time to update the nodeinfo, how many sec.
  #     EnableDNS: false # Use custom DNS config, Please ensure that you set the dns.json well
  #     CertConfig:
  #       CertMode: dns # Option about how to get certificate: none, file, http, dns
  #       CertDomain: "node1.test.com" # Domain to cert
  #       CertFile: /etc/XrayR/cert/node1.test.com.cert # Provided if the CertMode is file
  #       KeyFile: /etc/XrayR/cert/node1.test.com.pem
  #       Provider: alidns # DNS cert provider, Get the full support list here: https://go-acme.github.io/lego/dns/
  #       Email: test@me.com
  #       DNSEnv: # DNS ENV option used by DNS provider
  #         ALICLOUD_ACCESS_KEY: aaa
  #         ALICLOUD_SECRET_KEY: bbb
```

## Docker compose升级
在docker-compose.yml目录下执行：
```
docker-compose pull
docker-compose up -d
```
