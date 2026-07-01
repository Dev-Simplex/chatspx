// Package types contem os tipos compartilhados da plataforma Almirante.
package types

type VMAuth string

const (
	AuthKey      VMAuth = "key"
	AuthPassword VMAuth = "password"
)

// VM e uma maquina da frota (sem segredos — credenciais ficam no control).
type VM struct {
	ID            string `json:"id"`
	Name          string `json:"name"`
	IP            string `json:"ip"`
	TransportUser string `json:"transport_user"`
	Auth          VMAuth `json:"auth"`
	Env           string `json:"env"`
	Branch        string `json:"branch"`
	Critical      bool   `json:"critical"`
	AutoApprove   bool   `json:"auto_approve"`
	// Governanca de IA (receptor spx/ai_config). Vazio = VM sem IA governavel.
	// O api_access_token NAO fica aqui (secret): vem de AICONFIG_TOKEN_<slug>.
	AIConfigURL       string `json:"aiconfig_url,omitempty"`
	AIConfigAccountID int    `json:"aiconfig_account_id,omitempty"`
}

// Fleet e o inventario carregado de fleet.json.
type Fleet struct {
	GitHubRepo    string `json:"github_repo"`
	DefaultBranch string `json:"default_branch"`
	VMs           []VM   `json:"vms"`
}

type HostStatus struct {
	VM            string `json:"vm"`
	Online        bool   `json:"online"`
	ServiceActive bool   `json:"service_active"`
	Puma          int    `json:"puma"`
	Sidekiq       int    `json:"sidekiq"`
	CPU           *int   `json:"cpu"`
	RAM           *int   `json:"ram"`
	Disk          *int   `json:"disk"`
	PingMS        *int   `json:"ping_ms"`
	Commit        string `json:"commit"`
	Branch        string `json:"branch"`
	Uptime        string `json:"uptime"`
}

// HealthReport e o health COMPOSTO real (nunca "exit 0").
type HealthReport struct {
	VM                  string `json:"vm"`
	Healthy             bool   `json:"healthy"`
	ServiceActive       bool   `json:"service_active"`
	DB                  bool   `json:"db"`
	Redis               bool   `json:"redis"`
	Sidekiq             bool   `json:"sidekiq"`
	HTTP200             bool   `json:"http_200"`
	MigrationsUpToDate  bool   `json:"migrations_up_to_date"`
	Detail              string `json:"detail"`
}

type PendingMigration struct {
	Version     string `json:"version"`
	Name        string `json:"name"`
	Destructive bool   `json:"destructive"`
	Reason      string `json:"reason,omitempty"`
}

type MigrationStatus struct {
	VM            string             `json:"vm"`
	UpToDate      bool               `json:"up_to_date"`
	Pending       []PendingMigration `json:"pending"`
	HasDestructive bool              `json:"has_destructive"`
}

type GitDiff struct {
	VM          string `json:"vm"`
	CurrentSHA  string `json:"current_sha"`
	TargetSHA   string `json:"target_sha"`
	BehindCount int    `json:"behind_count"`
	Commits     []struct {
		SHA     string `json:"sha"`
		Subject string `json:"subject"`
	} `json:"commits"`
	CompareURL string `json:"compare_url"`
}

type DeployStatus string

const (
	StatusPending   DeployStatus = "pending"
	StatusApproved  DeployStatus = "approved"
	StatusExecuting DeployStatus = "executing"
	StatusSuccess   DeployStatus = "success"
	StatusFailed    DeployStatus = "failed"
	StatusExpired   DeployStatus = "expired"
	StatusRejected  DeployStatus = "rejected"
)

type DeployRequest struct {
	ID            string             `json:"id"`
	VM            string             `json:"vm"`
	Branch        string             `json:"branch"`
	TargetSHA     string             `json:"target_sha"`
	CurrentSHA    string             `json:"current_sha"`
	RequestedBy   string             `json:"requested_by"`
	Status        DeployStatus       `json:"status"`
	Migrations    []PendingMigration `json:"migrations"`
	HasDestructive bool              `json:"has_destructive"`
	CreatedAt     string             `json:"created_at"`
	ExpiresAt     string             `json:"expires_at"`
	ApprovedBy    string             `json:"approved_by,omitempty"`
	ApprovedAt    string             `json:"approved_at,omitempty"`
	FinishedAt    string             `json:"finished_at,omitempty"`
	ResultDetail  string             `json:"result_detail,omitempty"`
}

type DeployHistoryEntry struct {
	ID         string       `json:"id"`
	VM         string       `json:"vm"`
	FromSHA    string       `json:"from_sha"`
	ToSHA      string       `json:"to_sha"`
	Actor      string       `json:"actor"`
	ApprovedBy string       `json:"approved_by,omitempty"`
	Status     DeployStatus `json:"status"`
	DurationS  *int         `json:"duration_s"`
	FinishedAt string       `json:"finished_at"`
}
