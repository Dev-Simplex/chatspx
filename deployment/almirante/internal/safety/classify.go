// Package safety classifica migrations destrutivas e sanitiza input.
// A classificacao e SEMPRE server-side — nunca confiar no LLM para isso.
package safety

import (
	"regexp"

	"github.com/Dev-Simplex/almirante/internal/types"
)

// DestructiveDenylist: migrations conhecidamente irreversiveis.
// 20260330120000 faz DELETE de orfaos + FK on_delete: :cascade.
var DestructiveDenylist = map[string]string{
	"20260330120000": "DELETE de orfaos + FK on_delete: :cascade (irreversivel)",
}

var destructivePattern = regexp.MustCompile(`(?i)(drop_|remove_|rename_|delete_|_cascade|truncate)`)

// Classify decide se uma migration e destrutiva (denylist + heuristica).
func Classify(version, name string) types.PendingMigration {
	if reason, ok := DestructiveDenylist[version]; ok {
		return types.PendingMigration{Version: version, Name: name, Destructive: true, Reason: reason}
	}
	if destructivePattern.MatchString(name) {
		return types.PendingMigration{Version: version, Name: name, Destructive: true, Reason: "padrao destrutivo no nome (heuristica)"}
	}
	return types.PendingMigration{Version: version, Name: name, Destructive: false}
}

// IsDestructive e o atalho booleano.
func IsDestructive(version, name string) bool {
	return Classify(version, name).Destructive
}
