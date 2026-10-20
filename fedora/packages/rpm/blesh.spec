%global upstream_version 0.4.0-devel3

Name:           blesh
Version:        0.4.0_devel3
Release:        1%{?dist}
Summary:        Bash Line Editor with highlighting and autosuggestions
License:        BSD-3-Clause
URL:            https://github.com/akinomyoga/ble.sh
Source0:        %{url}/releases/download/v%{upstream_version}/ble-%{upstream_version}-2.tar.xz
BuildArch:      noarch
BuildRequires:  tar
BuildRequires:  xz
Requires:       bash

%description
Blesh adds syntax highlighting, autosuggestions, and advanced line editing to
interactive Bash sessions.

%prep
%autosetup -n ble-%{upstream_version}

%build

%install
install -d %{buildroot}%{_datadir}/blesh
cp -a . %{buildroot}%{_datadir}/blesh/

%files
%license doc/LICENSE.md
%{_datadir}/blesh/
