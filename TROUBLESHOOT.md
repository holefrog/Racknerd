# 🚀 RackNerd VPS 自动化部署工具

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-Rocky%20Linux%20%7C%20AlmaLinux-red.svg)
![Status](https://img.shields.io/badge/status-production%20ready-green.svg)

一键将全新的 **RackNerd VPS** 配置为功能完整的生产环境，包含 Nginx、SSL、FTP、Aria2、V2Ray 等服务。

---

## ✨ 主要特性

### 🔐 安全加固
- ✅ 自动申请和配置 Let's Encrypt SSL 证书
- ✅ SSH 端口修改 + 防火墙规则
- ✅ SELinux 配置
- ✅ FTP 用户 chroot 隔离

### 🌐 Web 服务
- ✅ Nginx 反向代理 + HTTPS 强制跳转
- ✅ Node.js 服务器（系统信息展示）
- ✅ 自动证书续期

### 📥 下载服务
- ✅ Aria2 下载器 + RPC 接口
- ✅ FTP 服务器（被动模式）

### 🔒 代理服务
- ✅ V2Ray (VMess + WebSocket + TLS)
- ✅ 自动生成客户端配置和订阅链接

### 🌍 动态域名
- ✅ ChangeIP DDNS 自动更新（可选）

### ⚡ 系统优化
- ✅ TCP BBR 拥塞控制
- ✅ 系统依赖自动安装

---

## 📁 项目结构

```
RackNerd-Setup/
├── setup.sh                  # 本地部署入口脚本
├── stage_1.sh                # 阶段 1：系统初始化
├── stage_2.sh                # 阶段 2：服务部署
├── pre-check.sh              # 部署前环境检查
├── config.ini.example        # 配置文件示例
├── config.ini                # 实际配置文件（需创建）
│
├── lib/
│   ├── env.sh                # 环境变量定义
│   └── utils.sh              # 工具函数（日志、模板替换等）
│
├── modules/                  # 功能模块
│   ├── 01-system.sh          # 系统更新、BBR 启用
│   ├── 02-ftp.sh             # FTP 服务器配置
│   ├── 03-nginx.sh           # Nginx + SSL 配置
│   ├── 04-nodejs.sh          # Node.js 服务
│   ├── 05-aria2.sh           # Aria2 下载器
│   ├── 06-v2ray.sh           # V2Ray 代理
│   ├── 07-ddns.sh            # DDNS 动态域名
│   └── 99-security.sh        # SSH 端口修改
│
└── templates/                # 配置模板
    ├── configs/              # 服务配置文件
    │   ├── vsftpd.conf       # FTP 配置
    │   ├── nginx.conf        # Nginx 主配置
    │   ├── site.conf         # 站点配置
    │   ├── aria2.conf        # Aria2 配置
    │   ├── v2ray.json        # V2Ray 服务端配置
    │   └── vmess_client.json # V2Ray 客户端配置
    │
    ├── scripts/              # 脚本文件
    │   ├── server.js         # Node.js 服务器
    │   ├── renew-cert.sh     # SSL 证书续期
    │   └── changeip.sh       # DDNS 更新脚本
    │
    ├── services/             # Systemd 服务单元
    │   ├── nodejs.service    # Node.js 服务
    │   ├── aria2.service     # Aria2 服务
    │   └── v2ray.service     # V2Ray 服务
    │
    └── web/                  # 静态网页文件
        ├── index.html        # 默认首页
        └── showinfo.html     # 系统信息页面
```

---

## 🛠️ 快速开始

### 前置要求

- **VPS 系统**：Rocky Linux 8/9 或 AlmaLinux 8/9（RackNerd 默认系统）
- **本地系统**：Linux / macOS / WSL
- **域名**：已解析到 VPS IP 的域名（用于 SSL 证书）
- **本地工具**：bash, ssh, scp, awk, sed

---

### 步骤 1：克隆项目

```bash
git clone https://github.com/holefrog/Racknerd.git
cd Racknerd
```

---


---

### 步骤 2：生成 SSH 密钥

如果还没有 SSH 密钥：

```bash
mkdir -p rpi_keys
ssh-keygen -t rsa -b 4096 -f rpi_keys/id_rsa -N ""

# 上传公钥到 VPS（替换 YOUR_VPS_IP）
ssh-copy-id -i rpi_keys/id_rsa.pub root@YOUR_VPS_IP
```

---

### 步骤 3：配置文件

```bash
cp config.ini.example config.ini
nano config.ini
```

#### 必须修改的配置项：

```ini
[ssh]
host=YOUR_VPS_IP              # 替换为 VPS IP 地址
user=root
port=22
key=./rpi_keys/id_rsa         # SSH 私钥路径

[nginx]
domain=example.com            # 替换为你的域名
email=admin@example.com       # 替换为你的邮箱

[ftp]
password=STRONG_PASSWORD_HERE # 设置强密码

[aria2]
token=YOUR_SECRET_TOKEN       # 设置 RPC 密钥

[v2ray]
path_url=ws_random_string     # 随机字符串（WebSocket 路径）
```

#### 可选配置：

```ini
[ports]
ssh_new=22022                 # 修改 SSH 端口（推荐）
nodejs=3000
aria2=6800
v2ray=10086

[ddns]
enable=yes                    # 启用 DDNS
user=changeip_username
password=changeip_password
hostname=your.changeip.com
```

---

### 步骤 4：开始部署

```bash
./setup.sh
```

部署过程：
1. **上传文件** → VPS
2. **阶段 1**：系统更新、BBR 启用
3. **自动重启**
4. **阶段 2**：安装所有服务
5. **服务检查**
6. **显示部署摘要**

**预计耗时**：10-15 分钟（取决于网络和 VPS 性能）

---

### 步骤 5：验证部署

使用新的 SSH 端口登录：

```bash
ssh -i rpi_keys/id_rsa -p 22022 root@YOUR_VPS_IP
```

检查服务状态：

```bash
systemctl status nginx aria2 v2ray nodejs vsftpd
```

检查端口监听：

```bash
ss -tlnp | grep -E ":(21|443|3000|6800|10086)"
```

访问网站：

```bash
https://your-domain.com
```

---

## 📋 服务说明

### 1. Nginx（Web 服务器）

- **端口**：80 (HTTP, 自动跳转), 443 (HTTPS)
- **配置文件**：`/etc/nginx/conf.d/YOUR_DOMAIN.conf`
- **站点目录**：`/usr/share/nginx/YOUR_DOMAIN/`
- **SSL 证书**：`/etc/letsencrypt/live/YOUR_DOMAIN/`
- **自动续期**：每月 1 号凌晨自动续期

**管理命令**：
```bash
systemctl restart nginx
nginx -t                    # 测试配置
certbot renew --dry-run     # 测试证书续期
```

---

### 2. FTP 服务器（vsftpd）

- **端口**：21 (控制), 40000-40100 (被动模式)
- **用户**：config.ini 中配置的 ftp.user
- **目录**：config.ini 中配置的 ftp.path (默认 `/var/ftp/files`)
- **安全**：chroot 限制用户在主目录

**连接方式**：
```bash
ftp YOUR_VPS_IP
# 或使用 FileZilla 等 FTP 客户端
```

**管理命令**：
```bash
systemctl restart vsftpd
journalctl -u vsftpd -f     # 查看日志
```

---

### 3. Aria2（下载器）

- **端口**：6800 (RPC)
- **配置文件**：`/etc/aria2/aria2.conf`
- **下载目录**：FTP 目录（共享）
- **WebUI**：通过 Nginx 反向代理访问

**RPC 连接信息**：
- **地址**：`https://YOUR_DOMAIN/jsonrpc`
- **密钥**：config.ini 中的 `aria2.token`

**推荐 WebUI**：
- [AriaNg](https://github.com/mayswind/AriaNg)
- [Aria2 WebUI](https://github.com/ziahamza/webui-aria2)

**管理命令**：
```bash
systemctl restart aria2
tail -f /etc/aria2/aria2.log
```

---

### 4. V2Ray（代理服务）

- **端口**：10086 (可修改)
- **协议**：VMess + WebSocket + TLS
- **路径**：`/YOUR_PATH_URL` (config.ini 中配置)
- **配置文件**：`/etc/v2ray/v2ray.json`

**客户端配置**：
1. **方式一**：复制 Base64 订阅链接
   ```bash
   cat /var/ftp/files/v2ray_sub.txt
   ```

2. **方式二**：手动配置
   ```bash
   cat /etc/v2ray/vmess_client.json
   ```

**客户端参数**：
- **地址**：YOUR_DOMAIN
- **端口**：10086 (或自定义)
- **UUID**：自动生成（首次部署时显示）
- **传输**：ws (WebSocket)
- **路径**：/YOUR_PATH_URL
- **TLS**：启用

**管理命令**：
```bash
systemctl restart v2ray
journalctl -u v2ray -f      # 查看日志
```

---

### 5. Node.js（系统信息服务）

- **端口**：3000
- **功能**：显示主机和访客信息、失败登录记录

**API 端点**：
- `https://YOUR_DOMAIN/host-info` - 主机信息
- `https://YOUR_DOMAIN/visitor-info` - 访客信息

**管理命令**：
```bash
systemctl restart nodejs
journalctl -u nodejs -f     # 查看日志
```

---

### 6. DDNS（动态域名，可选）

- **服务商**：ChangeIP.com
- **更新频率**：每 15 分钟
- **日志**：`/var/log/changeip.log`

**手动运行**：
```bash
/usr/local/bin/changeip.sh
```

**查看日志**：
```bash
tail -f /var/log/changeip.log
```

---

## 🔧 常见问题

### Q1: SSL 证书申请失败？

**原因**：
1. 域名 DNS 未解析到 VPS IP
2. 防火墙未开放 80/443 端口
3. Nginx 未正确安装

**解决方法**：
```bash
# 检查 DNS 解析
dig YOUR_DOMAIN +short

# 检查防火墙
firewall-cmd --list-all

# 手动申请证书
certbot certonly --nginx -d YOUR_DOMAIN --email YOUR_EMAIL --agree-tos
```

---

### Q2: 服务无法启动？

```bash
# 查看服务状态
systemctl status SERVICE_NAME

# 查看详细日志
journalctl -xeu SERVICE_NAME

# 重启服务
systemctl restart SERVICE_NAME
```

---

### Q3: SSH 连接断开？

如果修改了 SSH 端口，立即使用新端口登录：

```bash
ssh -i rpi_keys/id_rsa -p 22022 root@YOUR_VPS_IP
```

如果无法连接，联系 RackNerd 客服通过 VNC 恢复。

---

### Q4: V2Ray 客户端无法连接？

**检查**：
1. UUID 是否正确（查看 `/etc/v2ray/v2ray.json`）
2. WebSocket 路径是否匹配
3. 端口是否开放
4. TLS 是否启用

```bash
# 查看 V2Ray 配置
cat /etc/v2ray/v2ray.json

# 查看客户端配置
cat /etc/v2ray/vmess_client.json

# 测试端口
nc -zv localhost 10086
```

---

### Q5: FTP 无法连接？

```bash
# 检查 FTP 服务
systemctl status vsftpd

# 检查防火墙
firewall-cmd --list-all | grep ftp

# 查看 FTP 日志
journalctl -u vsftpd -f
```

---

## 🔐 安全建议

### 1. 定期更新系统
```bash
dnf update -y
```

### 2. 更改默认端口
在 `config.ini` 中修改：
```ini
[ports]
ssh_new=自定义端口
aria2=自定义端口
v2ray=自定义端口
```

### 3. 使用强密码
- FTP 密码至少 16 位
- Aria2 token 使用随机字符串
- V2Ray path_url 使用随机字符串

### 4. 限制访问
编辑 `/etc/nginx/conf.d/YOUR_DOMAIN.conf`：
```nginx
location /host-info {
    allow YOUR_HOME_IP;
    deny all;
    proxy_pass http://localhost:3000/host-info;
}
```

### 5. 监控日志
```bash
# 失败登录
lastb -n 20

# 系统日志
journalctl -p err -n 50

# Nginx 访问日志
tail -f /var/log/nginx/access.log
```

---

## 📚 目录和文件位置

| 服务 | 配置文件 | 日志文件 | 数据目录 |
|------|---------|---------|---------|
| Nginx | `/etc/nginx/conf.d/` | `/var/log/nginx/` | `/usr/share/nginx/DOMAIN/` |
| FTP | `/etc/vsftpd/vsftpd.conf` | `/var/log/messages` | `/var/ftp/files/` |
| Aria2 | `/etc/aria2/aria2.conf` | `/etc/aria2/aria2.log` | FTP 目录 |
| V2Ray | `/etc/v2ray/v2ray.json` | `/etc/v2ray/*.log` | - |
| Node.js | `/usr/share/nginx/DOMAIN/` | `journalctl -u nodejs` | - |
| SSL | `/etc/letsencrypt/live/` | `/var/log/letsencrypt/` | - |

---

## 🚀 高级用法

### 添加新域名

1. 申请新证书：
```bash
certbot certonly --nginx -d new-domain.com --email your@email.com
```

2. 复制站点配置：
```bash
cp /etc/nginx/conf.d/old-domain.conf /etc/nginx/conf.d/new-domain.conf
```

3. 修改配置中的域名和证书路径

4. 重载 Nginx：
```bash
nginx -t && systemctl reload nginx
```

---

### 添加新模块

1. 在 `modules/` 目录创建新脚本（例如 `10-mysql.sh`）
2. 在 `stage_2.sh` 中添加：
```bash
bash modules/10-mysql.sh
```

---

### 自定义 Nginx 配置

编辑 `/etc/nginx/conf.d/YOUR_DOMAIN.conf`，然后：
```bash
nginx -t && systemctl reload nginx
```

---

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

1. Fork 本项目
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

---

## 📜 开源许可

MIT License - 详见 [LICENSE](LICENSE) 文件

---

## 📞 支持

- **GitHub Issues**: [https://github.com/holefrog/Racknerd/issues](https://github.com/holefrog/Racknerd/issues)
- **文档**: [项目 Wiki](https://github.com/holefrog/Racknerd/wiki)

---

## 🙏 致谢

- [Nginx](https://nginx.org/)
- [V2Ray](https://www.v2fly.org/)
- [Aria2](https://aria2.github.io/)
- [Let's Encrypt](https://letsencrypt.org/)
- [RackNerd](https://www.racknerd.com/)

---

## ⭐ Star History

如果这个项目对你有帮助，请给个 Star ⭐️

---

**最后更新**: 2024-11-20
