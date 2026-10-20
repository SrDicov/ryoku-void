Name:           apple_cursor
Version:        2.0.1
Release:        1%{?dist}
Summary:        Open source macOS cursor themes
License:        GPL-3.0-only
URL:            https://github.com/ful1e5/apple_cursor
Source0:        %{url}/releases/download/v%{version}/macOS.tar.xz
Source1:        %{url}/raw/v%{version}/LICENSE#/apple-cursor-LICENSE
BuildArch:      noarch

%description
Dark and light macOS-style XCursor themes.

%prep
%setup -q -c -T
%{__tar} -xf %{SOURCE0}

%install
install -d %{buildroot}%{_datadir}/icons
cp -a macOS macOS-White %{buildroot}%{_datadir}/icons/
install -Dm644 %{SOURCE1} %{buildroot}%{_licensedir}/%{name}/LICENSE

%files
%license %{_licensedir}/%{name}/LICENSE
%{_datadir}/icons/macOS/
%{_datadir}/icons/macOS-White/
