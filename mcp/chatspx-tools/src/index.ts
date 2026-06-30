#!/usr/bin/env node
/**
 * ChatSPX Tools MCP Server
 * -------------------------
 * A thin Model Context Protocol (stdio) server that wraps the ChatSPX
 * (Chatwoot-based) "Captain Custom Tools" REST API. It lets an admin
 * create / edit / delete / test Captain custom tools from an MCP client
 * (Claude Desktop, Cursor, etc.) WITHOUT touching the source code.
 *
 * GOVERNANCE
 * ----------
 * Tools created through this server are ALWAYS born disabled (enabled:false).
 * A human admin must review and ACTIVATE each tool in the ChatSPX UI at
 * /agents/tools. Enabling a tool via MCP is intentionally blocked.
 *
 * CONFIGURATION (environment variables)
 * -------------------------------------
 *   CHATSPX_API_URL     Base URL of the ChatSPX install (e.g. https://chat.example.com)
 *   CHATSPX_API_TOKEN   A user api_access_token (admin) sent as the `api_access_token` header
 *   CHATSPX_ACCOUNT_ID  Numeric account id the tools belong to
 *
 * All HTTP calls hit: {CHATSPX_API_URL}/api/v1/accounts/{CHATSPX_ACCOUNT_ID}/...
 * and carry the `api_access_token: {CHATSPX_API_TOKEN}` header.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import type { CallToolResult } from "@modelcontextprotocol/sdk/types.js";
import { z } from "zod";

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------

const SERVER_NAME = "chatspx-tools-mcp";
const SERVER_VERSION = "1.0.0";
const REQUEST_TIMEOUT_MS = 30_000;
const CHARACTER_LIMIT = 25_000;

// --------------------------------------------------------------------------
// Configuration
// --------------------------------------------------------------------------

interface ChatSpxConfig {
  apiUrl: string;
  token: string;
  accountId: string;
}

let CONFIG: ChatSpxConfig;

function loadConfig(): ChatSpxConfig | { error: string } {
  const missing: string[] = [];
  const apiUrl = process.env.CHATSPX_API_URL?.replace(/\/+$/, "");
  const token = process.env.CHATSPX_API_TOKEN;
  const accountId = process.env.CHATSPX_ACCOUNT_ID;

  if (!apiUrl) missing.push("CHATSPX_API_URL");
  if (!token) missing.push("CHATSPX_API_TOKEN");
  if (!accountId) missing.push("CHATSPX_ACCOUNT_ID");

  if (missing.length > 0) {
    return { error: `Missing required environment variable(s): ${missing.join(", ")}` };
  }
  return { apiUrl: apiUrl as string, token: token as string, accountId: accountId as string };
}

function baseUrl(): string {
  return `${CONFIG.apiUrl}/api/v1/accounts/${CONFIG.accountId}`;
}

// --------------------------------------------------------------------------
// Audit logging (stderr only — never stdout, which carries the MCP protocol)
// --------------------------------------------------------------------------

/**
 * Emit a single-line audit record to stderr: action + details + ISO timestamp.
 * Every tool invocation calls this so admins get a tamper-evident trail.
 */
function audit(action: string, details: Record<string, unknown> = {}): void {
  const ts = new Date().toISOString();
  const extra = Object.entries(details)
    .filter(([, v]) => v !== undefined)
    .map(([k, v]) => `${k}=${typeof v === "string" ? v : JSON.stringify(v)}`)
    .join(" ");
  console.error(`[AUDIT] ${ts} action=${action}${extra ? ` ${extra}` : ""}`);
}

// --------------------------------------------------------------------------
// HTTP client + error helpers
// --------------------------------------------------------------------------

type HttpMethod = "GET" | "POST" | "PATCH" | "DELETE";

interface ApiResult {
  ok: boolean;
  status: number;
  data: unknown;
}

/**
 * Perform an authenticated request against the ChatSPX REST API.
 * Always attaches the `api_access_token` header. Parses JSON when possible.
 */
async function apiRequest(path: string, method: HttpMethod = "GET", body?: unknown): Promise<ApiResult> {
  const url = `${baseUrl()}${path}`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const response = await fetch(url, {
      method,
      headers: {
        api_access_token: CONFIG.token,
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: controller.signal,
    });

    const raw = await response.text();
    let data: unknown = null;
    if (raw) {
      try {
        data = JSON.parse(raw);
      } catch {
        data = raw;
      }
    }
    return { ok: response.ok, status: response.status, data };
  } finally {
    clearTimeout(timer);
  }
}

function pretty(data: unknown): string {
  return typeof data === "string" ? data : JSON.stringify(data, null, 2);
}

function truncate(text: string, limit = CHARACTER_LIMIT): string {
  if (text.length <= limit) return text;
  return `${text.slice(0, limit)}\n…[truncated ${text.length - limit} chars]`;
}

/** Build a clear, actionable error message for a non-2xx API response. */
function apiErrorText(action: string, res: ApiResult): string {
  const snippet = truncate(pretty(res.data));
  let hint = "";
  switch (res.status) {
    case 401:
      hint = " Check that CHATSPX_API_TOKEN is a valid api_access_token.";
      break;
    case 403:
      hint = " This action requires an administrator token.";
      break;
    case 404:
      hint = " Check the tool id and CHATSPX_ACCOUNT_ID.";
      break;
    case 422:
      hint =
        " Validation failed. Common causes: endpoint_url must be a PUBLIC https URL (localhost/private IPs are blocked), title is required, param_schema items need name+type+description.";
      break;
    default:
      hint = "";
  }
  return `Error: ${action} failed (HTTP ${res.status}).${hint}\nResponse: ${snippet}`;
}

/** Build a clear error message for network/timeout failures. */
function networkErrorText(action: string, err: unknown): string {
  if (err instanceof Error && err.name === "AbortError") {
    return `Error: ${action} timed out after ${REQUEST_TIMEOUT_MS}ms. Check CHATSPX_API_URL is reachable.`;
  }
  const msg = err instanceof Error ? err.message : String(err);
  return `Error: ${action} failed: ${msg}. Check CHATSPX_API_URL and network connectivity.`;
}

// --------------------------------------------------------------------------
// MCP tool result helpers
// --------------------------------------------------------------------------

function ok(text: string, structured?: Record<string, unknown>): CallToolResult {
  const result: CallToolResult = { content: [{ type: "text", text: truncate(text) }] };
  if (structured) result.structuredContent = structured;
  return result;
}

function fail(text: string): CallToolResult {
  return { content: [{ type: "text", text: truncate(text) }], isError: true };
}

/** Copy only the provided (defined) keys from `args` into a clean payload object. */
function buildPayload(args: Record<string, unknown>, keys: readonly string[]): Record<string, unknown> {
  const payload: Record<string, unknown> = {};
  for (const key of keys) {
    if (args[key] !== undefined) payload[key] = args[key];
  }
  return payload;
}

// --------------------------------------------------------------------------
// Zod schemas (raw shapes for registerTool)
// --------------------------------------------------------------------------

const paramSchemaItem = z
  .object({
    name: z.string().min(1).describe("Parameter name; referenced in Liquid templates, e.g. order_id"),
    type: z.string().min(1).describe("Logical type, e.g. string | number | boolean"),
    description: z.string().min(1).describe("What this parameter is for (shown to the LLM)"),
    required: z.boolean().optional().describe("Whether the LLM must supply this parameter"),
  })
  .strict();

const httpMethodSchema = z.enum(["GET", "POST"]);
const authTypeSchema = z.enum(["none", "bearer", "basic", "api_key"]);
const authConfigSchema = z
  .record(z.string(), z.string())
  .describe(
    "Auth credentials object. bearer: {token}. basic: {username,password}. api_key: {key, location:'header'|'query', name}. Omit or {} for none."
  );

const createToolShape = {
  title: z.string().min(1).describe("Human-readable tool name. The slug is derived from it (e.g. 'Fetch Order Status' -> custom_fetch_order_status)."),
  description: z
    .string()
    .optional()
    .describe("What the tool does. The agent reads this to decide when to call the tool, so make it precise."),
  endpoint_url: z
    .string()
    .min(1)
    .describe(
      "PUBLIC https endpoint. localhost/private IPs are blocked by the SSRF guard. May contain Liquid placeholders, e.g. https://api.example.com/orders/{{ order_id }}"
    ),
  http_method: httpMethodSchema.default("GET").describe("GET or POST."),
  auth_type: authTypeSchema.default("none").describe("Authentication scheme used to call the endpoint."),
  auth_config: authConfigSchema.optional(),
  param_schema: z
    .array(paramSchemaItem)
    .optional()
    .describe("Parameters the agent must collect/provide before calling the tool."),
  request_template: z
    .string()
    .optional()
    .describe("Optional Liquid template for the POST request body, e.g. '{ \"order_id\": \"{{ order_id }}\" }'."),
  response_template: z
    .string()
    .optional()
    .describe("Optional Liquid template to format the upstream response shown to the agent, e.g. 'Status: {{ response.status }}'."),
  copilot_only: z
    .boolean()
    .optional()
    .describe("If true, the tool is only available in Copilot (agent-assist), not to the autonomous agent."),
} as const;

const CREATE_KEYS = [
  "title",
  "description",
  "endpoint_url",
  "http_method",
  "auth_type",
  "auth_config",
  "param_schema",
  "request_template",
  "response_template",
  "copilot_only",
] as const;

const updateToolShape = {
  id: z.number().int().positive().describe("Numeric id of the custom tool to update."),
  title: z.string().min(1).optional(),
  description: z.string().optional(),
  endpoint_url: z.string().min(1).optional().describe("PUBLIC https endpoint (localhost/private IPs are blocked)."),
  http_method: httpMethodSchema.optional(),
  auth_type: authTypeSchema.optional(),
  auth_config: authConfigSchema.optional(),
  param_schema: z.array(paramSchemaItem).optional(),
  request_template: z.string().optional(),
  response_template: z.string().optional(),
  copilot_only: z.boolean().optional(),
  enabled: z
    .boolean()
    .optional()
    .describe(
      "Only `false` is honored (disable / kill-switch). To ENABLE/activate a tool an admin must do it in the UI at /agents/tools — enabling via MCP is blocked by governance."
    ),
} as const;

const UPDATE_KEYS = [...CREATE_KEYS, "enabled"] as const;

const idShape = {
  id: z.number().int().positive().describe("Numeric id of the custom tool."),
} as const;

const testToolShape = {
  id: z.number().int().positive().describe("Numeric id of the custom tool to test."),
  params: z
    .record(z.string(), z.unknown())
    .optional()
    .describe("Values for the tool's param_schema, keyed by parameter name, e.g. { \"order_id\": \"123\" }."),
} as const;

// --------------------------------------------------------------------------
// Server + tools
// --------------------------------------------------------------------------

const server = new McpServer({ name: SERVER_NAME, version: SERVER_VERSION });

server.registerTool(
  "list_tools",
  {
    title: "List All Agent Tools",
    description: `List every tool available to Captain agents in this account — built-in tools AND custom tools.

Returns: array of { id, title, description, icon }.

Use this to discover existing tool ids/slugs before creating a new one (avoid duplicates) or to see what an agent can already do.`,
    inputSchema: {},
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: true },
  },
  async () => {
    audit("list_tools");
    try {
      const res = await apiRequest("/captain/assistants/tools", "GET");
      if (!res.ok) return fail(apiErrorText("list_tools", res));
      const tools = Array.isArray(res.data) ? (res.data as Array<Record<string, unknown>>) : [];
      const lines = tools.map((t) => `- ${String(t.id)} — ${String(t.title ?? "")}${t.description ? `: ${String(t.description)}` : ""}`);
      return ok(
        `Available agent tools (${tools.length}) — built-in + custom:\n${lines.join("\n") || "(none)"}`,
        { count: tools.length, tools }
      );
    } catch (err) {
      return fail(networkErrorText("list_tools", err));
    }
  }
);

server.registerTool(
  "list_custom_tools",
  {
    title: "List Custom Tools",
    description: `List this account's Captain CUSTOM tools (the ones manageable via this server).

Returns each tool's full configuration: id, slug, title, description, endpoint_url, http_method, auth_type, auth_config, param_schema, enabled, timestamps.

Use this to find a tool id before update/delete/test, or to inspect current configuration.`,
    inputSchema: {},
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: true },
  },
  async () => {
    audit("list_custom_tools");
    try {
      const res = await apiRequest("/captain/custom_tools", "GET");
      if (!res.ok) return fail(apiErrorText("list_custom_tools", res));
      const data = (res.data ?? {}) as { payload?: Array<Record<string, unknown>> };
      const tools = Array.isArray(data.payload) ? data.payload : [];
      const lines = tools.map(
        (t) =>
          `- id=${String(t.id)} slug=${String(t.slug)} "${String(t.title)}" [${t.enabled ? "ENABLED" : "disabled"}] ${String(
            t.http_method
          )} ${String(t.endpoint_url)}`
      );
      return ok(`Custom tools (${tools.length}):\n${lines.join("\n") || "(none)"}`, { count: tools.length, tools });
    } catch (err) {
      return fail(networkErrorText("list_custom_tools", err));
    }
  }
);

server.registerTool(
  "create_tool",
  {
    title: "Create Custom Tool (disabled)",
    description: `Create a new Captain custom tool that calls an external HTTP endpoint.

GOVERNANCE: the tool is ALWAYS created DISABLED (enabled:false). It will not run until an admin reviews and activates it in the UI at /agents/tools. You cannot enable it from here.

Inputs:
  - title (required): display name; the slug is derived from it.
  - description: when/why the agent should use the tool.
  - endpoint_url (required): PUBLIC https URL; may contain Liquid like .../orders/{{ order_id }}.
  - http_method: GET (default) or POST.
  - auth_type: none (default) | bearer | basic | api_key.
  - auth_config: credentials object (see auth_type).
  - param_schema: array of { name, type, description, required? }.
  - request_template / response_template: optional Liquid templates.
  - copilot_only: restrict to Copilot only.

Returns the created tool object (note enabled:false).`,
    inputSchema: createToolShape,
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: true },
  },
  async (args) => {
    audit("create_tool", { title: args.title, http_method: args.http_method, enabled: false });
    try {
      const payload = buildPayload(args as Record<string, unknown>, CREATE_KEYS);
      payload.enabled = false; // GOVERNANCE: tools are born disabled; an admin activates them in the UI.
      const res = await apiRequest("/captain/custom_tools", "POST", { custom_tool: payload });
      if (!res.ok) return fail(apiErrorText("create_tool", res));
      const created = (res.data ?? {}) as Record<string, unknown>;
      audit("create_tool.result", { id: created.id, slug: created.slug, enabled: created.enabled });
      return ok(
        `Created custom tool "${String(created.title)}" (id=${String(created.id)}, slug=${String(created.slug)}).\n` +
          `Status: DISABLED. An admin must review and ACTIVATE it in the UI at /agents/tools.\n\n${pretty(created)}`,
        { tool: created }
      );
    } catch (err) {
      return fail(networkErrorText("create_tool", err));
    }
  }
);

server.registerTool(
  "update_tool",
  {
    title: "Update Custom Tool",
    description: `Update an existing Captain custom tool. Provide the numeric id plus any fields to change.

Editable fields: title, description, endpoint_url, http_method, auth_type, auth_config, param_schema, request_template, response_template, copilot_only.

GOVERNANCE on the 'enabled' flag:
  - enabled:false IS honored (use it as a kill-switch to disable a live tool).
  - enabled:true is REFUSED — activating a tool must be done by an admin in the UI at /agents/tools.

Returns the updated tool object.`,
    inputSchema: updateToolShape,
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: true },
  },
  async (args) => {
    audit("update_tool", { id: args.id });
    if (args.enabled === true) {
      return fail(
        "Refused: enabling a tool via MCP is blocked by governance. To ACTIVATE a tool an admin must enable it in the UI at /agents/tools. (You may pass enabled:false to disable a tool.)"
      );
    }
    try {
      const payload = buildPayload(args as Record<string, unknown>, UPDATE_KEYS);
      delete payload.id;
      if (Object.keys(payload).length === 0) {
        return fail("Nothing to update: provide at least one field besides id.");
      }
      const res = await apiRequest(`/captain/custom_tools/${args.id}`, "PATCH", { custom_tool: payload });
      if (!res.ok) return fail(apiErrorText("update_tool", res));
      const updated = (res.data ?? {}) as Record<string, unknown>;
      audit("update_tool.result", { id: updated.id, enabled: updated.enabled });
      return ok(`Updated custom tool id=${String(updated.id)} ("${String(updated.title)}").\n\n${pretty(updated)}`, {
        tool: updated,
      });
    } catch (err) {
      return fail(networkErrorText("update_tool", err));
    }
  }
);

server.registerTool(
  "delete_tool",
  {
    title: "Delete Custom Tool",
    description: `Permanently delete a Captain custom tool by numeric id. This cannot be undone.

Tip: if you only want to stop a tool from running, prefer update_tool with enabled:false instead of deleting it.

Returns a confirmation message.`,
    inputSchema: idShape,
    annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: true },
  },
  async (args) => {
    audit("delete_tool", { id: args.id });
    try {
      const res = await apiRequest(`/captain/custom_tools/${args.id}`, "DELETE");
      if (!res.ok) return fail(apiErrorText("delete_tool", res));
      audit("delete_tool.result", { id: args.id, status: res.status });
      return ok(`Deleted custom tool id=${args.id} (HTTP ${res.status}).`);
    } catch (err) {
      return fail(networkErrorText("delete_tool", err));
    }
  }
);

server.registerTool(
  "test_tool",
  {
    title: "Test Custom Tool",
    description: `Smoke-test a custom tool against its real endpoint (this exercises the SSRF guard and auth/template building, exactly like the agent would).

Inputs:
  - id (required): numeric id of the tool to test.
  - params: values for the tool's param_schema keyed by name, e.g. { "order_id": "123" }.

Returns { ok, status, body } on success, or { ok:false, error } if the upstream call failed. A disabled tool can still be tested.`,
    inputSchema: testToolShape,
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: false, openWorldHint: true },
  },
  async (args) => {
    audit("test_tool", { id: args.id });
    try {
      const res = await apiRequest(`/captain/custom_tools/${args.id}/test`, "POST", { params: args.params ?? {} });
      if (!res.ok) return fail(apiErrorText("test_tool", res));
      const result = (res.data ?? {}) as Record<string, unknown>;
      const header = result.ok
        ? `Test OK — upstream responded HTTP ${String(result.status)}.`
        : `Test reached the server but the upstream call failed: ${String(result.error ?? "unknown error")}.`;
      return ok(`${header}\n\n${pretty(result)}`, { result });
    } catch (err) {
      return fail(networkErrorText("test_tool", err));
    }
  }
);

// --------------------------------------------------------------------------
// Bootstrap (stdio transport)
// --------------------------------------------------------------------------

async function main(): Promise<void> {
  const loaded = loadConfig();
  if ("error" in loaded) {
    console.error(`[${SERVER_NAME}] FATAL: ${loaded.error}`);
    console.error("Set CHATSPX_API_URL, CHATSPX_API_TOKEN and CHATSPX_ACCOUNT_ID, then retry.");
    process.exit(1);
  }
  CONFIG = loaded;

  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error(`[${SERVER_NAME}] v${SERVER_VERSION} running (stdio). account=${CONFIG.accountId} api=${CONFIG.apiUrl}`);
}

main().catch((err) => {
  console.error(`[${SERVER_NAME}] fatal error:`, err);
  process.exit(1);
});
