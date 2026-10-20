package main

import (
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"slices"
	"sort"
	"strconv"
	"strings"
	"time"

	"ryoku-i18n"
)

const fedoraReleasesURL = "https://repo.ryoku.dev/stable/fedora/releases"

type httpDoer interface {
	Do(*http.Request) (*http.Response, error)
}

func osReleaseField(text, key string) string {
	for _, line := range strings.Split(text, "\n") {
		name, value, ok := strings.Cut(line, "=")
		if !ok || name != key {
			continue
		}
		return strings.Trim(strings.TrimSpace(value), `"'`)
	}
	return ""
}

func fedoraReleaseRepoURL(ref, release string) string {
	_, repository := fedoraRepository(ref)
	return strings.ReplaceAll(repository, "$releasever", release) + "/repodata/repomd.xml"
}

func httpStatusOK(client httpDoer, method, url string) (*http.Response, error) {
	req, err := http.NewRequest(method, url, nil)
	if err != nil {
		return nil, err
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode != http.StatusOK {
		resp.Body.Close()
		return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	return resp, nil
}

func fedoraRepositoryPublished(client httpDoer, url string) (bool, error) {
	check := func(method string) (int, error) {
		req, err := http.NewRequest(method, url, nil)
		if err != nil {
			return 0, err
		}
		resp, err := client.Do(req)
		if err != nil {
			return 0, err
		}
		defer resp.Body.Close()
		return resp.StatusCode, nil
	}

	code, err := check(http.MethodHead)
	if err != nil {
		return false, err
	}
	switch code {
	case http.StatusOK:
		return true, nil
	case http.StatusNotFound:
		return false, nil
	}

	code, err = check(http.MethodGet)
	if err != nil {
		return false, err
	}
	switch code {
	case http.StatusOK:
		return true, nil
	case http.StatusNotFound:
		return false, nil
	default:
		return false, fmt.Errorf("HTTP %d", code)
	}
}

func supportedFedoraReleases(client httpDoer) ([]string, error) {
	resp, err := httpStatusOK(client, http.MethodGet, fedoraReleasesURL)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 64*1024))
	if err != nil {
		return nil, err
	}
	var releases []string
	for _, field := range strings.Fields(string(body)) {
		if _, err := strconv.Atoi(field); err != nil {
			return nil, fmt.Errorf("invalid Fedora release %q", field)
		}
		releases = append(releases, field)
	}
	if len(releases) == 0 {
		return nil, fmt.Errorf("empty release list")
	}
	return releases, nil
}

// isFedoraPublishedOnChannel counts an unreachable repository as published,
// since the release list is shared with testing.
func isFedoraPublishedOnChannel(client httpDoer, ref string, releases []string) bool {
	for _, release := range releases {
		published, err := fedoraRepositoryPublished(client, fedoraReleaseRepoURL(ref, release))
		if published || err != nil {
			return true
		}
	}
	return false
}

func fedoraReleaseVersion(osReleasePath string) (string, error) {
	data, err := os.ReadFile(osReleasePath)
	if err != nil {
		return "", fmt.Errorf(i18n.T("read Fedora release: %w"), err)
	}
	release := osReleaseField(string(data), "VERSION_ID")
	if release == "" {
		return "", fmt.Errorf(i18n.T("Fedora VERSION_ID is missing from %s"), osReleasePath)
	}
	return release, nil
}

func fedoraReleaseGate(client httpDoer, ref, osReleasePath string) error {
	if os.Getenv("RYOKU_RPM_REPO") != "" {
		return nil
	}
	release, err := fedoraReleaseVersion(osReleasePath)
	if err != nil {
		return err
	}
	published, err := fedoraRepositoryPublished(client, fedoraReleaseRepoURL(ref, release))
	if err != nil {
		return fmt.Errorf(i18n.T("Ryoku repository for Fedora %s could not be reached: %v"), release, err)
	}
	if published {
		return nil
	}
	supported, listErr := supportedFedoraReleases(client)
	if listErr != nil {
		return fmt.Errorf(i18n.T("Ryoku does not publish packages for Fedora %s yet. Supported releases could not be read from %s: %v"), release, fedoraReleasesURL, listErr)
	}
	if channel, _ := fedoraRepository(ref); channel == "stable" && slices.Contains(supported, release) && !isFedoraPublishedOnChannel(client, ref, supported) {
		return errors.New(i18n.T("The stable channel has no Fedora packages until Ryoku's first Fedora release. To install the testing packages now, run the installer with --ref unstable-dev."))
	}
	message := i18n.Tf("Ryoku does not publish packages for Fedora %s yet. Supported: %s.", release, strings.Join(supported, ", "))
	running, parseErr := strconv.Atoi(release)
	if parseErr == nil {
		versions := make([]int, 0, len(supported))
		for _, value := range supported {
			version, convErr := strconv.Atoi(value)
			if convErr == nil {
				versions = append(versions, version)
			}
		}
		sort.Ints(versions)
		if len(versions) > 0 && running < versions[0] {
			message += " " + i18n.T("Upgrade Fedora first with sudo dnf system-upgrade.")
		}
	}
	return fmt.Errorf("%s", message)
}

func fedoraReleaseHTTPClient() *http.Client {
	return &http.Client{Timeout: 8 * time.Second}
}
