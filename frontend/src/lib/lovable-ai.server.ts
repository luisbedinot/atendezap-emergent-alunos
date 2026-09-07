// Multi-provider AI chat.
//
// DEFAULT (Gemini): routed through the local Emergent AI proxy (FastAPI backend
// at /api/ai/chat) which uses the Emergent Universal Key. This replaces the
// original Lovable AI Gateway — the Lovable gateway and its credits are NOT used.
// OpenAI and Anthropic remain available using the company's own keys (advanced
// agent screen / plans that unlock external providers).

export interface ChatMsg {
  role: "system" | "user" | "assistant";
  content: string;
}

export interface AiProviderConfig {
  provider?: "gemini" | "openai" | "anthropic" | string;
  model?: string;
  openaiKey?: string;
  anthropicKey?: string;
}

export async function lovableAiChat(
  messages: ChatMsg[],
  modelOrConfig: string | AiProviderConfig = "gemini-2.5-flash",
): Promise<string> {
  const cfg: AiProviderConfig =
    typeof modelOrConfig === "string"
      ? { provider: "gemini", model: modelOrConfig }
      : modelOrConfig;
  const provider = (cfg.provider || "gemini").toLowerCase();

  if (provider === "openai") {
    const key = cfg.openaiKey?.trim();
    if (!key) throw new Error("Chave OpenAI não configurada na sua empresa.");
    const model = cfg.model || "gpt-4o-mini";
    return openAiChat(key, model, messages);
  }
  if (provider === "anthropic") {
    const key = cfg.anthropicKey?.trim();
    if (!key) throw new Error("Chave Anthropic (Claude) não configurada na sua empresa.");
    const model = cfg.model || "claude-3-5-sonnet-latest";
    return anthropicChat(key, model, messages);
  }

  // default: Gemini via Emergent Universal Key (through the local backend proxy)
  const endpoint = process.env.AI_CHAT_URL || "http://127.0.0.1:8001/api/ai/chat";
  const model = (cfg.model && !cfg.model.startsWith("google/")) ? cfg.model : "gemini-2.5-flash";
  const res = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      // server->server auth; never exposed to the browser (not a VITE_ var)
      "x-ai-proxy-secret": process.env.AI_PROXY_SECRET || "",
    },
    body: JSON.stringify({ model, messages }),
  });
  if (!res.ok) {
    const t = await res.text();
    if (res.status === 403) throw new Error("IA indisponível: proxy interno não autorizado.");
    if (res.status === 402) throw new Error("Créditos de IA (Emergent) esgotados. Recarregue a chave universal.");
    if (res.status === 503) throw new Error("IA não configurada: defina EMERGENT_LLM_KEY no backend.");
    throw new Error(`Emergent AI: ${res.status} ${t.slice(0, 200)}`);
  }
  const data = await res.json();
  return (data?.content ?? "").toString().trim();
}

async function openAiChat(key: string, model: string, messages: ChatMsg[]): Promise<string> {
  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ model, messages }),
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`OpenAI: ${res.status} ${t.slice(0, 200)}`);
  }
  const data = await res.json();
  return data?.choices?.[0]?.message?.content?.toString().trim() || "";
}

async function anthropicChat(key: string, model: string, messages: ChatMsg[]): Promise<string> {
  const system = messages.filter((m) => m.role === "system").map((m) => m.content).join("\n\n");
  const conv = messages
    .filter((m) => m.role !== "system")
    .map((m) => ({ role: m.role, content: m.content }));
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": key,
      "anthropic-version": "2023-06-01",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ model, max_tokens: 1024, system, messages: conv }),
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`Anthropic: ${res.status} ${t.slice(0, 200)}`);
  }
  const data = await res.json();
  const txt = (data?.content || [])
    .filter((p: any) => p?.type === "text")
    .map((p: any) => p.text)
    .join("\n")
    .trim();
  return txt;
}
