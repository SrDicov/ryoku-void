Name:           zsh-history-substring-search
Version:        1.1.0
Release:        2%{?dist}
Summary:        Zsh port of the Fish history substring search
License:        BSD-3-Clause
URL:            https://github.com/zsh-users/zsh-history-substring-search
Source0:        %{url}/archive/v%{version}/%{name}-v%{version}.tar.gz
BuildArch:      noarch
Requires:       zsh

%description
This Zsh plugin searches command history for the text already entered at the
prompt when the configured history keys are pressed.

%prep
%autosetup
sed -e 's/^# //g; s/^#//g' -ne 4,38p %{name}.zsh > LICENSE

%build

%install
install -Dpm 0644 %{name}.zsh \
  %{buildroot}%{_datadir}/zsh/plugins/%{name}/%{name}.zsh
install -Dpm 0644 README.md \
  %{buildroot}%{_docdir}/%{name}/README.md
install -Dpm 0644 LICENSE \
  %{buildroot}%{_licensedir}/%{name}/LICENSE

%files
%license %{_licensedir}/%{name}/LICENSE
%doc %{_docdir}/%{name}/README.md
%{_datadir}/zsh/plugins/%{name}/%{name}.zsh
