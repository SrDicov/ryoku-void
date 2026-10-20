Name:           ttf-fraunces-variable
Version:        1.000
Release:        1%{?dist}
Summary:        Fraunces variable display typeface
License:        OFL-1.1
URL:            https://github.com/undercasetype/Fraunces
Source0:        %{url}/releases/download/%{version}/UnderCaseType_Fraunces_%{version}.zip
Source1:        %{url}/raw/%{version}/OFL.txt#/fraunces-OFL.txt
BuildRequires:  unzip
BuildArch:      noarch
Requires:       fonts-filesystem

%description
Roman and italic variable TrueType fonts from the Fraunces family.

%prep
%setup -q -c -T
unzip -q %{SOURCE0}

%install
install -Dm644 'UnderCaseType_Fraunces_%{version}/Fonts - Desktop/Fraunces[SOFT,WONK,opsz,wght].ttf' %{buildroot}%{_datadir}/fonts/fraunces/Fraunces-Variable.ttf
install -Dm644 'UnderCaseType_Fraunces_%{version}/Fonts - Desktop/Fraunces-Italic[SOFT,WONK,opsz,wght].ttf' %{buildroot}%{_datadir}/fonts/fraunces/Fraunces-Italic-Variable.ttf
install -Dm644 %{SOURCE1} %{buildroot}%{_licensedir}/%{name}/OFL.txt

%files
%license %{_licensedir}/%{name}/OFL.txt
%{_datadir}/fonts/fraunces/
