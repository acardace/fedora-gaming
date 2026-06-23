# Build stage for umu-launcher
FROM quay.io/fedora/fedora:latest AS umu-builder

RUN dnf install -y \
        rpm-build rpmdevtools \
        meson ninja-build cmake \
        g++ gcc-c++ \
        scdoc git \
        python3-devel python3-build python3-installer python3-hatchling \
        python python3 python3-pip \
        libzstd-devel \
        python3-hatch-vcs python3-wheel python3-xlib python3-pyzstd \
        cargo

COPY spec_files/umu-launcher/umu-launcher.spec /tmp/umu-launcher.spec

RUN mkdir -p /root/rpmbuild/{SOURCES,SPECS} && \
    cp /tmp/umu-launcher.spec /root/rpmbuild/SPECS/ && \
    spectool -g -R /root/rpmbuild/SPECS/umu-launcher.spec && \
    rpmbuild -bb /root/rpmbuild/SPECS/umu-launcher.spec

# Base gaming bootc image (GPU-agnostic)
# GPU-specific layers are added by Containerfile.amd and Containerfile.nvidia
FROM quay.io/fedora/fedora-bootc:latest

# Install fish shell (used as default shell) and libvirt (for libvirt group)
# Configure timezone, sudoers, and SELinux
RUN dnf install -y fish libvirt && \
    dnf clean all && \
    ln -sf ../usr/share/zoneinfo/Europe/Rome /etc/localtime && \
    echo '%wheel ALL=(ALL) ALL' > /etc/sudoers.d/wheel && \
    # Set fish as root's shell
    usermod -s /usr/bin/fish root && \
    # Required for Steam Big Picture mode
    setsebool -P allow_execheap 1

# Copy umu-launcher RPM from builder
COPY --from=umu-builder /root/rpmbuild/RPMS/*/*.rpm /tmp/

# Add third-party repositories:
#  - negativo17: Steam, multimedia codecs, RAR
#  - Terra Mesa: Valve-patched Mesa (26.x)
#  - Bazzite COPRs: patched pipewire, bluez, wireplumber, Xwayland
#  - RPM Fusion: freeworld codecs
#  - Other COPRs: LatencyFleX, LACT, Sunshine, cachyos-addons
RUN dnf install -y 'dnf5-command(copr)' && \
    dnf config-manager addrepo --from-repofile=https://negativo17.org/repos/fedora-steam.repo && \
    dnf config-manager addrepo --from-repofile=https://negativo17.org/repos/fedora-multimedia.repo && \
    dnf config-manager addrepo --from-repofile=https://negativo17.org/repos/fedora-rar.repo && \
    dnf install -y --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
        terra-release terra-release-extras terra-release-mesa && \
    dnf copr enable -y kylegospo/LatencyFleX && \
    dnf copr enable -y ilyaz/LACT && \
    dnf copr enable -y lizardbyte/beta && \
    dnf copr enable -y bieszczaders/kernel-cachyos-addons && \
    dnf install -y \
        https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
        https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm && \
    dnf config-manager setopt "fedora-steam".priority=4 && \
    dnf config-manager setopt "fedora-multimedia".priority=4 \
        "fedora-multimedia".exclude="gstreamer1-plugins-bad gstreamer1-plugins-ugly vlc-plugins-base" && \
    dnf config-manager setopt "fedora-rar".priority=4 && \
    dnf config-manager setopt "*rpmfusion*".priority=5 "*rpmfusion*".exclude="vlc-*" && \
    dnf config-manager setopt "fedora".exclude="vlc-*" "updates".exclude="vlc-*" && \
    dnf clean all

# Swap Mesa for Terra Mesa (Valve-patched, 26.x)
# Terra Mesa has higher priority so subsequent installs pull mesa from there.
# Note: mesa-va-drivers is obsoleted by mesa-dri-drivers in Mesa 26.x
RUN dnf -y swap --repo=terra-mesa mesa-filesystem mesa-filesystem && \
    dnf config-manager setopt "terra-mesa".priority=1 && \
    dnf5 versionlock add \
        mesa-dri-drivers \
        mesa-filesystem \
        mesa-libEGL \
        mesa-libGL \
        mesa-libgbm \
        mesa-vulkan-drivers && \
    dnf clean all

# Install KDE Plasma desktop (pulls in pipewire, wireplumber, bluez, Xwayland)
RUN dnf install -y \
        @kde-desktop-environment \
        plasma-workspace plasma-desktop \
        dolphin kitty spectacle ark okular gwenview kate \
        kde-settings-plasma \
        xdg-desktop-portal-kde \
        qt5-qtwayland qt6-qtwayland \
        rtkit && \
    dnf clean all

# Install ScopeBuddy
RUN curl -Lo /usr/local/bin/scopebuddy https://raw.githubusercontent.com/HikariKnight/ScopeBuddy/refs/heads/main/bin/scopebuddy && \
    chmod +x /usr/local/bin/scopebuddy && \
    ln -s scopebuddy /usr/local/bin/scb

# Install Steam from negativo17
RUN dnf5 -y --setopt=install_weak_deps=False install steam && \
    dnf clean all

# Install gaming packages (including 32-bit libs for Proton compatibility)
RUN dnf install -y \
        gamescope \
        steam-devices kernel-modules-extra \
        mangohud.x86_64 mangohud.i686 \
        goverlay \
        lutris \
        protontricks winetricks \
        wine wine-mono \
        gamemode \
        sunshine \
        latencyflex-vulkan-layer \
        vulkan-tools vulkan-loader \
        libva-utils \
        vkBasalt.x86_64 vkBasalt.i686 \
        libFAudio.x86_64 libFAudio.i686 \
        lact \
        input-remapper \
        scx-scheds scx-tools \
        dbus-x11 xrandr evtest \
        libxcrypt-compat \
        xdg-user-dirs && \
    dnf clean all

# Install VR packages
RUN dnf install -y \
        openxr \
        wivrn && \
    dnf clean all

# renovate: datasource=github-releases depName=Supreeeme/xrizer
ARG XRIZER_VERSION=0.5

# Install xrizer (OpenVR driver for OpenXR)
RUN curl -Lo /tmp/xrizer.zip \
        https://github.com/Supreeeme/xrizer/releases/download/v${XRIZER_VERSION}/xrizer-v${XRIZER_VERSION}.zip && \
    unzip /tmp/xrizer.zip -d /tmp/xrizer-src && \
    mkdir -p /opt/xrizer && \
    mv /tmp/xrizer-src/xrizer-v${XRIZER_VERSION}/* /opt/xrizer/ && \
    rm -rf /tmp/xrizer.zip /tmp/xrizer-src

# Install audio/video essentials + multimedia codecs
RUN dnf install -y \
        pipewire wireplumber pipewire-alsa pipewire-pulseaudio \
        pipewire-module-filter-chain-sofa \
        alsa-ucm alsa-utils \
        ffmpeg \
        libfreeaptx \
        ladspa-caps-plugins \
        libaacs \
        libbdplus \
        libbluray \
        libbluray-utils && \
    dnf clean all

# Install firmware (mesa-vulkan-drivers already installed via Terra Mesa swap)
# GPU-specific firmware is installed in Containerfile.amd / Containerfile.nvidia
RUN dnf install -y \
        linux-firmware linux-firmware-whence \
        alsa-sof-firmware realtek-firmware && \
    dnf clean all

# Install hardware support
RUN dnf install -y \
        lm_sensors \
        ddcutil \
        i2c-tools \
        libinput-utils \
        v4l-utils \
        libcec \
        pulseaudio-utils && \
    dnf clean all

# Install system utilities
RUN dnf install -y \
        flatpak plasma-discover plasma-discover-flatpak plasma-discover-rpm-ostree \
        btop htop git make neovim \
        NetworkManager-wifi NetworkManager-bluetooth \
        bluez blueman fastfetch \
        glibc-langpack-en curl wget distrobox podman \
        firefox chromium \
        virt-manager \
        fzf ripgrep bat xdg-terminal-exec hostapd dnsmasq stow \
        duf lshw \
        powertop krfb \
        p7zip p7zip-plugins rar lzip \
        python3-icoextract && \
    dnf clean all

# renovate: datasource=github-releases depName=Heroic-Games-Launcher/HeroicGamesLauncher
ARG HEROIC_VERSION=2.22.0

# Install Heroic Games Launcher
RUN dnf install -y \
    https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/releases/download/v${HEROIC_VERSION}/Heroic-${HEROIC_VERSION}-linux-x86_64.rpm && \
    dnf clean all

# Install OpenCode
RUN dnf install -y \
    https://github.com/anomalyco/opencode/releases/latest/download/opencode-desktop-linux-$(uname -m).rpm && \
    dnf clean all

# Install umu-launcher from local RPM and remove unnecessary packages
RUN dnf install -y /tmp/*.rpm && \
    rm -f /tmp/*.rpm && \
    dnf remove -y plymouth ModemManager cups plasma-discover-packagekit && \
    dnf clean all

# Add NetBird repository
COPY rootfs/etc/yum.repos.d/netbird.repo /etc/yum.repos.d/netbird.repo

RUN dnf install -y --setopt=tsflags=noscripts netbird netbird-ui && \
    dnf clean all

# Set cap_sys_admin on Sunshine binary for KMS capture on Wayland
RUN setcap 'cap_sys_admin+p' $(readlink -f /usr/bin/sunshine)

# Install simracing hwdb entries (joystick detection fixes for sim racing peripherals)
RUN git clone --depth=1 https://github.com/JacKeTUs/simracing-hwdb /tmp/simracing-hwdb && \
    make -C /tmp/simracing-hwdb install && \
    systemd-hwdb update && \
    rm -rf /tmp/simracing-hwdb
