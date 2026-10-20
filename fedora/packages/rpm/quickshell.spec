Name:           quickshell
Version:        0.3.2
Release:        1%{?dist}
Summary:        Flexible toolkit for making desktop shells with Qt Quick
License:        LGPL-3.0-only
URL:            https://git.outfoxxed.me/quickshell/quickshell
Source0:        %{url}/archive/v%{version}.tar.gz#/quickshell-%{version}.tar.gz
%global debug_package %{nil}

BuildRequires:  cmake
BuildRequires:  gcc-c++
BuildRequires:  ninja-build
BuildRequires:  pkgconfig
BuildRequires:  cli11-devel
BuildRequires:  glib2-devel
BuildRequires:  jemalloc-devel
BuildRequires:  libdrm-devel
BuildRequires:  libglvnd-devel
BuildRequires:  libxcb-devel
BuildRequires:  mesa-libgbm-devel
BuildRequires:  pam-devel
BuildRequires:  pipewire-devel
BuildRequires:  polkit-devel
BuildRequires:  qt6-qtbase-devel
BuildRequires:  qt6-qtbase-private-devel
BuildRequires:  qt6-qtdeclarative-devel
BuildRequires:  qt6-qtshadertools-devel
BuildRequires:  qt6-qtwayland-devel
BuildRequires:  spirv-tools-devel
BuildRequires:  vulkan-headers
BuildRequires:  wayland-devel
BuildRequires:  wayland-protocols-devel
Requires:       hicolor-icon-theme
Requires:       qt6-qtsvg

%description
Quickshell is a Qt Quick toolkit for building desktop shells. Ryoku builds the
same release as Arch and retains RPM's generated Qt private-ABI requirements.

%prep
%autosetup -n quickshell

%build
%cmake \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DDISTRIBUTOR="Ryoku Fedora" \
    -DCRASH_HANDLER=OFF \
    -DINSTALL_QML_PREFIX=%{_lib}/qt6/qml
%cmake_build

%install
%cmake_install
ln -sfn quickshell %{buildroot}%{_bindir}/qs

%files
%license LICENSE
%{_bindir}/qs
%{_bindir}/quickshell
%{_datadir}/applications/org.quickshell.desktop
%{_datadir}/icons/hicolor/*/apps/org.quickshell.svg
%{_libdir}/qt6/qml/Quickshell/
