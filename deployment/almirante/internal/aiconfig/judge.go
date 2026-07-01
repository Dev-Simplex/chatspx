package aiconfig

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// judge.go e o LLM-juiz do test-gate de prompt. Cliente minimo de chat/completions
// (OpenAI-compat): dada a rubrica + (input, resposta nova, baseline), devolve score
// 0-1 e veredito por cenario. Portado do noc-spxia.

type Judge struct {
	apiKey  string
	model   string
	baseURL string
	http    *http.Client
}

// NewJudge cria o cliente. apiKey vazio => Available()==false (gate degrada).
func NewJudge(apiKey, model, baseURL string, timeout time.Duration) *Judge {
	if strings.TrimSpace(model) == "" {
		model = "gpt-4o-mini"
	}
	if strings.TrimSpace(baseURL) == "" {
		baseURL = "https://api.openai.com/v1"
	}
	if timeout <= 0 {
		timeout = 30 * time.Second
	}
	return &Judge{
		apiKey:  strings.TrimSpace(apiKey),
		model:   model,
		baseURL: strings.TrimRight(baseURL, "/"),
		http:    &http.Client{Timeout: timeout},
	}
}

func (j *Judge) Available() bool { return j != nil && j.apiKey != "" }

// JudgeVerdict e a avaliacao de UM cenario.
type JudgeVerdict struct {
	ScenarioID int     `json:"scenario_id"`
	Score      float64 `json:"score"`
	Verdict    string  `json:"verdict"`
	Reasons    string  `json:"reasons"`
}

const judgeSystemPrompt = `Você é um juiz de qualidade de respostas de um agente de atendimento brasileiro (Captain/ChatSPX).
Avalie a RESPOSTA do agente contra a rubrica e devolva SOMENTE um objeto JSON.
Rubrica (cada item pesa no score):
1. Responde em pt-BR natural e correto.
2. Não inventa fatos, políticas ou preços fora do contexto fornecido.
3. Chama a pessoa pelo nome quando o nome está disponível.
4. Dispara a tool certa quando o cenário exige (ex.: pergunta de imóvel -> tool de imóveis).
5. Tom adequado; usar "IGNORAR" apenas quando o cenário é espera por atendimento humano.
A resposta nova deve ser >= ao baseline esperado em fidelidade, segurança e tom.
Saída JSON estrita: {"score": <number 0..1>, "verdict": "pass|warn|fail", "reasons": "<curto>"}.
Convenção: score>=0.8 => pass; 0.6<=score<0.8 => warn; score<0.6 => fail.`

type chatMsg struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}
type chatReq struct {
	Model          string            `json:"model"`
	Messages       []chatMsg         `json:"messages"`
	Temperature    float64           `json:"temperature"`
	ResponseFormat map[string]string `json:"response_format,omitempty"`
}
type chatResp struct {
	Choices []struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
	} `json:"choices"`
	Error *struct {
		Message string `json:"message"`
		Type    string `json:"type"`
	} `json:"error"`
}

// ScoreScenario pede ao juiz a avaliacao de um cenario.
func (j *Judge) ScoreScenario(ctx context.Context, scenarioID int, input, response, expected, expectedTool string, toolCalls []string) (JudgeVerdict, error) {
	if !j.Available() {
		return JudgeVerdict{}, fmt.Errorf("judge: sem api key")
	}
	var b strings.Builder
	fmt.Fprintf(&b, "Cenário #%d\n", scenarioID)
	fmt.Fprintf(&b, "MENSAGEM DO CLIENTE:\n%s\n\n", strings.TrimSpace(input))
	fmt.Fprintf(&b, "RESPOSTA NOVA DO AGENTE:\n%s\n\n", strings.TrimSpace(response))
	if strings.TrimSpace(expected) != "" {
		fmt.Fprintf(&b, "BASELINE ESPERADO (referência):\n%s\n\n", strings.TrimSpace(expected))
	}
	if strings.TrimSpace(expectedTool) != "" {
		fmt.Fprintf(&b, "TOOL ESPERADA: %s\n", expectedTool)
	}
	if len(toolCalls) > 0 {
		fmt.Fprintf(&b, "TOOLS DISPARADAS: %s\n", strings.Join(toolCalls, ", "))
	}
	b.WriteString("\nAvalie e devolva o JSON.")

	reqBody := chatReq{
		Model:          j.model,
		Temperature:    0,
		ResponseFormat: map[string]string{"type": "json_object"},
		Messages: []chatMsg{
			{Role: "system", Content: judgeSystemPrompt},
			{Role: "user", Content: b.String()},
		},
	}
	raw, err := json.Marshal(reqBody)
	if err != nil {
		return JudgeVerdict{}, fmt.Errorf("judge: marshal: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, j.baseURL+"/chat/completions", bytes.NewReader(raw))
	if err != nil {
		return JudgeVerdict{}, fmt.Errorf("judge: build req: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+j.apiKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	resp, err := j.http.Do(req)
	if err != nil {
		return JudgeVerdict{}, fmt.Errorf("judge: do req: %w", err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 64*1024))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return JudgeVerdict{}, fmt.Errorf("judge: http %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	var cr chatResp
	if err := json.Unmarshal(body, &cr); err != nil {
		return JudgeVerdict{}, fmt.Errorf("judge: decode envelope: %w", err)
	}
	if cr.Error != nil {
		return JudgeVerdict{}, fmt.Errorf("judge: api error: %s", cr.Error.Message)
	}
	if len(cr.Choices) == 0 {
		return JudgeVerdict{}, fmt.Errorf("judge: resposta sem choices")
	}
	content := strings.TrimSpace(cr.Choices[0].Message.Content)
	var parsed struct {
		Score   float64 `json:"score"`
		Verdict string  `json:"verdict"`
		Reasons string  `json:"reasons"`
	}
	if err := json.Unmarshal([]byte(content), &parsed); err != nil {
		return JudgeVerdict{}, fmt.Errorf("judge: conteudo nao-JSON: %w (%.200s)", err, content)
	}
	if parsed.Score < 0 {
		parsed.Score = 0
	}
	if parsed.Score > 1 {
		parsed.Score = 1
	}
	if parsed.Verdict == "" {
		switch {
		case parsed.Score >= 0.8:
			parsed.Verdict = "pass"
		case parsed.Score >= 0.6:
			parsed.Verdict = "warn"
		default:
			parsed.Verdict = "fail"
		}
	}
	return JudgeVerdict{ScenarioID: scenarioID, Score: parsed.Score, Verdict: parsed.Verdict, Reasons: parsed.Reasons}, nil
}
