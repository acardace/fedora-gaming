# Build stage for umu-launcher
FROM quay.io/fedora/fedora:43 AS umu-builder

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

# Main image
FROM quay.io/fedora/fedora-bootc:43

LABEL quay.expires-after=12w

# Copy umu-launcher RPM from builder
COPY --from=umu-builder /root/rpmbuild/RPMS/*/*.rpm /tmp/

# Add third-party repositories
RUN dnf install -y 'dnf5-command(copr)' && \
    dnf config-manager addrepo --from-repofile=https://negativo17.org/repos/fedora-steam.repo && \
    dnf copr enable -y kylegospo/LatencyFleX && \
    dnf copr enable -y ilyaz/LACT && \
    dnf copr enable -y lizardbyte/beta && \
    dnf install -y \
        https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-43.noarch.rpm \
        https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-43.noarch.rpm

# Install KDE Plasma desktop
RUN dnf install -y \
        @kde-desktop-environment \
        sddm sddm-kcm \
        plasma-workspace plasma-desktop \
        dolphin kitty spectacle ark okular gwenview kate \
        kde-settings-plasma \
        xdg-desktop-portal-kde \
        qt5-qtwayland qt6-qtwayland

# Install ScopeBuddy
RUN curl -Lo /usr/local/bin/scopebuddy https://raw.githubusercontent.com/HikariKnight/ScopeBuddy/refs/heads/main/bin/scopebuddy && \
    chmod +x /usr/local/bin/scopebuddy && \
    ln -s scopebuddy /usr/local/bin/scb

# Install Steam from negativo17
RUN dnf5 -y --setopt=install_weak_deps=False install steam

# Install gaming packages
RUN dnf install -y \
        gamescope \
        mangohud goverlay \
        lutris \
        protontricks winetricks \
        wine wine-mono \
        gamemode \
        sunshine \
        latencyflex-vulkan-layer \
        vulkan-tools vulkan-loader \
        mesa-vulkan-drivers mesa-va-drivers mesa-vdpau-drivers \
        libva-utils vkBasalt \
        corectrl \
        lact \
        input-remapper

# Install audio/video essentials
RUN dnf install -y \
        pipewire wireplumber pipewire-alsa pipewire-pulseaudio \
        alsa-ucm alsa-utils \
        ffmpeg

# Install firmware and AMD drivers
RUN dnf install -y \
        linux-firmware linux-firmware-whence \
        alsa-sof-firmware realtek-firmware \
        amd-gpu-firmware \
        mesa-va-drivers mesa-vdpau-drivers mesa-vulkan-drivers

# Install system utilities
RUN dnf install -y \
        flatpak plasma-discover plasma-discover-flatpak \
        btop htop git make neovim fish \
        NetworkManager-wifi NetworkManager-bluetooth \
        bluez blueman fastfetch \
        glibc-langpack-en curl wget distrobox podman \
        firefox chromium \
        libvirt virt-manager

# renovate: datasource=github-releases depName=Heroic-Games-Launcher/HeroicGamesLauncher
ARG HEROIC_VERSION=2.18.1

# Install Heroic Games Launcher
RUN dnf install -y \
    https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/releases/download/v${HEROIC_VERSION}/Heroic-${HEROIC_VERSION}-linux-x86_64.rpm

# Install umu-launcher from local RPM
RUN dnf install -y /tmp/*.rpm && \
    rm -f /tmp/*.rpm

# Remove unnecessary packages for faster boot
RUN dnf remove -y plymouth ModemManager cups plasma-discover-packagekit && \
    dnf clean all

# Copy system configuration files
COPY rootfs/ /

# Copy scripts
COPY host-scripts/ /usr/local/bin/

# Configure timezone, sudoers, SELinux, and enable SDDM
RUN ln -sf ../usr/share/zoneinfo/Europe/Rome /etc/localtime && \
    echo '%wheel ALL=(ALL) ALL' > /etc/sudoers.d/wheel && \
    # Required for Steam Big Picture mode
    setsebool -P allow_execheap 1 && \
    systemctl enable sddm && \
    systemctl preset-all && \
    systemctl --global preset-all
