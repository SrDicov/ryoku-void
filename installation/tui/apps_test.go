package main

import (
	"strings"
	"testing"
)

// The product steps choose one browser, login shell, and file manager, then
// collect the shared optional components. Locked rows refuse to toggle and all
// losing packages reach the backend through one drop list.

func TestProductStepsExistInOrder(t *testing.T) {
	f := stepsForVariant("plain")
	b := flowIndex(f, "browser")
	s := flowIndex(f, "login-shell")
	files := flowIndex(f, "file-manager")
	rashin := flowIndex(f, "rashin")
	cachyos := flowIndex(f, "cachyos")
	a := flowIndex(f, "apps")
	review := flowIndex(f, "review")
	if b < 0 || s < 0 || files < 0 || rashin < 0 || cachyos < 0 || a < 0 || review < 0 {
		t.Fatalf("product steps missing: browser=%d shell=%d files=%d rashin=%d cachyos=%d apps=%d review=%d",
			b, s, files, rashin, cachyos, a, review)
	}
	if !(b < s && s < files && files < rashin && rashin < cachyos && cachyos < a && a < review) {
		t.Fatalf("product steps out of order: browser=%d shell=%d files=%d rashin=%d cachyos=%d apps=%d review=%d",
			b, s, files, rashin, cachyos, a, review)
	}
	if f[b].kind != kSelect || f[s].kind != kSelect || f[files].kind != kSelect ||
		f[rashin].kind != kConfirm || f[cachyos].kind != kConfirm || f[a].kind != kApps {
		t.Fatal("product step kinds changed")
	}
	if !f[b].numbered || !f[s].numbered || !f[files].numbered {
		t.Fatal("browser, login-shell, and file-manager choices must be numbered")
	}
	m := newModel()
	if m.picks["browser"] != "firefox" || m.picks["login-shell"] != "fish" ||
		m.picks["file-manager"] != "nautilus" || m.picks["rashin"] != "1" || m.picks["cachyos"] != "0" {
		t.Fatalf("product defaults = %#v", m.picks)
	}
	void := stepsForVariant(variantVoid)
	if flowIndex(void, "cachyos") >= 0 || stepByKey(t, void, "rashin").kind != kConfirm {
		t.Fatal("Void must omit CachyOS and ask about Rashin")
	}
}

func TestBrowserListOrderAndRecommendation(t *testing.T) {
	bs := browsers()
	// None sits last on purpose: the three that install something are offered
	// first, and opting out is the deliberate step past them.
	want := []string{"firefox", "chromium", "zen", "none"}
	if len(bs) != len(want) {
		t.Fatalf("Ryoku ships %d browsers, got %d", len(want), len(bs))
	}
	for i, key := range want {
		if bs[i].key != key {
			t.Errorf("browser %d = %q, want %q", i, bs[i].key, key)
		}
	}
	if !strings.Contains(bs[0].hint, "Recommended") {
		t.Errorf("Firefox description does not mark it Recommended: %q", bs[0].hint)
	}
	if strings.Contains(bs[2].hint, "default") {
		t.Errorf("Zen description still claims to be the default: %q", bs[2].hint)
	}
}

func TestLoginShellListOrderAndAppOwnership(t *testing.T) {
	ss := loginShells()
	want := []string{"fish", "zsh", "bash"}
	if len(ss) != len(want) {
		t.Fatalf("Ryoku offers %d login shells, got %d", len(want), len(ss))
	}
	for i, key := range want {
		if ss[i].key != key {
			t.Errorf("login shell %d = %q, want %q", i, ss[i].key, key)
		}
	}
	if !strings.Contains(ss[0].hint, "Recommended") {
		t.Errorf("Fish description does not mark it Recommended: %q", ss[0].hint)
	}
	for _, r := range appRows() {
		if r.ID == "shell" || r.ID == "bash-edit" {
			t.Errorf("shell-owned app row %q remains in Apps & tools", r.ID)
		}
	}
}

func TestFileManagerListOrderAndRecommendation(t *testing.T) {
	managers := fileManagers()
	want := []string{"nautilus", "dolphin", "thunar"}
	if len(managers) != len(want) {
		t.Fatalf("file managers = %v, want %v", managers, want)
	}
	for i, id := range want {
		if managers[i].key != id {
			t.Errorf("file manager %d = %q, want %q", i, managers[i].key, id)
		}
	}
	if !strings.Contains(managers[0].hint, "Recommended") ||
		!strings.Contains(strings.ToLower(managers[0].hint), "stash") {
		t.Errorf("Nautilus recommendation = %q", managers[0].hint)
	}
}

func TestAppsUseSharedComponentCatalogue(t *testing.T) {
	rows := appRowsForVariant("plain")
	if len(rows) < 3 || rows[0].ID != "ryotunes" || rows[1].ID != "ryoport" || rows[2].ID != "ryomanager" {
		t.Fatalf("Ryoku apps are not first: %+v", rows)
	}
	for _, row := range rows {
		switch row.ID {
		case "files", "stash-menu", "rashin", "cachyos-layer":
			t.Errorf("step-owned component %q remains in Apps & tools", row.ID)
		}
	}
	for _, id := range []string{"terminal", "editor", "monitor"} {
		row, ok := appRowByID(id)
		if !ok || row.Req == "" {
			t.Errorf("required app %q = %+v, found %v", id, row, ok)
		}
	}
}

func TestRequiredRowsAreDefaultOn(t *testing.T) {
	for _, r := range appRows() {
		if r.Req != "" && !r.Def {
			t.Errorf("%s: required rows must ship on by default", r.ID)
		}
	}
}

func TestAppsToggleSkipsRequired(t *testing.T) {
	m := newModel()
	m.state, m.flow = "wizard", steps()
	m.idx = flowIndex(m.flow, "apps")
	m.loadStep()
	if m.keep == nil {
		t.Fatal("loadStep did not seed the keep map")
	}
	rows := m.appsRows()
	m.alsel = -1
	for i, r := range rows {
		if ar, _ := appRowByID(r.id); r.kind == "app" && ar.Req != "" {
			m.alsel = i
			break
		}
	}
	if m.alsel < 0 {
		t.Fatal("no required row in Apps & tools")
	}
	m.appsKey("space")
	if !m.keep[m.appsRows()[m.alsel].id] {
		t.Fatal("a required row toggled off")
	}
	if m.inputErr == "" {
		t.Error("refusing the toggle must explain itself")
	}
	// Walk to the first removable row; a clean toggle clears the notice.
	for i, r := range rows {
		if r.kind == "app" {
			if ar, _ := appRowByID(r.id); ar.Req == "" {
				m.alsel = i
				break
			}
		}
	}
	id := rows[m.alsel].id
	m.appsKey("space")
	if m.keep[id] {
		t.Fatalf("row %s did not toggle off", id)
	}
	if m.inputErr != "" {
		t.Errorf("clean toggle left an error: %q", m.inputErr)
	}
}

func TestDeselectDoesNotTouchRequiredPackages(t *testing.T) {
	keep := appDefaults()
	for _, r := range appRows() {
		keep[r.ID] = false // user tries to drop everything
	}
	d := installerChoicesForVariant("plain").DropComponentPackages(keep)
	set := map[string]bool{}
	for _, p := range d {
		set[p] = true
	}
	for _, r := range appRows() {
		if r.Req == "" {
			continue
		}
		for _, p := range r.Pkgs {
			if set[p] {
				t.Errorf("required package %s (%s) appears in the drop list", p, r.ID)
			}
		}
	}
}

func TestRashinIsAChoiceOnEveryEdition(t *testing.T) {
	for _, variant := range []string{"plain", variantCachyOS, variantVoid} {
		plan := installerChoicesForVariant(variant)
		rashin, ok := plan.Component("rashin")
		if !ok || !rashin.Available || rashin.Locked || !rashin.Component.DefaultOn {
			t.Fatalf("%s Rashin component = %+v, found %v", variant, rashin, ok)
		}
		selected := plan.DefaultComponents()
		selected["rashin"] = false
		if got := strings.Join(plan.DropComponentPackages(selected), ","); !strings.Contains(got, "ryoku-rashin") {
			t.Fatalf("%s: turning off Rashin did not drop ryoku-rashin: %q", variant, got)
		}
	}
}

func TestRashinAndCachyOSStepBehaviour(t *testing.T) {
	flow := stepsForVariant("plain")
	rashin := model{
		variant: "plain", flow: flow, idx: flowIndex(flow, "rashin"),
		state: "wizard", picks: map[string]string{"rashin": "1"},
	}
	rashin.loadStep()
	if !rashin.yes {
		t.Fatal("Rashin does not default to Yes")
	}
	next, _ := rashin.onKey("enter")
	rashin = next.(model)
	if rashin.picks["rashin"] != "1" || rashin.cur().key != "cachyos" {
		t.Fatalf("Rashin choice did not advance: pick=%q step=%q", rashin.picks["rashin"], rashin.cur().key)
	}

	rashin.netOnline = false
	rashin.loadStep()
	next, _ = rashin.onKey("y")
	cachyos := next.(model)
	if cachyos.yes {
		t.Fatal("offline CachyOS layer could be enabled")
	}
	next, _ = cachyos.onKey("enter")
	cachyos = next.(model)
	if cachyos.picks["cachyos"] != "0" || cachyos.cur().key != "apps" {
		t.Fatalf("offline CachyOS choice did not stay off and advance: pick=%q step=%q", cachyos.picks["cachyos"], cachyos.cur().key)
	}
}

func TestAppsResetRestoresDefaults(t *testing.T) {
	m := newModel()
	m.state, m.flow = "wizard", steps()
	m.idx = flowIndex(m.flow, "apps")
	m.loadStep()
	m.keep["yazi"] = false
	m.keep["docker"] = false
	m.appsKey("a")
	if !m.keep["yazi"] || !m.keep["docker"] {
		t.Fatal("'a' must restore the shipped defaults")
	}
	if got := appsSummary(m.keep); got != "all" {
		t.Errorf("appsSummary after reset = %q, want %q", got, "all")
	}
	m.keep["docker"] = false
	if got := appsSummary(m.keep); !strings.Contains(got, "docker") {
		t.Errorf("appsSummary after drop = %q, must name docker", got)
	}
}

// installEnv carries every shared choice and folds losing packages into one
// drop list. Desktop-only payloads use the separate hide list.
func TestInstallEnvCarriesProductChoicesAndDrops(t *testing.T) {
	envHas := func(env []string, want string) bool {
		for _, e := range env {
			if e == want {
				return true
			}
		}
		return false
	}
	envValue := func(env []string, key string) (string, bool) {
		prefix := key + "="
		for _, e := range env {
			if strings.HasPrefix(e, prefix) {
				return strings.TrimPrefix(e, prefix), true
			}
		}
		return "", false
	}
	asSet := func(csv string) map[string]bool {
		set := map[string]bool{}
		for _, value := range strings.Split(csv, ",") {
			if value != "" {
				set[value] = true
			}
		}
		return set
	}

	m := newModel()
	m.variant = "plain"
	m.diskDev, m.pwHash = "/dev/vda", "x"
	m.picks["disk"] = "whole"
	env := m.installEnv()
	for _, want := range []string{
		"RYOKU_BROWSER=firefox", "RYOKU_LOGIN_SHELL=fish",
		"RYOKU_FILE_MANAGER=nautilus", "RYOKU_RASHIN=1",
		"RYOKU_CACHYOS_LAYER=0",
	} {
		if !envHas(env, want) {
			t.Errorf("default environment missing %q: %v", want, env)
		}
	}
	if _, ok := envValue(env, "RYOKU_HIDE_APPS"); ok {
		t.Fatal("default app selection emitted a hide list")
	}
	drops, ok := envValue(env, "RYOKU_DROP_PACKAGES")
	if !ok {
		t.Fatal("default environment has no drop list")
	}
	defaultSet := asSet(drops)
	for _, want := range []string{
		"chromium", "zen-browser-bin", "zsh", "blesh", "dolphin", "thunar",
	} {
		if !defaultSet[want] {
			t.Errorf("default drop list %q missing %s", drops, want)
		}
	}
	for _, absent := range []string{
		"firefox", "fish", "nautilus", "nautilus-python", "ryoku-rashin",
		"linux-cachyos", "cachyos-settings", "proton-cachyos-native",
	} {
		if defaultSet[absent] {
			t.Errorf("default drop list %q contains package %s", drops, absent)
		}
	}

	for _, tc := range []struct {
		shell string
		drop  []string
		keep  []string
	}{
		{"fish", []string{"zsh", "zsh-autosuggestions", "zsh-history-substring-search", "zsh-syntax-highlighting", "ryoku-oh-my-zsh", "blesh"}, []string{"fish"}},
		{"zsh", []string{"fish", "blesh"}, []string{"zsh", "zsh-autosuggestions", "zsh-history-substring-search", "zsh-syntax-highlighting", "ryoku-oh-my-zsh"}},
		{"bash", []string{"fish", "zsh", "zsh-autosuggestions", "zsh-history-substring-search", "zsh-syntax-highlighting", "ryoku-oh-my-zsh"}, []string{"blesh"}},
	} {
		m.picks["login-shell"] = tc.shell
		env = m.installEnv()
		if !envHas(env, "RYOKU_LOGIN_SHELL="+tc.shell) {
			t.Errorf("%s: chosen shell did not reach env", tc.shell)
		}
		csv, exists := envValue(env, "RYOKU_DROP_PACKAGES")
		if !exists {
			t.Fatalf("%s: no drop list", tc.shell)
		}
		set := asSet(csv)
		for _, pkg := range tc.drop {
			if !set[pkg] {
				t.Errorf("%s: drop list %q missing %s", tc.shell, csv, pkg)
			}
		}
		for _, pkg := range tc.keep {
			if set[pkg] {
				t.Errorf("%s: selected stack package %s appears in %q", tc.shell, pkg, csv)
			}
		}
		if set["bash"] {
			t.Errorf("%s: bash itself must never be dropped", tc.shell)
		}
	}

	m.picks["browser"] = "chromium"
	m.picks["login-shell"] = "zsh"
	m.picks["file-manager"] = "dolphin"
	m.picks["rashin"] = "0"
	m.keep = appDefaults()
	m.keep["docker"] = false
	m.keep["flatpak"] = false
	m.keep["ryoport"] = false
	env = m.installEnv()
	if !envHas(env, "RYOKU_BROWSER=chromium") {
		t.Error("the chosen browser did not reach the env")
	}
	csv, ok := envValue(env, "RYOKU_DROP_PACKAGES")
	if !ok {
		t.Fatal("deselections must emit a drop list")
	}
	set := asSet(csv)
	for _, want := range []string{"docker", "flatpak", "firefox", "zen-browser-bin", "fish", "blesh", "nautilus", "nautilus-python", "ryoku-rashin"} {
		if !set[want] {
			t.Errorf("drop list %q missing %s", csv, want)
		}
	}
	for _, keep := range []string{"chromium", "zsh", "zsh-autosuggestions", "zsh-history-substring-search", "zsh-syntax-highlighting", "ryoku-oh-my-zsh"} {
		if set[keep] {
			t.Errorf("chosen product package %s appears in %q", keep, csv)
		}
	}
	if !envHas(env, "RYOKU_FILE_MANAGER=dolphin") || !envHas(env, "RYOKU_RASHIN=0") {
		t.Errorf("updated file-manager/Rashin choices missing from %v", env)
	}
	if hidden, ok := envValue(env, "RYOKU_HIDE_APPS"); !ok || hidden != "ryovm.desktop" {
		t.Errorf("hidden apps = %q (ok=%v), want ryovm.desktop", hidden, ok)
	}
}

func TestEditionOnlyEnvironmentVariables(t *testing.T) {
	has := func(env []string, want string) bool {
		for _, value := range env {
			if value == want {
				return true
			}
		}
		return false
	}
	hasPrefix := func(env []string, prefix string) bool {
		for _, value := range env {
			if strings.HasPrefix(value, prefix) {
				return true
			}
		}
		return false
	}
	for _, variant := range []string{variantCachyOS, variantVoid} {
		m := model{variant: variant, picks: map[string]string{"disk": "whole", "rashin": "0"}}
		env := m.installEnv()
		if hasPrefix(env, "RYOKU_CACHYOS_LAYER=") {
			t.Errorf("%s emitted plain-Arch CachyOS layer variable: %v", variant, env)
		}
		if !has(env, "RYOKU_RASHIN=0") {
			t.Errorf("%s did not pass the Rashin choice through: %v", variant, env)
		}
	}
}

func TestReviewNamesProductChoices(t *testing.T) {
	m := reviewModel()
	m.variant = "plain"
	m.picks["browser"] = "chromium"
	m.picks["login-shell"] = "zsh"
	m.picks["file-manager"] = "dolphin"
	m.picks["rashin"] = "1"
	m.picks["cachyos"] = "0"
	m.keep = appDefaultsForVariant("plain")
	m.keep["ryoport"] = false
	body := stripSGR(m.reviewBody(100))
	for _, want := range []string{
		"browser", "Chromium", "shell", "Zsh", "files", "Dolphin",
		"Rashin", "minus ryoport", "CachyOS", "No",
	} {
		if !strings.Contains(body, want) {
			t.Errorf("Review does not show %q:\n%s", want, body)
		}
	}
}

// The apps step must Tab forward with the summary recorded, and the whole
// checklist must render without error on a tiny grid (the VT invariant).
func TestAppsStepAdvancesAndRendersSmall(t *testing.T) {
	for _, sz := range gridSizes {
		m := wizardAt("apps", sz[0], sz[1])
		gw, gh := frameBox(m.fittedFrame())
		if gw > sz[0] || gh > sz[1] {
			t.Errorf("apps step at %dx%d rendered %dx%d", sz[0], sz[1], gw, gh)
		}
	}
	m := wizardAt("apps", 112, 42)
	before := m.idx
	m.appsKey("tab")
	if m.idx <= before {
		t.Fatal("tab did not advance from the apps step")
	}
	if m.picks["apps"] == "" {
		t.Error("tab did not record the apps summary pick")
	}
}
