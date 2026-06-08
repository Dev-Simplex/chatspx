package safety

import (
	"fmt"
	"regexp"
	"strings"
)

var (
	vmIDRe   = regexp.MustCompile(`^[a-z0-9_-]{1,40}$`)
	shaRe    = regexp.MustCompile(`^[0-9a-fA-F]{7,40}$`)
	branchRe = regexp.MustCompile(`^[A-Za-z0-9._/-]{1,100}$`)
)

// shellMeta: caracteres que permitiriam injecao de comando. Inclui backtick
// (concatenado) para evitar conflito com string literals do Go.
const shellMeta = ";&|$(){}<>\n\r\"'\\" + "`"

func hasShellMeta(s string) bool { return strings.ContainsAny(s, shellMeta) }

func IsValidVMID(s string) bool  { return vmIDRe.MatchString(s) }
func IsValidSHA(s string) bool   { return shaRe.MatchString(s) }
func IsValidBranch(s string) bool {
	return branchRe.MatchString(s) && !hasShellMeta(s)
}

// AssertSafeArg rejeita qualquer argumento com metacaractere de shell —
// defense-in-depth, aplicado tanto no control quanto dentro do agente.
func AssertSafeArg(value, label string) error {
	if hasShellMeta(value) {
		return fmt.Errorf("argumento %q contem caractere proibido (possivel injecao): %q", label, value)
	}
	return nil
}
