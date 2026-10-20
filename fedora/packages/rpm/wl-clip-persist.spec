%global ryoku_vendor cargo

Name:           wl-clip-persist
Version:        0.5.0
Release:        2%{?dist}
Summary:        Keep the Wayland clipboard after applications close
License:        MIT
URL:            https://github.com/Linus789/wl-clip-persist
Source0:        %{url}/archive/v%{version}.tar.gz#/%{name}-%{version}.tar.gz
Source100:      %{name}-%{version}-vendor.tar.gz
ExclusiveArch:  x86_64
%global debug_package %{nil}

BuildRequires:  cargo
BuildRequires:  gcc
BuildRequires:  rust

%description
wl-clip-persist keeps Wayland clipboard data available after the application
that supplied it exits.

%prep
%autosetup
tar -xf %{SOURCE100}
mkdir -p .cargo
cat > .cargo/config.toml <<'EOF'
[source.crates-io]
replace-with = "vendored-sources"

[source.vendored-sources]
directory = "vendor"
EOF

%build
cargo build --offline --locked --release --all-features

%install
install -Dpm0755 target/release/%{name} %{buildroot}%{_bindir}/%{name}

%files
%license LICENSE
%doc README.md
%{_bindir}/%{name}
