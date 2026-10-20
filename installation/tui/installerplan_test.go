package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	installerplan "ryoku-installerplan"
)

func TestTUIFrontendMatchesSharedEditionPlan(t *testing.T) {
	for _, edition := range []string{"arch", "void"} {
		t.Run(edition, func(t *testing.T) {
			var plan installerplan.EditionPlan
			if edition == "arch" {
				plan = installerplan.ResolveSource("Arch")
			} else {
				data, err := os.ReadFile(filepath.Join("..", "..", edition, "packages", "translations.tsv"))
				if err != nil {
					t.Fatal(err)
				}
				plan, err = installerplan.ResolveEdition(data)
				if err != nil {
					t.Fatal(err)
				}
			}
			for _, kind := range []string{installerplan.Browser, installerplan.LoginShell, installerplan.FileManager, installerplan.Compositor} {
				items := choiceItems(kind, plan, true)
				got := make([]string, 0, len(items))
				for _, item := range items {
					got = append(got, item.key)
				}
				if want := strings.Join(plan.AvailableIDs(kind), ","); strings.Join(got, ",") != want {
					t.Errorf("%s choices = %q, want %q", kind, strings.Join(got, ","), want)
				}
			}
			if installerplan.FreshDefault(installerplan.Browser) != "firefox" ||
				installerplan.FreshDefault(installerplan.LoginShell) != "fish" ||
				installerplan.FreshDefault(installerplan.FileManager) != "nautilus" {
				t.Fatal("fresh-install defaults changed")
			}
			wantDrops := "chromium,zen-browser-bin,zsh,zsh-autosuggestions,zsh-history-substring-search,zsh-syntax-highlighting,ryoku-oh-my-zsh,blesh"
			if got := strings.Join(installerplan.DropPackages("firefox", "fish"), ","); got != wantDrops {
				t.Fatalf("drops = %q, want %q", got, wantDrops)
			}
		})
	}
}

func TestUnavailableChoiceNoticeUsesEditionTableReason(t *testing.T) {
	for _, edition := range []string{"void"} {
		t.Run(edition, func(t *testing.T) {
			data, err := os.ReadFile(filepath.Join("..", "..", edition, "packages", "translations.tsv"))
			if err != nil {
				t.Fatal(err)
			}
			lines := strings.Split(string(data), "\n")
			reason := "Fixture " + edition + " Zen package is unavailable."
			for i, line := range lines {
				fields := strings.Split(line, "\t")
				if len(fields) == 4 && fields[0] == "zen-browser-bin" {
					fields[1] = "-"
					fields[3] = reason
					lines[i] = strings.Join(fields, "\t")
				}
			}
			plan, err := installerplan.ResolveEdition([]byte(strings.Join(lines, "\n")))
			if err != nil {
				t.Fatal(err)
			}
			items := choiceItems(installerplan.Browser, plan, true)
			var ids []string
			for _, item := range items {
				ids = append(ids, item.key)
			}
			// None installs nothing, so no edition table can withhold it.
			if got, want := strings.Join(ids, ","), "firefox,chromium,none"; got != want {
				t.Fatalf("browser choices = %q, want %q", got, want)
			}
			notices := unavailableChoiceNotices(plan, installerplan.Browser)
			if got, want := strings.Join(notices, "\n"), "Zen is unavailable: "+reason; got != want {
				t.Fatalf("browser notice = %q, want %q", got, want)
			}
		})
	}
}
