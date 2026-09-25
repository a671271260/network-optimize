# network-optimize 部署与操作说明

> 适用对象：需要给「中转服务器」做网络优化的运维 / 使用者
> 脚本用途：一键给 Linux 服务器开启 **BBR 加速 + CAKE 限速整形**，适合 100Mbps 的 TCP / Realm 中转线路（台湾、中东等跨境场景）
> 当前版本：**v1.0.2（菜单交互版）**
> 仓库地址：https://github.com/a671271260/network-optimize

---

## 一、这个脚本到底干了啥（大白话）

一句话：**把服务器的网卡调成「BBR 加速 + CAKE 主动限速」的模式，让跨境线路跑得更稳、更少丢包。**

具体做两件事：

1. **调内核 TCP 参数**：开启 BBR 拥塞控制、开启 MTU 探测、把 TCP 缓冲区设为 16MB、加大连接队列。
2. **用 CAKE 限速整形**：把带宽主动压到 100M 以下（台湾 94M / 中东 92M），并按线路延迟设置 RTT，避免跑满被上游限速导致丢包。

现在脚本是**菜单交互版**：运行后出现彩色数字菜单，输入数字回车即可，不用记命令。

---

## 二、环境要求

| 项目 | 要求 |
|------|------|
| 操作系统 | Debian / Ubuntu / CentOS / Rocky / AlmaLinux 等主流发行版均可 |
| 权限 | 除 `status` 查询外**必须 root**，普通用户请加 `sudo` |
| 内核 | 建议 Linux 4.9+（需支持 `tcp_bbr`）；CAKE 需内核支持 `sch_cake` |
| 网络 | 已能正常联网，且有默认出口网卡 |
| 工具 | `iproute2`（提供 `ip` / `tc` 命令） |

> 脚本**不会自动安装**依赖，请先确认系统里有 `ip` 和 `tc`（`command -v ip tc`）。
> CentOS / Rocky / AlmaLinux 装：`yum install -y iproute`；Debian / Ubuntu 装：`apt-get install -y iproute2`。

---

## 三、部署步骤

### 方式 A：一条命令直接跑（推荐，无需上传）

在服务器上直接执行（拉取最新脚本并运行菜单）：

```bash
curl -fsSL --retry 2 --connect-timeout 10 "https://raw.githubusercontent.com/a671271260/network-optimize/main/ty.sh" | sudo bash
```

执行后进入菜单，输入数字选择即可。**首次进入菜单会自动装好快捷命令 `yh`**，以后直接输 `yh` 就能启动。
（脚本已内置兼容：即使这样用管道运行，菜单也能正常接收键盘输入。）

> 若服务器访问不了 `raw.githubusercontent.com`（部分地区网络受限），可改用 git 方式：
>
> ```bash
> git clone --depth 1 https://github.com/a671271260/network-optimize.git /tmp/netopt && sudo bash /tmp/netopt/ty.sh && rm -rf /tmp/netopt
> ```

### 方式 B：先下载再执行

```bash
# 1) 下载到 /root/netopt.sh
curl -fsSL --retry 2 --connect-timeout 10 "https://raw.githubusercontent.com/a671271260/network-optimize/main/ty.sh" -o /root/netopt.sh

# 2) 赋权
chmod +x /root/netopt.sh

# 3) 运行（菜单版）
sudo bash /root/netopt.sh
```

### 方式 C：本地文件上传

```bash
# 在本地把脚本传到服务器（示例）
scp ty.sh root@你的服务器IP:/root/netopt.sh
ssh root@你的服务器IP
chmod +x /root/netopt.sh
bash /root/netopt.sh
```

---

## 四、菜单界面说明

运行脚本后，会看到如下菜单（彩色）：

```
             NETOPT（大字母横幅）
网络优化脚本工具箱  v1.0.2
命令输入 yh 可快速启动脚本
----------------------------------------
1.   台湾线路优化   [94M / 50ms]
2.   中东线路优化   [92M / 160ms]
3.   自定义线路优化
4.   网络状态查询
5.   关闭 CAKE 限速
6.   卸载所有优化
7.   安装快捷启动命令 yh
----------------------------------------
00.  查看使用说明
----------------------------------------
0.   退出脚本
----------------------------------------
请输入你的选择:
```

| 菜单项 | 作用 | 说明 |
|--------|------|------|
| `1` | 台湾线路优化 | 限速 94 Mbps / RTT 50ms |
| `2` | 中东线路优化 | 限速 92 Mbps / RTT 160ms |
| `3` | 自定义线路优化 | 手动输入带宽(Mbps) 和 RTT(ms) |
| `4` | 网络状态查询 | 查看内核、TCP、CAKE、网卡、重传统计 |
| `5` | 关闭 CAKE 限速 | 停用服务，队列恢复为普通 `fq` |
| `6` | 卸载所有优化 | 二次确认后，删除本脚本写入的全部配置 |
| `7` | 安装快捷启动命令 yh | 装好后任意位置输入 `yh` 即可启动本脚本 |
| `00` | 查看使用说明 | 脚本内置帮助 |
| `0` | 退出脚本 | 退出菜单 |

> 每次操作完会提示「按回车键返回主菜单」，可连续操作。

---

## 五、命令行方式（兼容旧用法）

除了菜单，也支持直接带参数运行，适合写进自动化脚本：

| 命令 | 作用 |
|------|------|
| `bash netopt.sh`（无参数） | 进入菜单交互界面 |
| `bash netopt.sh taiwan` | 台湾线路优化（94 Mbps / RTT 50ms） |
| `bash netopt.sh middleeast` | 中东线路优化（92 Mbps / RTT 160ms） |
| `bash netopt.sh custom <Mbps> <RTT>` | 自定义带宽与 RTT，例如 `custom 93 120` |
| `bash netopt.sh status` | 查看当前内核、TCP、CAKE、网卡状态（**普通用户也可运行**） |
| `bash netopt.sh disable-cake` | 关闭 CAKE，退回到普通 `fq` 队列 |
| `yh` | 安装快捷命令后，等价于运行本脚本菜单 |

---

## 六、脚本会写入 / 修改哪些文件

| 路径 | 内容 | 说明 |
|------|------|------|
| `/etc/sysctl.d/99-network-stability.conf` | TCP 内核参数 | 覆盖前自动备份为 `.bak` |
| `/etc/modules-load.d/network-optimize.conf` | 开机加载 `tcp_bbr`、`sch_cake` | 覆盖前自动备份为 `.bak` |
| `/usr/local/sbin/network-cake.sh` | CAKE 限速脚本 | 覆盖前自动备份为 `.bak` |
| `/etc/systemd/system/network-cake.service` | 开机自动恢复限速的服务 | `daemon-reload` + `enable`，并立即应用一次 |
| `/usr/local/bin/netopt.sh` | 快捷命令实际调用的脚本副本 | 首次进入菜单时自动写入（菜单项 `7` 也可手动重装） |
| `/usr/local/bin/yh` | 快捷启动命令 | 首次进入菜单时自动写入（菜单项 `7` 也可手动重装） |

> 脚本在**覆盖同名文件前会自动备份**为 `<原文件名>.bak`（仅备份一次，保留机器上最原始的那份）；卸载时会**优先用 `.bak` 还原**，没有备份则删除。

---

## 七、关键参数说明

### TCP 层（写入 sysctl）

| 参数 | 值 | 作用 |
|------|-----|------|
| `net.ipv4.tcp_congestion_control` | `bbr` | 用 BBR 拥塞控制，跨境高延迟链路提速 |
| `net.core.default_qdisc` | `fq` | 默认队列（稍后会被 CAKE 覆盖） |
| `net.ipv4.tcp_mtu_probing` | `1` | 检测到 PMTU 黑洞后启用探测 |
| `net.core.rmem_max` / `wmem_max` | `16777216`（16MB） | 接收/发送缓冲区上限 |
| `net.ipv4.tcp_rmem / tcp_wmem` | `4096 131072 16777216` / `4096 65536 16777216` | 缓冲区动态范围 |
| `net.core.somaxconn` | `4096` | 监听队列上限 |
| `net.ipv4.tcp_max_syn_backlog` | `4096` | SYN 队列上限 |

> 16MB 已远高于 100Mbps 的 BDP，所以脚本**故意不上 128M/256M/512M**，避免缓冲膨胀（bufferbloat）。

### CAKE 层（网卡限速）

| 参数 | 台湾 | 中东 | 作用 |
|------|------|------|------|
| `bandwidth` | 94Mbit | 92Mbit | 主动压低到 100M 以下，防跑满被限速 |
| `rtt` | 50ms | 160ms | 按线路实际延迟校准队列 |
| `besteffort` | 是 | 是 | 所有流量同一优先级，避免 DSCP 误标干扰 |
| `raw` | 是 | 是 | 不额外叠加链路封装开销 |

---

## 八、常见问题排查

### 1. 提示「请使用 root 权限运行本脚本」
加 `sudo`，或直接切到 root：`sudo -i`。
> 只有 `status`（状态查询）是只读操作，普通用户也能跑；改配置的操作才需要 root。

### 2. 提示「无法自动识别默认出口网卡」
检查路由：`ip route show default`。确认有默认网关后重试。
> 多网卡机器（如同时有内网/公网网卡）可能识别错网卡，可手动指定出口网卡：
>
> ```bash
> IFACE=eth0 bash netopt.sh taiwan
> # 或 sudo IFACE=eth0 bash /root/netopt.sh
> ```

### 3. 提示「当前内核未发现 BBR」
内核不支持或被禁用，脚本会继续执行但 BBR 不会生效。解决：升级内核到 4.9+，或改用支持 BBR 的系统。

### 4. 提示 MTU 不是 1500
脚本**不会自动改 MTU**，只是提醒。若你开了隧道/特殊线路，需要按实际情况手动设置。

### 5. 想临时关掉限速
菜单选 `5`，或执行：

```bash
bash netopt.sh disable-cake
```

会停掉并禁用 `network-cake.service`，把队列恢复成 `fq`。

### 6. 想彻底卸载所有改动
菜单选 `6（卸载所有优化）`，确认后自动还原/清理，并把内核参数恢复为系统默认。也可手动执行：

```bash
# 1) 停用并禁用服务
systemctl disable --now network-cake.service

# 2) 有 .bak 备份则还原原始文件，没有则删除
for f in /usr/local/sbin/network-cake.sh \
         /etc/systemd/system/network-cake.service \
         /etc/sysctl.d/99-network-stability.conf \
         /etc/modules-load.d/network-optimize.conf; do
    [ -f "$f.bak" ] && mv -f "$f.bak" "$f" || rm -f "$f"
done
rm -f /usr/local/bin/netopt.sh /usr/local/bin/yh
systemctl daemon-reload

# 3) 内核参数回默认：拥塞算法 cubic、默认队列 fq_codel
sysctl -w net.ipv4.tcp_congestion_control=cubic
sysctl -w net.core.default_qdisc=fq_codel
sysctl --system

# 4) 删除网卡 root qdisc，回到系统默认队列
IFACE=$(ip route show default | awk '/default/{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1); exit}')
tc qdisc del dev "$IFACE" root 2>/dev/null || true
```

> 想连 TCP Buffer 等参数都完全回到出厂值，重启一次即可。

### 7. 敲 `yh` 提示 `command not found` / 没反应
**原因**：以前用 `curl ... | bash` 这种管道方式运行时，脚本等待输入的 `read` 会去读管道（也就是脚本自身内容），导致菜单选不动数字、`yh` 根本装不上。**v1.0.2 已修复**：菜单改为从终端读键盘，并在首次进入菜单时自动装好 `yh`。

**处理**：用 v1.0.2 的命令重新跑一次（见「方式 A」），进入菜单后 `yh` 即自动装好。若仍不行，手动排查：

```bash
# 看两个文件是否存在、是否为空
ls -l /usr/local/bin/yh /usr/local/bin/netopt.sh
# 看脚本本体行数是否正常（应为几百行，不是 0）
wc -l /usr/local/bin/netopt.sh
# 确认命令目录在 PATH 里
echo $PATH
```

### 8. 查看 TCP 重传（判断线路质量）
菜单选 `4`，或执行：

```bash
nstat -az | grep -E 'TcpRetransSegs|TcpExtTCPTimeouts|TcpExtTCPSpuriousRTOs'
```

### 9. 一键命令拉取脚本失败
仓库已迁到 GitHub。若 `raw.githubusercontent.com` 在你所在网络访问不了，依次尝试：

```bash
# ① raw 直链（推荐）
curl -fsSL --retry 2 --connect-timeout 10 "https://raw.githubusercontent.com/a671271260/network-optimize/main/ty.sh" | sudo bash

# ② GitHub API 原始内容（raw 被墙时的备用）
curl -fsSL --retry 2 --connect-timeout 10 -H "Accept: application/vnd.github.raw" \
  "https://api.github.com/repos/a671271260/network-optimize/contents/ty.sh?ref=main" | sudo bash

# ③ git 浅克隆（最稳，走 443）
git clone --depth 1 https://github.com/a671271260/network-optimize.git /tmp/netopt && sudo bash /tmp/netopt/ty.sh && rm -rf /tmp/netopt
```

> 脚本内置的「安装快捷命令 yh」也用同样的三级回退（raw → API → git）自动下载，无需手动处理。

---

## 九、日常运维速查

```bash
# 看限速队列实时统计（丢包、队列长度等）
tc -s qdisc show dev <出口网卡>

# 看服务状态
systemctl status network-cake.service

# 重启后自动恢复限速（已由 systemd 保证，无需手动）
systemctl is-enabled network-cake.service

# 快捷启动菜单
yh
```

---

## 十、注意事项

1. **重复执行安全**：脚本可重复运行，覆盖同名文件前会自动生成 `.bak` 备份（只备份一次，保留最原始版本），不用担心把原配置冲掉。
2. **只针对 100Mbps 线路调参**：换更大带宽（如 500M/1G）时，`bandwidth` 和 RTT 应重新评估，建议用菜单 `3` 自定义模式。
3. **改完立即生效**：sysctl 和 CAKE 都是即时生效，不需要重启。
4. **自动备份**：无需手动备份，脚本已对将要覆盖的文件自动存 `.bak`；卸载时会优先用 `.bak` 还原。
5. **卸载入口**：要回退到系统默认（含内核参数回 cubic / fq_codel），用菜单 `6（卸载所有优化）` 最省事。

---

## 十一、一键执行示例（复制即用）

```bash
# 1) 直接跑菜单（推荐，首次进菜单自动装好 yh）
curl -fsSL --retry 2 --connect-timeout 10 "https://raw.githubusercontent.com/a671271260/network-optimize/main/ty.sh" | sudo bash

# 2) 或先下载再跑
curl -fsSL --retry 2 --connect-timeout 10 "https://raw.githubusercontent.com/a671271260/network-optimize/main/ty.sh" -o /root/netopt.sh
chmod +x /root/netopt.sh
sudo bash /root/netopt.sh

# 3) 或 git 方式
git clone --depth 1 https://github.com/a671271260/network-optimize.git /tmp/netopt && sudo bash /tmp/netopt/ty.sh && rm -rf /tmp/netopt

# 4) 免交互执行（三选一）
sudo bash /root/netopt.sh taiwan
# sudo bash /root/netopt.sh middleeast
# sudo bash /root/netopt.sh custom 93 120

# 5) 验证
sudo bash /root/netopt.sh status

# 6) 若需回退
sudo bash /root/netopt.sh disable-cake
```
