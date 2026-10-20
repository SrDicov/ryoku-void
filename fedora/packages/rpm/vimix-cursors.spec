%global upstream_version 2020-02-24

Name:           vimix-cursors
Version:        2020.02.24
Release:        1%{?dist}
Summary:        Material-inspired XCursor theme
License:        GPL-3.0-or-later
URL:            https://github.com/vinceliuice/Vimix-cursors
Source0:        %{url}/archive/%{upstream_version}.tar.gz#/Vimix-cursors-%{upstream_version}.tar.gz
BuildArch:      noarch

%description
Vimix provides dark and light Material-inspired cursor themes.

%prep
%autosetup -n Vimix-cursors-%{upstream_version}

%build

%install
install -d %{buildroot}%{_datadir}/icons/Vimix
cp -a dist/. %{buildroot}%{_datadir}/icons/Vimix/
install -d %{buildroot}%{_datadir}/icons/Vimix-white-cursors
cp -a dist-white/. %{buildroot}%{_datadir}/icons/Vimix-white-cursors/

%files
%license LICENSE
%{_datadir}/icons/Vimix/
%{_datadir}/icons/Vimix-white-cursors/
