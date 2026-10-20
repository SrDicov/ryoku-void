Name:           ttf-hack-nerd
Version:        3.5.1
Release:        1%{?dist}
Summary:        Hack Nerd Font monospace face
License:        MIT AND Bitstream-Vera
URL:            https://github.com/ryanoasis/nerd-fonts
Source0:        %{url}/releases/download/v%{version}/Hack.tar.xz
BuildArch:      noarch
BuildRequires:  tar
BuildRequires:  xz
Requires:       fonts-filesystem

%description
Hack patched with the Nerd Fonts glyph set for terminals and code editors.

%prep
%setup -q -c -n %{name}-%{version}

%build

%install
install -d %{buildroot}%{_datadir}/fonts/%{name}
install -m 0644 *.ttf %{buildroot}%{_datadir}/fonts/%{name}/

%files
%license LICENSE.md
%{_datadir}/fonts/%{name}/
