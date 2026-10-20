Name:           phinger-cursors
Version:        2.2
Release:        1%{?dist}
Summary:        Phinger XCursor themes
License:        CC-BY-SA-4.0
URL:            https://github.com/phisch/phinger-cursors
Source0:        %{url}/releases/download/v%{version}/phinger-cursors-variants.tar.bz2
Source1:        %{url}/raw/v%{version}/LICENSE#/phinger-cursors-LICENSE
BuildArch:      noarch

%description
Light and dark variants of the Phinger XCursor theme.

%prep
%setup -q -c -T
%{__tar} -xf %{SOURCE0}

%install
install -d %{buildroot}%{_datadir}/icons
for directory in phinger-*; do
    test -d "$directory" || continue
    cp -a "$directory" %{buildroot}%{_datadir}/icons/
done
install -Dm644 %{SOURCE1} %{buildroot}%{_licensedir}/%{name}/LICENSE

%files
%license %{_licensedir}/%{name}/LICENSE
%{_datadir}/icons/phinger-*/
