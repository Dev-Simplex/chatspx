package merge

import "testing"

func TestIsAllowed(t *testing.T) {
	ok := [][2]string{
		{"homologacao", "producao"},
		{"paulao", "producao"},
		{"paulao", "homologacao"},
	}
	for _, c := range ok {
		if !IsAllowed(c[0], c[1]) {
			t.Errorf("deveria permitir %s -> %s", c[0], c[1])
		}
	}
	bad := [][2]string{
		{"producao", "homologacao"}, // nao volta pra tras
		{"producao", "paulao"},
		{"homologacao", "paulao"},
		{"develop", "producao"}, // nao usam develop
		{"x", "y"},
	}
	for _, c := range bad {
		if IsAllowed(c[0], c[1]) {
			t.Errorf("NAO deveria permitir %s -> %s", c[0], c[1])
		}
	}
}

func TestRunRejectsBadFlow(t *testing.T) {
	if _, err := Run(t.TempDir(), "x", "producao", "paulao"); err == nil {
		t.Error("Run deveria recusar fluxo nao permitido")
	}
}
