%undefine source_date_epoch_from_changelog

# renovate: datasource=github-releases depName=Open-Wine-Components/umu-launcher
%global tag 1.3.0

%global build_timestamp %(date +"%Y%m%d")

%global rel_build 1.%{build_timestamp}%{?dist}

# renovate: datasource=github-releases depName=urllib3/urllib3
%global urllib3 2.3.0

Name:           umu-launcher
Version:        %{tag}
Release:        %{rel_build}
Summary:        A tool for launching non-steam games with proton

License:        GPLv3
URL:            https://github.com/Open-Wine-Components/umu-launcher
Source0:        %{url}/archive/refs/tags/%{tag}.tar.gz#/%{name}-%{tag}.tar.gz
Source1:        https://github.com/urllib3/urllib3/releases/download/%{urllib3}/urllib3-%{urllib3}.tar.gz

BuildRequires:  meson >= 0.54.0
BuildRequires:  ninja-build
BuildRequires:  cmake
BuildRequires:  g++
BuildRequires:  gcc-c++
BuildRequires:  scdoc
BuildRequires:  git
BuildRequires:  python3-devel
BuildRequires:  python3-build
BuildRequires:  python3-installer
BuildRequires:  python3-hatchling
BuildRequires:  python
BuildRequires:  python3
BuildRequires:  python3-pip
BuildRequires:  libzstd-devel
BuildRequires:  python3-hatch-vcs
BuildRequires:  python3-wheel
BuildRequires:  python3-xlib
BuildRequires:  python3-pyzstd
BuildRequires:  cargo

Requires:       python
Requires:       python3
Requires:       python3-xlib
Requires:       python3-filelock
Requires:       python3-pyzstd

Recommends:     python3-cbor2
Recommends:     python3-xxhash
Recommends:     libzstd

# We need this for now to allow umu's builtin urllib3 version to be used.
AutoReqProv: no


%description
%{name} A tool for launching non-steam games with proton

%prep
%autosetup -p 1
if ! find subprojects/urllib3/ -mindepth 1 -maxdepth 1 | read; then
    # Directory is empty, perform action
    mv %{SOURCE1} .
    tar -xf urllib3-%{urllib3}.tar.gz
    rm *.tar.gz
    mv urllib3-%{urllib3}/* subprojects/urllib3/
fi
# Relax hatch-vcs version requirement (F43 ships 0.5.0, urllib3 wants 0.4.0)
sed -i 's/"hatch-vcs==0.4.0"/"hatch-vcs"/' subprojects/urllib3/pyproject.toml

%build
export PYO3_USE_ABI3_FORWARD_COMPATIBILITY=1
./configure.sh --prefix=/usr --use-system-pyzstd
make

%install
make DESTDIR=%{buildroot} PYTHONDIR=%{python3_sitelib} install

%files
%{_bindir}/umu-run
%{_datadir}/man/*
%{python3_sitelib}/umu*

%changelog