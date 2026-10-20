Name:           catppuccin-cursors-mocha
Version:        2.0.0
Release:        1%{?dist}
Summary:        Catppuccin Mocha cursor themes
License:        GPL-2.0-only
URL:            https://github.com/catppuccin/cursors
Source0:        %{url}/releases/download/v%{version}/catppuccin-mocha-blue-cursors.zip
Source1:        %{url}/releases/download/v%{version}/catppuccin-mocha-dark-cursors.zip
Source2:        %{url}/releases/download/v%{version}/catppuccin-mocha-flamingo-cursors.zip
Source3:        %{url}/releases/download/v%{version}/catppuccin-mocha-green-cursors.zip
Source4:        %{url}/releases/download/v%{version}/catppuccin-mocha-lavender-cursors.zip
Source5:        %{url}/releases/download/v%{version}/catppuccin-mocha-light-cursors.zip
Source6:        %{url}/releases/download/v%{version}/catppuccin-mocha-maroon-cursors.zip
Source7:        %{url}/releases/download/v%{version}/catppuccin-mocha-mauve-cursors.zip
Source8:        %{url}/releases/download/v%{version}/catppuccin-mocha-peach-cursors.zip
Source9:        %{url}/releases/download/v%{version}/catppuccin-mocha-pink-cursors.zip
Source10:       %{url}/releases/download/v%{version}/catppuccin-mocha-red-cursors.zip
Source11:       %{url}/releases/download/v%{version}/catppuccin-mocha-rosewater-cursors.zip
Source12:       %{url}/releases/download/v%{version}/catppuccin-mocha-sapphire-cursors.zip
Source13:       %{url}/releases/download/v%{version}/catppuccin-mocha-sky-cursors.zip
Source14:       %{url}/releases/download/v%{version}/catppuccin-mocha-teal-cursors.zip
Source15:       %{url}/releases/download/v%{version}/catppuccin-mocha-yellow-cursors.zip
BuildRequires:  unzip
BuildArch:      noarch

%description
All accent variants of the Catppuccin Mocha XCursor theme.

%prep
%setup -q -c -T
for source in %{SOURCE0} %{SOURCE1} %{SOURCE2} %{SOURCE3} %{SOURCE4} %{SOURCE5} %{SOURCE6} %{SOURCE7} %{SOURCE8} %{SOURCE9} %{SOURCE10} %{SOURCE11} %{SOURCE12} %{SOURCE13} %{SOURCE14} %{SOURCE15}; do
    unzip -q "$source"
done

%install
install -d %{buildroot}%{_datadir}/icons
cp -a catppuccin-mocha-*-cursors %{buildroot}%{_datadir}/icons/

%files
%license catppuccin-mocha-blue-cursors/LICENSE
%{_datadir}/icons/catppuccin-mocha-*-cursors/
