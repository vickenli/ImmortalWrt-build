#!/bin/bash
# 23.05-diy-part1.sh - RAX3000M NAND 高功率版（出错即终止编译）
set -e  # 保持：任何命令失败立即退出编译
# 新增：错误时输出详细信息，便于定位
trap 'echo -e "\033[31m❌ 执行失败：命令 [$BASH_COMMAND] 在第 $LINENO 行出错\033[0m"' ERR

# ==============================================
# 核心新增：分支容错克隆函数（解决main分支不存在问题）
# ==============================================
clone_with_fallback() {
    local repo_url="$1"
    local target_dir="$2"
    local branch="${3:-master}"  # 默认分支master
    local depth=1

    # 创建目标目录（确保父目录存在）
    mkdir -p "$(dirname "$target_dir")"

    # 第一步：尝试克隆指定分支（失败则捕获错误）
    if git clone --depth "$depth" -b "$branch" "$repo_url" "$target_dir" 2>/dev/null; then
        echo -e "\033[32m✅ 成功克隆 [$repo_url] (分支: $branch) 到 [$target_dir]\033[0m"
        return 0
    fi

    # 第二步：指定分支失败，尝试克隆默认分支（无-b参数）
    echo -e "\033[33m⚠️ 分支 [$branch] 不存在，尝试克隆默认分支...\033[0m"
    if git clone --depth "$depth" "$repo_url" "$target_dir" 2>/dev/null; then
        echo -e "\033[32m✅ 成功克隆 [$repo_url] (默认分支) 到 [$target_dir]\033[0m"
        return 0
    fi

    # 第三步：全部失败，终止编译（保持原脚本严格性）
    echo -e "\033[31m❌ 克隆 [$repo_url] 失败（指定分支+默认分支均失败），终止编译\033[0m"
    exit 1
}

# ==============================================
# 1. 目录检查 & 切换（失败则退出）
# ==============================================
if [ ! -d "$GITHUB_WORKSPACE/openwrt" ]; then
    echo -e "\033[31m❌ 错误：openwrt目录不存在，终止编译\033[0m"
    exit 1
fi
cd "$GITHUB_WORKSPACE/openwrt" || {
    echo -e "\033[31m❌ 错误：切换到openwrt目录失败，终止编译\033[0m"
    exit 1
}

# ==============================================
# 2. 添加第三方Feeds（失败则退出）
# ==============================================
echo -e "\033[32m🔧 开始添加第三方Feeds源...\033[0m"
sed -i '$a src-git small https://github.com/kenzok8/small.git;openwrt-23.05' feeds.conf.default
sed -i '$a src-git kenzo https://github.com/kenzok8/openwrt-packages.git;openwrt-23.05' feeds.conf.default

mkdir -p package/custom
# 核心修改：用容错函数替换原git clone，解决main分支不存在问题
clone_with_fallback https://github.com/immortalwrt/homeproxy package/custom/homeproxy main
clone_with_fallback https://github.com/gdy666/luci-app-lucky.git package/custom/lucky main
git clone --depth=1 -b openwrt-23.05 https://github.com/liuzhengyang/luci-app-udpxy.git package/custom/udpxy  # 分支存在，无需容错
clone_with_fallback https://github.com/tailscale/tailscale-openwrt.git package/custom/tailscale main
echo "src-git rtp2httpd https://github.com/stackia/rtp2httpd.git" >> feeds.conf.default

# ==============================================
# 3. 修复MT76驱动版本锁定（核心解决7a71a9f找不到）
# ==============================================
echo -e "\033[32m🔧 开始配置MT76高功率驱动...\033[0m"
# 3.1 删除主仓库自带的mt76（属于主仓库，无7a71a9f提交）
if [ -d "package/kernel/mt76" ]; then
    rm -rf package/kernel/mt76 || {
        echo -e "\033[31m❌ 错误：删除原有mt76目录失败，终止编译\033[0m"
        exit 1
    }
fi

# 3.2 克隆MT76独立仓库（只有独立仓库才有7a71a9f提交）
git clone --depth=100 https://github.com/openwrt/mt76.git package/kernel/mt76 || {
    echo -e "\033[31m❌ 错误：克隆MT76独立仓库失败，终止编译\033[0m"
    exit 1
}

# 3.3 切换到MT76稳定提交（7a71a9f），失败则退出编译
cd package/kernel/mt76 || {
    echo -e "\033[31m❌ 错误：进入mt76目录失败，终止编译\033[0m"
    exit 1
}
git fetch --all || {
    echo -e "\033[31m❌ 错误：拉取MT76提交记录失败，终止编译\033[0m"
    exit 1
}
if ! git reset --hard 7a71a9f; then
    echo -e "\033[31m❌ 错误：MT76驱动无7a71a9f提交，终止编译\033[0m"
    exit 1
fi
cd - || {
    echo -e "\033[31m❌ 错误：返回openwrt根目录失败，终止编译\033[0m"
    exit 1
}

# 3.4 应用RAX3000M高功率补丁，失败则退出
mkdir -p package/custom/patches
wget -q -O package/custom/patches/mt7915_highpower.patch \
    https://raw.githubusercontent.com/immortalwrt/immortalwrt/openwrt-23.05/target/linux/mediatek/patches-5.15/999-mt76-mt7915-hw-config.patch || {
    echo -e "\033[31m❌ 错误：下载高功率补丁失败，终止编译\033[0m"
    exit 1
}
patch -p1 < package/custom/patches/mt7915_highpower.patch || {
    echo -e "\033[31m❌ 错误：应用高功率补丁失败，终止编译\033[0m"
    exit 1
}

# 3.5 配置开机功率解锁，失败则退出
cat > package/base-files/files/etc/rc.local << EOF
#!/bin/sh
sleep 10
[ -n "\$(iw dev wlan0)" ] && iw dev wlan0 set txpower fixed 2800
[ -n "\$(iw dev wlan1)" ] && iw dev wlan1 set txpower fixed 2600
/etc/init.d/network restart
exit 0
EOF || {
    echo -e "\033[31m❌ 错误：写入rc.local失败，终止编译\033[0m"
    exit 1
}
chmod +x package/base-files/files/etc/rc.local || {
    echo -e "\033[31m❌ 错误：设置rc.local权限失败，终止编译\033[0m"
    exit 1
}

# ==============================================
# 4. 更新Feeds & 安装插件（失败则退出）
# ==============================================
echo -e "\033[32m🔧 开始更新Feeds并安装插件...\033[0m"
./scripts/feeds update -a || {
    echo -e "\033[31m❌ 错误：Feeds更新失败，终止编译\033[0m"
    exit 1
}
./scripts/feeds install -a || {
    echo -e "\033[31m❌ 错误：Feeds安装失败，终止编译\033[0m"
    exit 1
}
./scripts/feeds install rtp2httpd luci-app-rtp2httpd || {
    echo -e "\033[31m❌ 错误：安装rtp2httpd失败，终止编译\033[0m"
    exit 1
}

# ==============================================
# 5. 注入编译配置（失败则退出）
# ==============================================
echo -e "\033[32m🔧 开始注入编译配置...\033[0m"
# RTP2HTTPD配置
echo "CONFIG_PACKAGE_rtp2httpd=y" >> .config
echo "CONFIG_PACKAGE_luci-app-rtp2httpd=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-rtp2httpd-zh-cn=y" >> .config
# 高功率驱动配置
echo "CONFIG_PACKAGE_kmod-mt76-disable-ps=y" >> .config
echo "CONFIG_MT76_HW_MGMT=y" >> .config
echo "CONFIG_PACKAGE_crda=y" >> .config
echo "CONFIG_PACKAGE_regdb=y" >> .config

# 合并配置，失败则退出
make defconfig || {
    echo -e "\033[31m❌ 错误：合并配置失败，终止编译\033[0m"
    exit 1
}

# ==============================================
# 6. 完成提示
# ==============================================
echo -e "\033[32m✅ DIY PART1 配置完成！所有步骤验证通过\033[0m"
exit 0
