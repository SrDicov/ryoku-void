Name:           ttf-firacode-nerd
Version:        3.5.1
Release:        1%{?dist}
Summary:        Fira Code Nerd Font monospace face
License:        OFL-1.1
URL:            https://github.com/ryanoasis/nerd-fonts
Source0:        %{url}/releases/download/v%{version}/FiraCode.tar.xz
BuildArch:      noarch
BuildRequires:  tar
BuildRequires:  xz
Requires:       fonts-filesystem

%description
Fira Code patched with the Nerd Fonts glyph set for terminals and code editors.

%prep
%setup -q -c -n %{name}-%{version}

%build

%install
install -d %{buildroot}%{_datadir}/fonts/%{name}
install -m 0644 *.ttf %{buildroot}%{_datadir}/fonts/%{name}/

%files
%license LICENSE
%{_datadir}/fonts/%{name}/
