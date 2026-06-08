// Package fleet carrega e consulta o inventario da frota (fleet.json).
package fleet

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/Dev-Simplex/almirante/internal/types"
)

// Grupos logicos derivados (ambiente/criticidade).
var groups = map[string]func(types.VM) bool{
	"all":      func(types.VM) bool { return true },
	"aws":      func(v types.VM) bool { return v.Env == "AWS EC2" },
	"proxmox":  func(v types.VM) bool { return v.Env == "Proxmox" },
	"sandbox":  func(v types.VM) bool { return v.Env == "Sandbox" },
	"critical": func(v types.VM) bool { return v.Critical },
}

func Load(path string) (*types.Fleet, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("lendo fleet %s: %w", path, err)
	}
	var f types.Fleet
	if err := json.Unmarshal(data, &f); err != nil {
		return nil, fmt.Errorf("parse fleet %s: %w", path, err)
	}
	return &f, nil
}

func FindVM(f *types.Fleet, id string) (types.VM, bool) {
	for _, v := range f.VMs {
		if v.ID == id {
			return v, true
		}
	}
	return types.VM{}, false
}

// Group retorna os ids das VMs de um grupo logico; ok=false se grupo invalido.
func Group(f *types.Fleet, name string) (ids []string, ok bool) {
	pred, exists := groups[name]
	if !exists {
		return nil, false
	}
	for _, v := range f.VMs {
		if pred(v) {
			ids = append(ids, v.ID)
		}
	}
	return ids, true
}

func CompareURL(repo, from, to string) string {
	if from == "" || to == "" {
		return ""
	}
	return fmt.Sprintf("https://github.com/%s/compare/%s...%s", repo, from, to)
}
