Name:           ttf-maple-mono-nf
Version:        7.9
Release:        1%{?dist}
Summary:        Maple Mono Nerd Font monospace face
License:        OFL-1.1
URL:            https://github.com/subframe7536/maple-font
Source0:        %{url}/releases/download/v%{version}/MapleMono-NF.zip
BuildArch:      noarch
BuildRequires:  unzip
Requires:       fonts-filesystem

%description
Maple Mono patched with the Nerd Fonts glyph set for terminals and code editors.

%prep
%setup -q -c -n %{name}-%{version}

%build

%install
install -d %{buildroot}%{_datadir}/fonts/%{name}
install -m 0644 *.ttf %{buildroot}%{_datadir}/fonts/%{name}/

%files
%license LICENSE.txt
%{_datadir}/fonts/%{name}/
