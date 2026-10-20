%global ryomanager_commit 459c6714e31276f73025369e722cf4ab48eccbc3
%global ryoku_vendor go
%global debug_package %{nil}

Name:           ryomanager
Version:        0.1.0.r27.g459c671
Release:        1%{?dist}
Summary:        System monitor and process manager for Ryoku
License:        GPL-3.0-only
URL:            https://github.com/Ryoku-dev/ryomanager
Source0:        %{url}/archive/%{ryomanager_commit}.tar.gz#/%{name}-%{ryomanager_commit}.tar.gz
Source1:        %{name}-%{version}-node_modules.tar.gz
Source2:        %{name}.desktop
Source100:      %{name}-%{version}-vendor.tar.gz
ExclusiveArch:  x86_64

BuildRequires:  desktop-file-utils
BuildRequires:  gcc
BuildRequires:  golang >= 1.25
BuildRequires:  gtk3-devel
BuildRequires:  pkgconf-pkg-config
BuildRequires:  nodejs24-npm
BuildRequires:  webkit2gtk4.1-devel
Requires:       desktop-file-utils
Requires:       gtk3
Requires:       hicolor-icon-theme
Requires:       webkit2gtk4.1

%description
RyoManager shows system performance and lets users inspect and manage running
processes.

%prep
%autosetup -n %{name}-%{ryomanager_commit}
tar -xzf %{SOURCE1} -C frontend
tar -xzf %{SOURCE100}

%build
npm --prefix frontend run build
CGO_ENABLED=1 \
  GOFLAGS='-mod=vendor -modcacherw -buildmode=pie' \
  go build -trimpath -tags 'desktop,production,webkit2_41' \
    -ldflags '-s -w' -o ryomanager .

%install
install -Dm0755 ryomanager %{buildroot}%{_bindir}/ryomanager
install -Dm0644 %{SOURCE2} \
    %{buildroot}%{_datadir}/applications/ryomanager.desktop
install -Dm0644 build/appicon.png \
    %{buildroot}%{_datadir}/icons/hicolor/64x64/apps/ryomanager.png

desktop-file-validate \
    %{buildroot}%{_datadir}/applications/ryomanager.desktop

%files
%license LICENSE
%doc README.md
%{_bindir}/ryomanager
%{_datadir}/applications/ryomanager.desktop
%{_datadir}/icons/hicolor/64x64/apps/ryomanager.png
