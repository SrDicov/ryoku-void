Name:           dualsensectl
Version:        0.7
Release:        2%{?dist}
Summary:        Control Sony DualSense controller features
License:        GPL-2.0-only
URL:            https://github.com/nowrep/dualsensectl
Source0:        %{url}/archive/v%{version}.tar.gz#/%{name}-%{version}.tar.gz
ExclusiveArch:  x86_64

BuildRequires:  gcc
BuildRequires:  meson
BuildRequires:  pkgconfig(dbus-1)
BuildRequires:  pkgconfig(hidapi-hidraw)
BuildRequires:  pkgconfig(libudev)
Requires:       dbus-libs
Requires:       hidapi
Requires:       libusb1

%description
dualsensectl controls player LEDs, the lightbar, battery reporting, microphone
routing, speaker routing, and adaptive triggers on Sony DualSense controllers.

%prep
%autosetup

%build
%meson
%meson_build

%install
%meson_install

%files
%license LICENSE
%doc README.md
%{_bindir}/dualsensectl
