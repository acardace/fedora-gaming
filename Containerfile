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

# Full gaming image based on minimal
FROM ghcr.io/acardace/fedora-gaming:minimal

LABEL quay.expires-after=12w

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
    dnf config-manager addrepo --from-repofile=https://negativo17.org/repos/fedora-rar.repo && \
    dnf install -y --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
        terra-release terra-release-extras terra-release-mesa && \
    dnf copr enable -y ublue-os/bazzite && \
    dnf copr enable -y ublue-os/bazzite-multilib && \
    dnf copr enable -y kylegospo/LatencyFleX && \
    dnf copr enable -y ilyaz/LACT && \
    dnf copr enable -y lizardbyte/beta && \
    dnf copr enable -y bieszczaders/kernel-cachyos-addons && \
    dnf install -y \
        https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
        https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm && \
    sed -i 's@enabled=0@enabled=1@g' /etc/yum.repos.d/negativo17-fedora-multimedia.repo && \
    dnf config-manager setopt "terra-mesa".enabled=false && \
    dnf config-manager setopt "*negativo17*".priority=4 "*negativo17*".exclude="mesa-*" && \
    dnf config-manager setopt "*rpmfusion*".priority=5 "*rpmfusion*".exclude="mesa-*" && \
    dnf config-manager setopt "*fedora*".exclude="mesa-*"

# Swap Mesa for Terra Mesa (Valve-patched, 26.x)
# Swap pipewire, bluez, wireplumber, Xwayland for Bazzite-patched versions
RUN dnf -y remove mesa-va-drivers && \
    dnf -y swap --repo=terra-mesa mesa-filesystem mesa-filesystem && \
    dnf -y swap --repo=copr:copr.fedorainfracloud.org:ublue-os:bazzite wireplumber wireplumber && \
    dnf -y swap --repo=copr:copr.fedorainfracloud.org:ublue-os:bazzite-multilib \
        pipewire pipewire && \
    dnf -y swap --repo=copr:copr.fedorainfracloud.org:ublue-os:bazzite-multilib \
        bluez bluez && \
    dnf -y swap --repo=copr:copr.fedorainfracloud.org:ublue-os:bazzite-multilib \
        xorg-x11-server-Xwayland xorg-x11-server-Xwayland && \
    dnf5 versionlock add \
        mesa-dri-drivers \
        mesa-filesystem \
        mesa-libEGL \
        mesa-libGL \
        mesa-libgbm \
        mesa-vulkan-drivers \
        mesa-va-drivers \
        pipewire \
        pipewire-alsa \
        pipewire-gstreamer \
        pipewire-jack-audio-connection-kit \
        pipewire-jack-audio-connection-kit-libs \
        pipewire-libs \
        pipewire-plugin-libcamera \
        pipewire-pulseaudio \
        pipewire-utils \
        wireplumber \
        wireplumber-libs \
        bluez \
        bluez-libs \
        bluez-obexd \
        xorg-x11-server-Xwayland

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

# Install gaming packages (including 32-bit libs for Proton compatibility)
RUN dnf install -y \
        gamescope gamescope-libs.x86_64 gamescope-libs.i686 gamescope-shaders \
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
        libobs_vkcapture.x86_64 libobs_vkcapture.i686 \
        libobs_glcapture.x86_64 libobs_glcapture.i686 \
        corectrl \
        lact \
        input-remapper \
        scx-scheds scx-tools \
        dbus-x11 xrandr evtest \
        libxcrypt-compat \
        xdg-user-dirs

# Install VR packages
RUN dnf install -y \
        openxr \
        wivrn

# Install audio/video essentials + multimedia codecs
RUN dnf install -y \
        pipewire wireplumber pipewire-alsa pipewire-pulseaudio \
        pipewire-module-filter-chain-sofa \
        alsa-ucm alsa-utils \
        ffmpeg \
        libfreeaptx \
        ladspa-caps-plugins \
        ladspa-noise-suppression-for-voice && \
    dnf install -y --enable-repo="*rpmfusion*" --disable-repo="*negativo17*" \
        libaacs \
        libbdplus \
        libbluray \
        libbluray-utils

# Install firmware and AMD drivers (Mesa from Terra, VA-API from Terra Mesa)
RUN dnf install -y --enable-repo=terra-mesa \
        linux-firmware linux-firmware-whence \
        alsa-sof-firmware realtek-firmware \
        amd-gpu-firmware \
        mesa-va-drivers mesa-vdpau-drivers-freeworld mesa-vulkan-drivers

# Install hardware support
RUN dnf install -y \
        lm_sensors \
        ddcutil \
        i2c-tools \
        libinput-utils \
        v4l-utils \
        libcec \
        pulseaudio-utils

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
        p7zip p7zip-plugins rar lzip \
        python3-icoextract

# renovate: datasource=github-releases depName=Heroic-Games-Launcher/HeroicGamesLauncher
ARG HEROIC_VERSION=2.19.1

# Install Heroic Games Launcher
RUN dnf install -y \
    https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/releases/download/v${HEROIC_VERSION}/Heroic-${HEROIC_VERSION}-linux-x86_64.rpm

# Install OpenCode
RUN dnf install -y \
    https://github.com/anomalyco/opencode/releases/latest/download/opencode-desktop-linux-$(uname -m).rpm

# Install umu-launcher from local RPM
RUN dnf install -y /tmp/*.rpm && \
    rm -f /tmp/*.rpm

# Remove unnecessary packages for faster boot
RUN dnf remove -y plymouth ModemManager cups plasma-discover-packagekit && \
    dnf clean all

# Set cap_sys_admin on Sunshine binary for KMS capture on Wayland
RUN setcap 'cap_sys_admin+p' $(readlink -f /usr/bin/sunshine)

# Enable systemd services
RUN systemctl enable sddm && \
    systemctl preset-all && \
    systemctl --global preset-all
