# gh-proxy

## 简介

github release、archive以及项目文件的加速项目，支持clone，有Cloudflare Workers无服务器版本以及Python版本

## 演示

[https://gh.api.99988866.xyz/](https://gh.api.99988866.xyz/)

演示站为公共服务，如有大规模使用需求请自行部署，演示站有点不堪重负

![imagea272c95887343279.png](https://img.maocdn.cn/img/2021/04/24/imagea272c95887343279.png)

当然也欢迎[捐赠](#捐赠)以支持作者

## python版本和cf worker版本差异

- python版本支持进行文件大小限制，超过设定返回原地址 [issue #8](https://github.com/hunshcn/gh-proxy/issues/8)

- python版本支持特定user/repo 封禁/白名单 以及passby [issue #41](https://github.com/hunshcn/gh-proxy/issues/41)

## 使用

直接在copy出来的url前加`https://gh.api.99988866.xyz/`即可

也可以直接访问，在input输入

***大量使用请自行部署，以上域名仅为演示使用。***

访问私有仓库可以通过

`git clone https://user:TOKEN@ghproxy.com/https://github.com/xxxx/xxxx` [#71](https://github.com/hunshcn/gh-proxy/issues/71)

以下都是合法输入（仅示例，文件不存在）：

- 分支源码：https://github.com/hunshcn/project/archive/master.zip

- release源码：https://github.com/hunshcn/project/archive/v0.1.0.tar.gz

- release文件：https://github.com/hunshcn/project/releases/download/v0.1.0/example.zip

- 分支文件：https://github.com/hunshcn/project/blob/master/filename

- commit文件：https://github.com/hunshcn/project/blob/1111111111111111111111111111/filename

- gist：https://gist.githubusercontent.com/cielpy/351557e6e465c12986419ac5a4dd2568/raw/cmd.py

## cf worker版本部署

首页：https://workers.cloudflare.com

注册，登陆，`Start building`，取一个子域名，`Create a Worker`。

复制 [index.js](https://cdn.jsdelivr.net/gh/hunshcn/gh-proxy@master/index.js)  到左侧代码框，`Save and deploy`。如果正常，右侧应显示首页。

`ASSET_URL`是静态资源的url（实际上就是现在显示出来的那个输入框单页面）

`PREFIX`是前缀，默认（根路径情况为"/"），如果自定义路由为example.com/gh/*，请将PREFIX改为 '/gh/'，注意，少一个杠都会错！

## Python版本部署

### Docker部署

```
docker run -d --name="gh-proxy-py" \
  -p 0.0.0.0:80:80 \
  --restart=always \
  hunsh/gh-proxy-py:latest
```

第一个80是你要暴露出去的端口

### 直接部署

安装依赖（请使用python3）

```pip install flask requests```

按需求修改`app/main.py`的前几项配置

*注意:* 可能需要在`return Response`前加两行
```python3
if 'Transfer-Encoding' in headers:
    headers.pop('Transfer-Encoding')
```

### 注意

python版本的机器如果无法正常访问github.io会启动报错，请自行修改静态文件url

python版本默认走服务器（2021.3.27更新）

---

## ⚡ 性能调优与 1核1GB 小鸡极轻量/安全部署指南

在 1核 1GB 内存的低配云服务器（小鸡）上代理大文件（如 HuggingFace 模型权重、GitHub Releases）时，必须针对**内存、磁盘与安全**进行专门优化，否则极易导致 **OOM 崩机、磁盘写满或被他人扫到蹭光流量**。

---

### 1. 彻底关闭磁盘缓冲（核心：0 磁盘写盘，纯内存流式直推）

> **⚠️ 为什么必须关闭缓冲**：  
> Nginx 代理 uWSGI/HTTP 时默认开启缓冲（`uwsgi_buffering on;` 或 `proxy_buffering on;`）。当上游下载速度大于本地接收速度时，Nginx 会将几十 GB 的数据先写入 VPS 本地磁盘（`/var/lib/nginx/tmp/`），不仅 100% 刷爆小鸡硬盘，还会导致极高的磁盘 IO 卡死整机。

在 Nginx 的反代配置中加入以下指令，开启**零拷贝实时内存直推**：

```nginx
# 1. 纯内存直推与防超时配置（根据你的部署方式二选一）

# 方式 A：如果使用 uwsgi_pass（如官方 Docker 镜像内部）
location / {
    include uwsgi_params;
    uwsgi_pass unix:///tmp/uwsgi.sock;  # 或 127.0.0.1:81;
    
    # 核心：彻底关闭缓冲，数据 0 磁盘落地，纯内存流式传输
    uwsgi_buffering off;
    uwsgi_request_buffering off;

    # 调大长连接超时（防止数十GB大文件下载因超时断开）
    uwsgi_read_timeout 3600s;
    uwsgi_send_timeout 3600s;
    uwsgi_connect_timeout 60s;
    
    # 透传 Range 报头，确保多线程断点续传生效
    uwsgi_pass_request_headers on;
}

# 方式 B：如果使用宿主机 Nginx 纯 HTTP 反代容器（proxy_pass）
location / {
    proxy_pass http://127.0.0.1:8080;
    
    # 核心：关闭磁盘临时缓冲
    proxy_buffering off;
    proxy_request_buffering off;
    
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
    proxy_connect_timeout 60s;
    
    # 关闭 access 日志，消除海量分块请求的高频磁盘写盘
    access_log off;
}
```

---

### 2. 针对 1核 1GB 内存小鸡的极轻量并发配置（`app/uwsgi.ini`）

> **⚠️ 为什么小鸡绝不能开多进程/重度多线程**：  
> Python Flask 每个进程基础占用约 40~60MB 内存。如果配置 4 个进程 8 个线程，加上 Linux 系统本身和 Nginx，内存会直接突破 800MB+，导致系统触发 Linux OOM Killer 杀掉 Python 容器导致经常掉线。  
> **1核 1GB 的最佳方案是：1 个单进程 + 2 个轻量线程**。

修改 `app/uwsgi.ini`：

```ini
[uwsgi]
module = main
callable = app
master = true

# 单核小鸡专属：1个 worker 进程配合 2 个轻量线程
# 总内存占用死死控制在 50MB 左右，CPU 占用极低
processes = 1
threads = 2

# 关键防崩保护：单 worker 物理内存超过 200MB 时自动优雅回收，杜绝大文件传输潜在的内存泄漏
reload-on-rss = 200

# 缓冲区与超时
buffer-size = 32768
harakiri = 3600
socket-timeout = 600
```

---

### 3. Python 后端（`app/main.py`）优化与修复

1. **分块大小（`CHUNK_SIZE`）**：
   - 设为 `64 KB`（`64 * 1024`）。每个连接在内存中仅占 64KB 缓冲，既保证满速带宽吞吐，又不会撑爆小鸡的 1GB 内存。
2. **修复重定向 500/502 报错（如 HuggingFace 等）**：
   - 上游（如 HuggingFace、GitHub CDN）返回相对路径重定向（如 `/api/resolve-cache/...`）时，使用 `urljoin` 自动补全协议头，避免 requests 抛出 `MissingSchema` 崩溃。
3. **剔除逐跳请求头**：
   - 自动过滤 `Transfer-Encoding`, `Connection`, `Keep-Alive`，避免与 Nginx 反向代理协议报头冲突。
4. **修复 Query 参数拼接**：
   - 使用标准 `request.query_string` 拼接，避免在经过 Nginx 反向代理 SSL 终结后 `request.base_url` 替换异常导致 URL 重复。

---

## Cloudflare Workers计费

到 `overview` 页面可参看使用情况。免费版每天有 10 万次免费请求，并且有每分钟1000次请求的限制。

如果不够用，可升级到 $5 的高级版本，每月可用 1000 万次请求（超出部分 $0.5/百万次请求）。

## Changelog

* 2020.04.10 增加对`raw.githubusercontent.com`文件的支持
* 2020.04.09 增加Python版本（使用Flask）
* 2020.03.23 新增了clone的支持
* 2020.03.22 初始版本

## 链接

[我的博客](https://hunsh.net)

## 参考

[jsproxy](https://github.com/EtherDream/jsproxy/)

## 捐赠

![wx.png](https://img.maocdn.cn/img/2021/04/24/image.md.png)
![ali.png](https://www.helloimg.com/images/2021/04/24/BK9vmb.md.png)
