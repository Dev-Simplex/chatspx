package safety

import "testing"

func TestClassify(t *testing.T) {
	cases := []struct {
		version, name string
		wantDestr     bool
	}{
		{"20260330120000", "add_foreign_key_constraints", true}, // denylist
		{"20260521090000", "add_column_last_seen_to_contacts", false},
		{"20260101000000", "drop_table_old_sessions", true},     // heuristica drop_
		{"20260101000001", "remove_column_foo", true},           // heuristica remove_
		{"20260101000002", "rename_users_to_accounts", true},    // heuristica rename_
		{"20260101000003", "add_index_to_conversations", false},
		{"20260101000004", "create_table_widgets", false},
	}
	for _, c := range cases {
		got := Classify(c.version, c.name)
		if got.Destructive != c.wantDestr {
			t.Errorf("Classify(%s,%s).Destructive = %v, quer %v", c.version, c.name, got.Destructive, c.wantDestr)
		}
		if c.wantDestr && got.Reason == "" {
			t.Errorf("Classify(%s,%s) destrutiva sem reason", c.version, c.name)
		}
	}
}

func TestSanitize(t *testing.T) {
	if !IsValidVMID("tozi") || !IsValidVMID("chatspx-fabrica") {
		t.Error("vm id valido rejeitado")
	}
	if IsValidVMID("tozi; rm -rf /") || IsValidVMID("UPPER") {
		t.Error("vm id invalido aceito")
	}
	if !IsValidSHA("d4e5f6a") || !IsValidSHA("88da75b") {
		t.Error("sha valido rejeitado")
	}
	if IsValidSHA("zzzz") || IsValidSHA("d4e5f6a; reboot") {
		t.Error("sha invalido aceito")
	}
	if !IsValidBranch("producao") || !IsValidBranch("feature/x.y_z-1") {
		t.Error("branch valida rejeitada")
	}
	if IsValidBranch("producao && rm -rf /") || IsValidBranch("`whoami`") {
		t.Error("branch com injecao aceita")
	}
}

func TestAssertSafeArg(t *testing.T) {
	safe := []string{"tozi", "d4e5f6a", "producao", "feature/x"}
	for _, s := range safe {
		if err := AssertSafeArg(s, "arg"); err != nil {
			t.Errorf("AssertSafeArg(%q) deveria passar: %v", s, err)
		}
	}
	bad := []string{"a;b", "a|b", "a`b`", "a$(x)", "a&b", "a>b", "a\nb", `a"b`}
	for _, s := range bad {
		if err := AssertSafeArg(s, "arg"); err == nil {
			t.Errorf("AssertSafeArg(%q) deveria falhar", s)
		}
	}
}
