import { Wllama } from 'https://cdn.jsdelivr.net/npm/@wllama/wllama@2.3.7/esm/index.js';

// --- Config ---
// Qwen2.5-0.5B-Instruct — Q4_K_M quantized, ~491 MB, cached in browser after first download
const MODEL_HF_REPO = 'Qwen/Qwen2.5-0.5B-Instruct-GGUF';
const MODEL_HF_FILE = 'qwen2.5-0.5b-instruct-q4_k_m.gguf';
const STORAGE_KEY = "greenmind_data";

const WASM_PATHS = {
  'single-thread/wllama.wasm': 'https://cdn.jsdelivr.net/npm/@wllama/wllama@2.3.7/esm/single-thread/wllama.wasm',
  'multi-thread/wllama.wasm': 'https://cdn.jsdelivr.net/npm/@wllama/wllama@2.3.7/esm/multi-thread/wllama.wasm',
};

// System prompt — same as mobile apps
const SYSTEM_PROMPT = `You are GreenMind, a helpful and concise AI assistant that runs locally on the user's device. You are climate-friendly because you use no cloud servers. Keep answers clear and helpful.`;

// --- State ---
let wllama = null;
let isGenerating = false;
let messageCount = 0;
let chatHistory = [];

// Multi-chat persistence
const CHATS_KEY = "greenmind_chats";
let savedChats = []; // [{id, title, messages, messageCount}]
let activeChatId = null;

// --- Persistence ---
function saveState() {
  if (chatHistory.length === 0) return;
  const title = chatHistory[0]?.content?.substring(0, 40) || 'New chat';
  if (activeChatId) {
    const idx = savedChats.findIndex(c => c.id === activeChatId);
    if (idx >= 0) savedChats[idx] = { id: activeChatId, title, messages: [...chatHistory], messageCount };
  } else {
    activeChatId = Date.now().toString();
    savedChats.unshift({ id: activeChatId, title, messages: [...chatHistory], messageCount });
  }
  try { localStorage.setItem(CHATS_KEY, JSON.stringify(savedChats)); } catch {}
  renderChatList();
}

function loadAllChats() {
  try {
    const raw = localStorage.getItem(CHATS_KEY);
    if (raw) savedChats = JSON.parse(raw);
  } catch {}
  // Migrate old single-chat data
  try {
    const old = localStorage.getItem(STORAGE_KEY);
    if (old) {
      const d = JSON.parse(old);
      if (d.chatHistory?.length) {
        const id = Date.now().toString();
        savedChats.unshift({ id, title: d.chatHistory[0]?.content?.substring(0, 40) || 'Old chat', messages: d.chatHistory, messageCount: d.messageCount || 0 });
        localStorage.setItem(CHATS_KEY, JSON.stringify(savedChats));
      }
      localStorage.removeItem(STORAGE_KEY);
    }
  } catch {}
}

function loadChat(chat) {
  chatHistory = [...chat.messages];
  messageCount = chat.messageCount || 0;
  activeChatId = chat.id;
  renderMessages();
  updateCarbonStats();
  closeSidebar();
}

function deleteChat(id) {
  savedChats = savedChats.filter(c => c.id !== id);
  if (activeChatId === id) { activeChatId = null; chatHistory = []; messageCount = 0; renderMessages(); updateCarbonStats(); }
  try { localStorage.setItem(CHATS_KEY, JSON.stringify(savedChats)); } catch {}
  renderChatList();
}

function newChat() {
  activeChatId = null;
  chatHistory = [];
  messageCount = 0;
  renderMessages();
  updateCarbonStats();
  closeSidebar();
  if (wllama) userInput.focus();
}

function clearState() {
  localStorage.removeItem(CHATS_KEY);
  localStorage.removeItem(STORAGE_KEY);
  savedChats = [];
  activeChatId = null;
  chatHistory = [];
  messageCount = 0;
  renderChatList();
}

// --- DOM ---
const statusIcon = document.getElementById("status-icon");
const statusMsg = document.getElementById("status-msg");
const progressWrap = document.getElementById("progress-wrap");
const progressBar = document.getElementById("progress-bar");
const messagesDiv = document.getElementById("messages");
const chatContainer = document.getElementById("chat-container");
const loadBtn = document.getElementById("load-btn");
const chatInputWrap = document.getElementById("chat-input-wrap");
const userInput = document.getElementById("user-input");
const sendBtn = document.getElementById("send-btn");
const statDevice = document.getElementById("stat-device");
const statCarbon = document.getElementById("stat-carbon");
const sidebar = document.getElementById("sidebar");
const sidebarOverlay = document.getElementById("sidebar-overlay");
const chatListEl = document.getElementById("chat-list");

// --- Sidebar ---
function openSidebar() { sidebar?.classList.add("open"); sidebarOverlay?.classList.add("open"); }
function closeSidebar() { sidebar?.classList.remove("open"); sidebarOverlay?.classList.remove("open"); }

function renderChatList() {
  if (!chatListEl) return;
  if (savedChats.length === 0) {
    chatListEl.innerHTML = '<div class="no-chats">No saved chats yet</div>';
    return;
  }
  chatListEl.innerHTML = savedChats.map(c => `
    <div class="chat-item${c.id === activeChatId ? ' active' : ''}" data-id="${escapeHtml(c.id)}">
      <div class="chat-item-text" onclick="loadChatById('${escapeHtml(c.id)}')">
        <div class="chat-item-title">${escapeHtml(c.title)}</div>
        <div class="chat-item-meta">${c.messages.length} messages</div>
      </div>
      <button class="chat-item-del" onclick="deleteChatById('${escapeHtml(c.id)}')" title="Delete">&times;</button>
    </div>
  `).join('');
}

// Global helpers for onclick handlers
window.loadChatById = (id) => { const c = savedChats.find(x => x.id === id); if (c) loadChat(c); };
window.deleteChatById = (id) => deleteChat(id);
window.openSidebar = openSidebar;
window.closeSidebar = closeSidebar;
window.newChat = newChat;

function renderMessages() {
  // Clear all except the welcome message
  messagesDiv.innerHTML = '';
  if (chatHistory.length === 0) {
    messagesDiv.innerHTML = `<div class="message assistant"><div class="bubble">
      Hi! I'm <strong>GreenMind</strong> &mdash; a climate-friendly AI that runs entirely on your device.
      No cloud servers, no CO&#8322; from data centers. Start typing to chat!</div></div>`;
    return;
  }
  for (const msg of chatHistory) {
    if (msg.role === "user") addMessage("user", escapeHtml(msg.content));
    else if (msg.role === "assistant") addMessage("assistant", formatText(msg.content));
  }
}

// --- Detect device ---
function detectDevice() {
  const ua = navigator.userAgent;
  const mem = navigator.deviceMemory ? `${navigator.deviceMemory} GB RAM` : "";
  let device = "Unknown";
  if (/iPhone|iPad/.test(ua)) device = "Apple iOS";
  else if (/Mac/.test(ua)) device = "macOS";
  else if (/Android/.test(ua)) device = "Android";
  else if (/Windows/.test(ua)) device = "Windows";
  else if (/Linux/.test(ua)) device = "Linux";
  statDevice.textContent = `Device: ${device}${mem ? ` (${mem})` : ""}`;
}

// --- CO2 ---
function updateCarbonStats() {
  const saved = (messageCount * 0.16).toFixed(2);
  statCarbon.textContent = `CO\u2082 saved: ~${saved}g (${messageCount} queries)`;
}

// --- Load model ---
async function loadModel() {
  loadBtn.disabled = true;
  loadBtn.textContent = "Loading...";
  progressWrap.classList.remove("hidden");
  setStatus("loading", "Initializing WASM engine...");

  try {
    wllama = new Wllama(WASM_PATHS, { allowOffline: true });

    setStatus("loading", "Loading model (one-time ~491 MB download, cached in browser)...");

    await wllama.loadModelFromHF(MODEL_HF_REPO, MODEL_HF_FILE, {
      n_ctx: 2048,
      progressCallback: ({ loaded, total }) => {
        if (total > 0) {
          const pct = Math.round((loaded / total) * 100);
          progressBar.style.width = `${pct}%`;
          setStatus("loading", `Loading model: ${pct}% (${(loaded / 1e6).toFixed(0)} / ${(total / 1e6).toFixed(0)} MB)`);
        }
      },
    });

    setStatus("ready", "Model loaded! Everything runs locally on your device.");
    loadBtn.style.display = "none";
    chatInputWrap.classList.remove("hidden");
    progressWrap.classList.add("hidden");
    userInput.focus();
  } catch (err) {
    console.error("Load error:", err);
    setStatus("error", `Error: ${err.message}`);
    loadBtn.disabled = false;
    loadBtn.textContent = "Try again";
  }
}

// --- Status ---
function setStatus(type, msg) {
  statusMsg.textContent = msg;
  statusIcon.className = "spinner";
  statusIcon.style = "";
  if (type === "loading") statusIcon.classList.add("loading");
  if (type === "ready") statusIcon.classList.add("ready");
  if (type === "error") {
    statusIcon.style.border = "2px solid #ef4444";
    statusIcon.style.background = "#ef4444";
    statusIcon.style.animation = "none";
  }
}

// --- Chat UI helpers ---
function addMessage(role, content) {
  const msgDiv = document.createElement("div");
  msgDiv.className = `message ${role}`;
  const bubble = document.createElement("div");
  bubble.className = "bubble";
  bubble.innerHTML = content;
  msgDiv.appendChild(bubble);
  messagesDiv.appendChild(msgDiv);
  chatContainer.scrollTop = chatContainer.scrollHeight;
  return bubble;
}

function addTypingIndicator() {
  const msgDiv = document.createElement("div");
  msgDiv.className = "message assistant";
  msgDiv.id = "typing-indicator";
  msgDiv.innerHTML = `<div class="typing-indicator"><span></span><span></span><span></span></div>`;
  messagesDiv.appendChild(msgDiv);
  chatContainer.scrollTop = chatContainer.scrollHeight;
}

function removeTypingIndicator() {
  const el = document.getElementById("typing-indicator");
  if (el) el.remove();
}

// --- Build ChatML prompt with context window (Qwen2.5 format) ---
const MAX_HISTORY_TURNS = 6; // keep last N user/assistant pairs to stay within 2048 ctx

function buildPrompt(userMessage) {
  let prompt = `<|im_start|>system\n${SYSTEM_PROMPT}<|im_end|>\n`;

  // Include recent chat history for context
  const recentHistory = chatHistory.slice(-(MAX_HISTORY_TURNS * 2));
  for (const msg of recentHistory) {
    const role = msg.role === 'user' ? 'user' : 'assistant';
    prompt += `<|im_start|>${role}\n${msg.content}<|im_end|>\n`;
  }

  prompt += `<|im_start|>user\n${userMessage}<|im_end|>\n<|im_start|>assistant\n`;
  return prompt;
}

// --- Send message ---
async function sendMessage() {
  const text = userInput.value.trim();
  if (!text || !wllama || isGenerating) return;

  isGenerating = true;
  sendBtn.disabled = true;
  userInput.value = "";
  userInput.style.height = "auto";

  addMessage("user", escapeHtml(text));
  addTypingIndicator();
  setStatus("loading", "Thinking...");

  chatHistory.push({ role: "user", content: text });
  const prompt = buildPrompt(text);

  try {
    removeTypingIndicator();
    const bubble = addMessage("assistant", "");

    const result = await wllama.createCompletion(prompt, {
      nPredict: 512,
      sampling: {
        temp: 0.3,
        top_k: 30,
        top_p: 0.9,
        min_p: 0.05,
        penalty_repeat: 1.2,
        penalty_last_n: 64,
      },
      onNewToken: (_token, _piece, textOrObj, _extra) => {
        // Handle both wllama v1 (object) and v2 (string) callback signatures
        const currentText = typeof textOrObj === 'string'
          ? textOrObj
          : (textOrObj?.completionText ?? '');
        if (!currentText) return;
        const cleaned = currentText
          .replace(/<\|im_end\|>.*$/s, "")
          .replace(/<\|im_start\|>.*$/s, "")
          .replace(/Google( Cloud Platform| AI| DeepMind)?/gi, "GreenMind")
          .replace(/\bQwen\b/gi, "GreenMind")
          .replace(/\bAlibaba\b/gi, "GreenMind team")
          .replace(/\bOpenAI\b/gi, "GreenMind")
          .replace(/\bGPT[-\s]?\d*/gi, "GreenMind");
        bubble.innerHTML = formatText(cleaned);
        chatContainer.scrollTop = chatContainer.scrollHeight;
      },
    });

    // Handle both string and object return types
    const rawResult = typeof result === 'string' ? result : (result || "").toString();
    let cleanResult = rawResult.replace(/<\|im_end\|>.*$/s, "").replace(/<\|im_start\|>.*$/s, "").trim();
    // Post-process: strip any leaked identity references
    cleanResult = cleanResult
      .replace(/Google( Cloud Platform| AI| DeepMind)?/gi, "GreenMind")
      .replace(/\bQwen\b/gi, "GreenMind")
      .replace(/\bAlibaba\b/gi, "GreenMind team")
      .replace(/\bOpenAI\b/gi, "GreenMind")
      .replace(/\bGPT[-\s]?\d*/gi, "GreenMind");
    bubble.innerHTML = formatText(cleanResult);
    chatHistory.push({ role: "assistant", content: cleanResult });
    messageCount++;
    saveState();
    updateCarbonStats();
    setStatus("ready", "Ready — everything stays on your device.");
  } catch (err) {
    removeTypingIndicator();
    console.error("Generation error:", err);
    addMessage("assistant", `<em>Error: ${escapeHtml(err.message)}</em>`);
    setStatus("ready", "Error occurred. Try again.");
    chatHistory.pop();
  }

  isGenerating = false;
  sendBtn.disabled = false;
  userInput.focus();
}

// --- Utilities ---
function escapeHtml(str) {
  const div = document.createElement("div");
  div.textContent = str;
  return div.innerHTML;
}

function formatText(text) {
  return escapeHtml(text)
    .replace(/\*\*(.*?)\*\*/g, "<strong>$1</strong>")
    .replace(/\*(.*?)\*/g, "<em>$1</em>")
    .replace(/`(.*?)`/g, "<code>$1</code>")
    .replace(/\n/g, "<br>");
}

function handleKey(event) {
  if (event.key === "Enter" && !event.shiftKey) {
    event.preventDefault();
    sendMessage();
  }
}

userInput.addEventListener("input", () => {
  userInput.style.height = "auto";
  userInput.style.height = Math.min(userInput.scrollHeight, 120) + "px";
});

// --- Restore chat ---
function restoreChats() {
  loadAllChats();
  renderChatList();
  // Load the most recent chat if any
  if (savedChats.length > 0) {
    chatHistory = [...savedChats[0].messages];
    messageCount = savedChats[0].messageCount || 0;
    activeChatId = savedChats[0].id;
    renderMessages();
  }
}

// --- Clear chat ---
function clearChat() {
  clearState();
  renderMessages();
  updateCarbonStats();
}

// --- Service Worker ---
if ("serviceWorker" in navigator) {
  caches.keys().then(keys => keys.forEach(k => caches.delete(k)));
  navigator.serviceWorker.getRegistrations().then(regs => {
    regs.forEach(r => r.unregister());
    setTimeout(() => navigator.serviceWorker.register("/sw.js"), 500);
  });
}

// --- Init ---
detectDevice();
restoreChats();
updateCarbonStats();

window.loadModel = loadModel;
window.sendMessage = sendMessage;
window.handleKey = handleKey;
window.clearChat = clearChat;
