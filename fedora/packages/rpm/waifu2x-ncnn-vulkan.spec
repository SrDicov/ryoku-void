Name:           waifu2x-ncnn-vulkan
Version:        20250915
Release:        1%{?dist}
Summary:        NCNN implementation of the waifu2x image converter
License:        MIT
URL:            https://github.com/nihui/waifu2x-ncnn-vulkan
Source0:        %{url}/releases/download/%{version}/%{name}-%{version}-linux.zip
Source1:        %{name}-wrapper
ExclusiveArch:  x86_64
%global debug_package %{nil}

BuildRequires:  unzip
Requires:       vulkan-loader
Conflicts:      waifu2x-ncnn-vulkan-git

%description
waifu2x-ncnn-vulkan uses Vulkan compute to denoise and enlarge images. This
package carries the upstream Linux build and its trained models.

%prep
%autosetup -n %{name}-%{version}-linux

%build

%install
install -Dpm0755 %{name} %{buildroot}%{_libexecdir}/%{name}.real
install -Dpm0755 %{SOURCE1} %{buildroot}%{_bindir}/%{name}
install -d %{buildroot}%{_datadir}/%{name}
cp -a models-* %{buildroot}%{_datadir}/%{name}/

%files
%license LICENSE
%doc README.md
%{_bindir}/%{name}
%{_libexecdir}/%{name}.real
%{_datadir}/%{name}/
