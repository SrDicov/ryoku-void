package main

import (
	"strings"
	"testing"
)

// The fixture is the real z-repo release key; the expected fingerprint is what
// xbps itself prints when it discovers the repository, and gives the trusted
// key its file name in /var/db/xbps/keys.
const zrepoTestPEM = `-----BEGIN PUBLIC KEY-----
MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAtxsCRxPCfAjfmTVe9Ni4
+bvnRleha2Mr8pe7XoMcutJLIoh/uL9R7qKot5uJlxjpYQPYou6/x7cTtJdxOuBw
0FlmZa3EaXvKaVr5Kr+rQNErmsPifLmfpUuuOR2cM19fVYrJ47UHvZ5PxlrONhIl
a91HYjrKaRKtuSpxO1Au2sPnAVMVAC9pPma911nt87DSI13p0Z2b6nhz/EM+z7jt
zsDUSjhc8G55yY5WSfFtkNEkhFCLPYY/Jt1p6b57Pe3V7WBoavKeHvBcgBtT3DYO
KECda81eEb+FsU4zi3M4uBAlIQcCOSU/d7lBtZ5dOPA8mVkNOZ60Mli7F9eNbteb
s/tj0YSF52cz//ZR1Fx5CJhc9cglAiXef3PxWfvW95Goi1/pb65Y3bxB0l5HIM3b
cngLcp6g66cEWCbKN5SfdFbKTfsDK0nPOAPs3FoACP9TjOq1l1oJenqst58UWB9Y
Jsjf4xPnTlJT2RcsT0D3KyzZBGnvqLSMnALeylDvDkiqfEBeKLsGvCfyq5T4clo/
8P7sIVv9/klIJAgRWA1AerbB8aGtpidPYrLXij/yPyrpuyEQXfL+3Oktut/n3gn2
UI2RW315Oi4sEEfnIrDq2GApLYb70NePsaJcLdrDisiTHoAdKrHchePY7Vcsb0+4
sEkdkGDykzq6Jt2yPM6PlEsCAwEAAQ==
-----END PUBLIC KEY-----
`

func TestSshPubkeyFingerprint(t *testing.T) {
	fp, err := sshPubkeyFingerprint([]byte(zrepoTestPEM))
	if err != nil {
		t.Fatal(err)
	}
	if fp != voidLinux.zrepoKeyFP {
		t.Fatalf("z-repo fingerprint %s; pinned %s", fp, voidLinux.zrepoKeyFP)
	}
	// a trust anchor must never accept truncated or tampered keys
	if _, err := sshPubkeyFingerprint([]byte(zrepoTestPEM[:len(zrepoTestPEM)/2])); err == nil {
		t.Fatal("corrupt key accepted")
	}
	tampered := strings.Replace(zrepoTestPEM, "MIICIjAN", "0IICIjAN", 1)
	if _, err := sshPubkeyFingerprint([]byte(tampered)); err == nil {
		t.Fatal("tampered key accepted")
	}
}
