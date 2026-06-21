#!/bin/bash
set -euo pipefail

source ./functions.sh

echo "                                                         "
echo "========================================================="
echo "========================================================="
echo "==                   00   START                        =="
echo "==                                                     =="
echo "========================================================="
echo "========================================================="
echo "                                                         "

cd "$SRC"

# Japansene Keyboard Keymap
localectl set-keymap jp106

# mkdir -p /lib/firmware
# touch /lib/firmware/regulatory.db

mkdir -p /var/lib/alsa

# /etc/profile
cat >> /etc/profile << "EOF"
# loadkeys jp106
ulimit -n 65536

if [ -z "$PKG_CONFIG_PATH" ]; then
    # 空なら、コロンを挟ずにそのまま代入
    export PKG_CONFIG_PATH="/usr/lib/pkgconfig:/usr/share/pkgconfig:/usr/lib64/pkgconfig:/usr/local/lib/pkgconfig"
else
    # すでに値があるなら、後ろにコロンで繋ぐ
    export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:/usr/lib/pkgconfig:/usr/share/pkgconfig:/usr/lib64/pkgconfig:/usr/local/lib/pkgconfig"
fi


export PATH=/usr/local/bin:$PATH:/root/.cargo/bin
export PKG_CONFIG_PATH
export MAKEFLAGS="-j$(nproc)"
export LANG=en_US.UTF-8

# /etc/profile.d/*.sh ファイルを読み込む設定
if [ -d /etc/profile.d ]; then
  for i in /etc/profile.d/*.sh; do
    if [ -r "$i" ]; then
      . "$i"
    fi
  done
  unset i
fi
EOF

echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Timezone Tokyo
ln -sfv /usr/share/zoneinfo/Asia/Tokyo /etc/localtime


# UDEV Not Show
cat >> /etc/udev/udev.conf << 'EOF'
udev_log=err
EOF

cat > /etc/profile.d/bash_colors.sh << "EOF"
# --- 1. dircolors Setting (LS COLOR) ---
if [ -x /usr/bin/dircolors ]; then
    eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
fi

alias vi='vi -u NONE'
alias vim='vim -u NONE'

# --- 3. プロンプト (PS1) の色分け設定 ---
# 色コードの定義（BLUE を CYAN '36' に変えると見やすくなります）
# BLUEは見えにくいので嫌や
RED='\[\e[1;31m\]'
GREEN='\[\e[1;32m\]'
CYAN='\[\e[1;36m\]'  # 見えにくい BLUE の代わりに
RESET='\[\e[0m\]'

if [ $(id -u) -eq 0 ]; then
    PS1="${RED}\u${RESET}@\h:${CYAN}\w${RESET}# "
else
    PS1="${GREEN}\u${RESET}@\h:${CYAN}\w${RESET}$ "
fi

# 256color は vi などの色を誘発するので、
# 色付きプロンプトだけが目的なら標準の xterm でも十分です
export TERM=xterm-256color

# ディレクトリの色を「太字のシアン」に変更する設定
export LS_COLORS=$LS_COLORS:'di=01;36:'
EOF

# 実行権限の付与
chmod +x /etc/profile.d/bash_colors.sh

# 共通の dircolors ファイルがなければ作成しておく
if [ ! -f /etc/dircolors ]; then
    dircolors -p > /etc/dircolors
fi
source /etc/profile
echo "===== Bash Color Setup Complete ====="

INTERFACES=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^e(n|t)' | head -n 1)

mkdir -p /etc/systemd/network

for IFACE in $INTERFACES; do
    echo "Found interface: $IFACE. Creating configuration..."
    
    cat > "/etc/systemd/network/10-${IFACE}.network" << EOF
[Match]
Name=en*

[Network]
DHCP=yes
DNS=8.8.8.8
EOF

    # インターフェースをUPにする
    ip link set "$IFACE" up
done



#  systemd-resolved の設定 (DNS解決に必要)
# DNS=8.8.8.8 を反映させるため、resolved も有効化し、/etc/resolv.conf をリンクします
systemctl enable systemd-resolved
systemctl restart systemd-resolved
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

#  サービスの有効化と開始
systemctl enable systemd-networkd
systemctl restart systemd-networkd

USER_GROUPS="video,input,render,seat,audio,sgx,wheel,pulse,pulse-access,rtkit"

# 1. 必要なグループの一括作成（重複を排除したマスターリスト）
#    -f: 存在すれば何もしない、-r: システムグループ
echo "Creating system groups..."
for grp in video input render seat audio sgx wheel pulse pulse-access rtkit; do
    groupadd -f -r "$grp"
done

# 🌟 追加：一般ユーザーと同名のプライベートグループ（UPG）を安全に作成
echo "Ensuring user private group for '${TARGET_USER}'..."
if ! getent group "$TARGET_USER" &>/dev/null; then
    if id "$TARGET_USER" &>/dev/null; then
        # 既存ユーザーがいる場合はそのGIDを引き継ぐ
        CURRENT_GID=$(id -g "$TARGET_USER")
        groupadd -g "$CURRENT_GID" "$TARGET_USER"
    else
        # 新規作成時は標準のGID 1000で作成
        groupadd -g 1000 "$TARGET_USER"
    fi
fi

echo "Creating system users..."
if ! getent passwd pulse >/dev/null; then
    useradd -c "PulseAudio Revision" -d /var/run/pulse -u 52 -g pulse -s /bin/false pulse
fi

if ! getent passwd rtkit >/dev/null; then
    useradd -c "RealtimeKit Daemon User" -d /var/lib/rtkit -u 133 -g rtkit -s /bin/false rtkit
fi

# 3. 一般ユーザー（user）への権限一括付与とプライマリグループ設定
echo "Configuring target user '${TARGET_USER}'..."
if id "$TARGET_USER" &>/dev/null; then
    echo "Assigning groups to existing '${TARGET_USER}'..."
    usermod -g "$TARGET_USER" -aG "$USER_GROUPS" "$TARGET_USER"
    echo "Success: Groups and Primary Group updated for existing user."
else
    echo "Creating '${TARGET_USER}' with pre-defined groups..."
    useradd -m -s /bin/bash -g "$TARGET_USER" -G "$USER_GROUPS" "$TARGET_USER"
    echo "Success: '${TARGET_USER}' created with primary group and [${USER_GROUPS}]."
fi

rm -rf /var/log/journal/*

mkdir -p /etc/systemd/journald.conf.d/

cat > /etc/systemd/journald.conf.d/storage-volatile.conf << 'EOF'
[Journal]
Storage=volatile
EOF

systemctl restart systemd-journald

# mkdir -p /usr/lib/firmware

# 上流（kernel.org）から本物のデータベースと証明書をダウンロードして配置
# ※ネットワークが繋がっている、またはホストからコピーする場合
# wget https://git.kernel.org/pub/scm/linux/kernel/git/sforshee/wireless-regdb.git/plain/regulatory.db?h=master -O /usr/lib/firmware/regulatory.db
# wget https://git.kernel.org/pub/scm/linux/kernel/git/sforshee/wireless-regdb.git/plain/regulatory.db.p7s?h=master -O /usr/lib/firmware/regulatory.db.p7s

scripts=(

wget
libtasn1
p11-kit
make-ca
wget
curl
git
which
sudo
openssh-1
cpio

)


for pkg in "${scripts[@]}"; do
    echo "========= Building $pkg =========="
    cd "$ROOT_DIR"
    source "./scripts/$pkg"
done

# clear LFS programs
rm -rf /sources/*

echo "                                                         "
echo "========================================================="
echo "========================================================="
echo "==                   00   COMPLETE                     =="
echo "==                                                     =="
echo "========================================================="
echo "========================================================="
echo "                                                         "
