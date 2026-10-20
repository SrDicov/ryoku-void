package installerplan

import (
	_ "embed"
	"errors"
	"fmt"
	"path/filepath"
	"strings"
	"sync"
)

const (
	Browser     = "browser"
	LoginShell  = "login-shell"
	FileManager = "file-manager"
	Compositor  = "compositor"
)

var choiceKinds = []string{Browser, LoginShell, FileManager, Compositor}

//go:embed choices.tsv
var manifestData []byte

type Choice struct {
	Kind               string
	ID                 string
	Label              string
	Packages           []string
	Executable         string
	ShowUnavailableISO bool
	TUIHint            string
	ShellDetail        string
	Experimental       bool
	// Installs nothing: the "none" flag marks a choice that is a deliberate
	// opt-out rather than a row whose package column was left blank by mistake.
	// Only a browser carries one today; a compositor or a login shell is not
	// something a Ryoku box can go without.
	NoPackages bool
}

type Availability struct {
	Choice    Choice
	Available bool
	Reason    string
}

type EditionPlan struct {
	Edition    string
	choices    map[string][]Availability
	components []ComponentAvailability
}

type definition struct {
	choices  map[string][]Choice
	policies map[string]string
}

var (
	definitionOnce sync.Once
	sharedDef      definition
	definitionErr  error
)

func loadDefinition() (definition, error) {
	definitionOnce.Do(func() {
		sharedDef, definitionErr = parseManifest(manifestData)
	})
	return sharedDef, definitionErr
}

func parseManifest(data []byte) (definition, error) {
	def := definition{
		choices:  map[string][]Choice{},
		policies: map[string]string{},
	}
	seenHeader := false
	for lineNo, line := range strings.Split(string(data), "\n") {
		if strings.TrimSpace(line) == "" || strings.HasPrefix(strings.TrimSpace(line), "#") {
			continue
		}
		fields := strings.Split(line, "\t")
		if !seenHeader {
			seenHeader = true
			if len(fields) != 12 || fields[0] != "record" || fields[1] != "kind" || fields[2] != "id" {
				return definition{}, fmt.Errorf("installer choices line %d has an invalid header", lineNo+1)
			}
			continue
		}
		if len(fields) != 12 {
			return definition{}, fmt.Errorf("installer choices line %d must have twelve tab-separated columns", lineNo+1)
		}
		switch fields[0] {
		case "choice":
			choice := Choice{
				Kind:               fields[1],
				ID:                 fields[2],
				Label:              fields[3],
				Executable:         dashEmpty(fields[5]),
				ShowUnavailableISO: fields[8] == "true",
				TUIHint:            dashEmpty(fields[9]),
				ShellDetail:        dashEmpty(fields[10]),
				Experimental:       strings.Contains(","+fields[11]+",", ",experimental,"),
				NoPackages:         strings.Contains(","+fields[11]+",", ",none,"),
			}
			if packages := dashEmpty(fields[4]); packages != "" {
				choice.Packages = strings.Split(packages, ",")
			}
			if choice.Kind == "" || choice.ID == "" || choice.Label == "" {
				return definition{}, fmt.Errorf("installer choices line %d is incomplete", lineNo+1)
			}
			// An empty package column is a typo unless the row says it meant it,
			// and a row that says so must not also carry packages.
			if len(choice.Packages) == 0 && !choice.NoPackages {
				return definition{}, fmt.Errorf("installer choices line %d lists no packages; add the none flag if that is deliberate", lineNo+1)
			}
			if len(choice.Packages) > 0 && choice.NoPackages {
				return definition{}, fmt.Errorf("installer choices line %d is flagged none but lists packages", lineNo+1)
			}
			for _, existing := range def.choices[choice.Kind] {
				if existing.ID == choice.ID {
					return definition{}, fmt.Errorf("installer choices line %d repeats %s %s", lineNo+1, choice.Kind, choice.ID)
				}
			}
			def.choices[choice.Kind] = append(def.choices[choice.Kind], choice)
		case "policy":
			value := fields[6]
			if fields[2] == "existing" {
				value = fields[7]
			}
			if value == "" || value == "-" {
				return definition{}, fmt.Errorf("installer choices line %d has an empty policy", lineNo+1)
			}
			def.policies[fields[1]+":"+fields[2]] = value
		default:
			return definition{}, fmt.Errorf("installer choices line %d has unknown record type %q", lineNo+1, fields[0])
		}
	}
	if !seenHeader {
		return definition{}, errors.New("installer choices have no header")
	}
	for _, kind := range choiceKinds {
		if len(def.choices[kind]) == 0 {
			return definition{}, fmt.Errorf("installer choices define no %s entries", kind)
		}
		for _, policy := range []string{"fresh", "existing"} {
			if def.policies[kind+":"+policy] == "" {
				return definition{}, fmt.Errorf("installer choices define no %s %s policy", policy, kind)
			}
		}
	}
	return def, nil
}

func dashEmpty(value string) string {
	if value == "-" {
		return ""
	}
	return value
}

func Choices(kind string) []Choice {
	def, err := loadDefinition()
	if err != nil {
		panic(err)
	}
	return append([]Choice(nil), def.choices[kind]...)
}

func ChoiceByID(kind, id string) (Choice, bool) {
	for _, choice := range Choices(kind) {
		if choice.ID == id {
			return choice, true
		}
	}
	return Choice{}, false
}

func IDs(kind string) []string {
	choices := Choices(kind)
	ids := make([]string, 0, len(choices))
	for _, choice := range choices {
		ids = append(ids, choice.ID)
	}
	return ids
}

func FreshDefault(kind string) string {
	def, err := loadDefinition()
	if err != nil {
		panic(err)
	}
	return def.policies[kind+":fresh"]
}

func FreshSelection(kind string, available []string) string {
	selected := FreshDefault(kind)
	if selected != "first-available" {
		return selected
	}
	if len(available) == 0 {
		return ""
	}
	return available[0]
}

func ExistingLoginShell(current string, available []string) string {
	def, err := loadDefinition()
	if err != nil {
		panic(err)
	}
	fallback := def.policies[LoginShell+":fresh"]
	if def.policies[LoginShell+":existing"] != "keep-supported-else-fish" {
		return fallback
	}
	current = filepath.Base(current)
	for _, id := range available {
		if id == current {
			return current
		}
	}
	return fallback
}

func ExistingFileManager(current string, available []string) string {
	def, err := loadDefinition()
	if err != nil {
		panic(err)
	}
	fallback := def.policies[FileManager+":fresh"]
	if def.policies[FileManager+":existing"] != "keep-supported-else-nautilus" {
		return fallback
	}
	current = filepath.Base(current)
	for _, id := range available {
		if id == current {
			return current
		}
	}
	return fallback
}

func ResolveSource(edition string) EditionPlan {
	plan := EditionPlan{Edition: canonicalEdition(edition), choices: map[string][]Availability{}}
	for _, kind := range choiceKinds {
		for _, choice := range Choices(kind) {
			plan.choices[kind] = append(plan.choices[kind], Availability{Choice: choice, Available: true})
		}
	}
	plan.components = resolveComponents(plan.Edition, nil)
	return plan
}

type translationRow struct {
	target string
	reason string
}

func ResolveEdition(data []byte) (EditionPlan, error) {
	rows := map[string]translationRow{}
	edition := ""
	header := false
	for lineNo, line := range strings.Split(string(data), "\n") {
		if strings.TrimSpace(line) == "" || strings.HasPrefix(strings.TrimSpace(line), "#") {
			continue
		}
		fields := strings.Split(line, "\t")
		if !header {
			header = true
			if len(fields) != 4 || fields[0] != "arch" || fields[2] != "lanes" || fields[3] != "notes" {
				return EditionPlan{}, fmt.Errorf("package table line %d has an invalid header", lineNo+1)
			}
			edition = fields[1]
			continue
		}
		if len(fields) != 4 {
			return EditionPlan{}, fmt.Errorf("package table line %d must have four tab-separated columns", lineNo+1)
		}
		rows[fields[0]] = translationRow{target: fields[1], reason: fields[3]}
	}
	if !header {
		return EditionPlan{}, errors.New("package table has no header")
	}
	plan := EditionPlan{Edition: edition, choices: map[string][]Availability{}}
	for _, kind := range choiceKinds {
		for _, choice := range Choices(kind) {
			availability := Availability{Choice: choice, Available: true}
			for _, pkg := range choice.Packages {
				row, ok := rows[pkg]
				if ok && row.target != "-" && row.target != "" {
					continue
				}
				availability.Available = false
				if ok && row.reason != "" {
					availability.Reason = row.reason
				} else {
					availability.Reason = fmt.Sprintf("%s is not listed in the %s edition table.", pkg, edition)
				}
				break
			}
			plan.choices[kind] = append(plan.choices[kind], availability)
		}
		if len(plan.AvailableIDs(kind)) == 0 {
			return EditionPlan{}, fmt.Errorf("the %s edition table publishes no %s choices", edition, kind)
		}
	}
	plan.components = resolveComponents(edition, rows)
	return plan, nil
}

func (p EditionPlan) Choices(kind string) []Availability {
	return append([]Availability(nil), p.choices[kind]...)
}

func (p EditionPlan) AvailableIDs(kind string) []string {
	var ids []string
	for _, choice := range p.choices[kind] {
		if choice.Available {
			ids = append(ids, choice.Choice.ID)
		}
	}
	return ids
}

func (p EditionPlan) Lookup(kind, id string) (Availability, bool) {
	for _, choice := range p.choices[kind] {
		if choice.Choice.ID == id {
			return choice, true
		}
	}
	return Availability{}, false
}

func DropPackagesFor(kind, selected string) []string {
	var drop []string
	for _, choice := range Choices(kind) {
		if choice.ID != selected {
			drop = append(drop, choice.Packages...)
		}
	}
	return drop
}

func DropPackages(browser, shell string) []string {
	drop := DropPackagesFor(Browser, browser)
	return append(drop, DropPackagesFor(LoginShell, shell)...)
}
