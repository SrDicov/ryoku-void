Name:           localsend-bin
Version:        1.18.2
Release:        1%{?dist}
Summary:        Cross-platform local network file sharing
License:        Apache-2.0
URL:            https://github.com/localsend/localsend
Source0:        %{url}/releases/download/v%{version}/LocalSend-%{version}-linux-x86-64.deb
Source1:        %{url}/raw/v%{version}/LICENSE#/localsend-LICENSE
# The Flutter plugins keep upstream's CI build path as RUNPATH; the loader
# skips it because it never exists on a user's machine.
%global __brp_check_rpaths %{nil}
BuildRequires:  bsdtar
Requires:       fuse-libs
Requires:       xdg-user-dirs
Requires:       libayatana-appindicator-gtk3
Requires:       libayatana-indicator-gtk3
Provides:       localsend = %{version}
Conflicts:      localsend
ExclusiveArch:  x86_64
AutoReqProv:    no
%global debug_package %{nil}

%description
LocalSend shares files and messages over the local network without an account.

%prep
%setup -q -c -T
bsdtar -xf %{SOURCE0} data.tar.zst
%{__tar} -xf data.tar.zst

%install
mkdir -p %{buildroot}/opt %{buildroot}%{_bindir} %{buildroot}%{_datadir}
cp -a opt/localsend_app %{buildroot}/opt/
cp -a usr/share/applications usr/share/icons %{buildroot}%{_datadir}/
ln -s /opt/localsend_app/localsend_app %{buildroot}%{_bindir}/localsend_app
install -Dm644 %{SOURCE1} %{buildroot}%{_licensedir}/%{name}/LICENSE

%files
%license %{_licensedir}/%{name}/LICENSE
/opt/localsend_app/
%{_bindir}/localsend_app
%{_datadir}/applications/localsend_app.desktop
%{_datadir}/icons/hicolor/*/apps/localsend_app.png
