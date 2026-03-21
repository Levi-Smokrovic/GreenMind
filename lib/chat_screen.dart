import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:llamadart/llamadart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _modelUrl =
    'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf';
const _modelFileName = 'qwen2.5-0.5b-instruct-q4_k_m.gguf';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  // Chat state
  List<_ChatMsg> _messages = [];
  bool _modelLoaded = false;
  bool _loading = false;
  bool _generating = false;
  String _statusText = 'Model not loaded yet';
  double _progress = 0;
  int _messageCount = 0;

  // Streaming UI throttle
  DateTime _lastUiUpdate = DateTime.now();
  static const _uiThrottle = Duration(milliseconds: 80);

  // Model
  LlamaEngine? _engine;
  ChatSession? _session;

  // Chat persistence
  List<_SavedChat> _savedChats = [];
  String? _activeChatId;

  @override
  void initState() {
    super.initState();
    _loadSavedChats();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _engine?.dispose();
    super.dispose();
  }

  // ── Persistence ──────────────────────────────────────────────

  Future<void> _loadSavedChats() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('saved_chats');
    if (raw != null) {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      setState(() => _savedChats = list.map(_SavedChat.fromJson).toList());
    }
  }

  Future<void> _persistChats() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(_savedChats.map((c) => c.toJson()).toList());
    await prefs.setString('saved_chats', json);
  }

  void _saveCurrentChat() {
    if (_messages.isEmpty) return;
    final title = _messages.first.text.length > 40
        ? '${_messages.first.text.substring(0, 40)}...'
        : _messages.first.text;

    if (_activeChatId != null) {
      final idx = _savedChats.indexWhere((c) => c.id == _activeChatId);
      if (idx >= 0) {
        _savedChats[idx] = _SavedChat(
          id: _activeChatId!,
          title: title,
          messages: List.from(_messages),
          timestamp: DateTime.now(),
        );
      }
    } else {
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      _activeChatId = id;
      _savedChats.insert(
        0,
        _SavedChat(id: id, title: title, messages: List.from(_messages), timestamp: DateTime.now()),
      );
    }
    _persistChats();
  }

  void _loadChat(_SavedChat chat) {
    setState(() {
      _messages = List.from(chat.messages);
      _activeChatId = chat.id;
      _messageCount = _messages.where((m) => m.role == 'user').length;
    });
    Navigator.of(context).pop(); // close drawer
    _scrollToBottom();
  }

  void _deleteChat(String id) {
    setState(() {
      _savedChats.removeWhere((c) => c.id == id);
      if (_activeChatId == id) {
        _activeChatId = null;
        _messages.clear();
        _messageCount = 0;
      }
    });
    _persistChats();
  }

  // ── Model ───────────────────────────────────────────────────

  Future<String> get _modelPath async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$_modelFileName';
  }

  Future<void> _loadModel() async {
    setState(() {
      _loading = true;
      _statusText = 'Checking for cached model...';
    });

    try {
      final path = await _modelPath;
      final file = File(path);

      if (!file.existsSync()) {
        setState(() => _statusText = 'Downloading Qwen 2.5 0.5B...');
        await _downloadModel(path);
      }

      setState(() => _statusText = 'Loading model into memory...');

      _engine = LlamaEngine(LlamaBackend());
      await _engine!.loadModel(
        path,
        modelParams: const ModelParams(
          contextSize: 2048,
          numberOfThreads: 4,
          batchSize: 512,
        ),
      );
      _session = ChatSession(
        _engine!,
        systemPrompt: 'You are GreenMind, a helpful and concise AI assistant that runs locally on the user\'s device. You are climate-friendly because you use no cloud servers. Keep answers clear and helpful.',
      );

      setState(() {
        _modelLoaded = true;
        _loading = false;
        _statusText = 'Ready — everything runs locally on your device';
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _statusText = 'Error: $e';
      });
    }
  }

  Future<void> _downloadModel(String savePath) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_modelUrl));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('Download failed: HTTP ${response.statusCode}');
      }

      final total = response.contentLength;
      var received = 0;
      final sink = File(savePath).openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          final pct = (received / total * 100).round();
          setState(() {
            _progress = received / total;
            _statusText = 'Downloading: $pct% (${(received / 1024 / 1024).toStringAsFixed(1)} MB)';
          });
        }
      }
      await sink.close();
    } finally {
      client.close();
    }
  }

  // ── Chat ────────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _session == null || _generating) return;

    _controller.clear();
    setState(() {
      _messages.add(_ChatMsg(role: 'user', text: text));
      _generating = true;
      _statusText = 'Thinking...';
    });
    _scrollToBottom();

    try {
      // Add empty assistant message for streaming
      setState(() => _messages.add(_ChatMsg(role: 'assistant', text: '')));
      final idx = _messages.length - 1;

      final buffer = StringBuffer();
      // ChatSession manages history and context window automatically
      final stream = _session!.create([LlamaTextContent(text)]);

      await for (final chunk in stream) {
        final token = chunk.choices.first.delta.content ?? '';
        if (token.isNotEmpty) {
          buffer.write(token);
          final now = DateTime.now();
          if (now.difference(_lastUiUpdate) >= _uiThrottle) {
            _lastUiUpdate = now;
            setState(() {
              _messages[idx] = _ChatMsg(
                role: 'assistant',
                text: buffer.toString().trim(),
              );
            });
            _scrollToBottomFast();
          }
        }
      }
      // Final flush
      setState(() {
        _messages[idx] = _ChatMsg(
          role: 'assistant',
          text: buffer.toString().trim(),
        );
      });

      _messageCount++;
      _saveCurrentChat();
      setState(() {
        _generating = false;
        _statusText =
            'Ready — CO\u2082 saved: ~${(_messageCount * 0.16).toStringAsFixed(2)}g';
      });
    } catch (e) {
      setState(() {
        _messages.add(_ChatMsg(role: 'assistant', text: 'Error: $e'));
        _generating = false;
        _statusText = 'Error occurred';
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _scrollToBottomFast() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  void _newChat() {
    setState(() {
      _messages.clear();
      _activeChatId = null;
      _messageCount = 0;
      _statusText = 'Ready — everything runs locally on your device';
    });
  }

  // ── UI ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _modelLoaded ? _buildDrawer() : null,
      appBar: AppBar(
        leading: _modelLoaded
            ? Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              )
            : null,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('\u{1F331} ', style: TextStyle(fontSize: 20)),
            Text('GreenMind AI',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
          ],
        ),
        actions: [
          if (_modelLoaded)
            IconButton(
              icon: const Icon(Icons.add_comment_rounded),
              onPressed: _newChat,
              tooltip: 'New chat',
            ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          _buildStatusBar(),

          // Messages or welcome
          Expanded(
            child: !_modelLoaded ? _buildWelcome() : _buildMessageList(),
          ),

          // Input
          if (_modelLoaded) _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        border: Border(bottom: BorderSide(color: Colors.green.shade100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _modelLoaded
                    ? Icons.check_circle_rounded
                    : _loading
                        ? Icons.downloading_rounded
                        : Icons.circle_outlined,
                size: 14,
                color: _modelLoaded
                    ? const Color(0xFF22C55E)
                    : const Color(0xFF16A34A),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _statusText,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF166534)),
                ),
              ),
            ],
          ),
          if (_loading && _progress > 0) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress,
                backgroundColor: const Color(0xFFDCFCE7),
                color: const Color(0xFF22C55E),
                minHeight: 5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFF16A34A),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('\u{1F331} GreenMind AI',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('Your saved conversations',
                      style: TextStyle(color: Color(0xFFBBF7D0), fontSize: 13)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_comment_rounded, color: Color(0xFF16A34A)),
              title: const Text('New Chat', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                _newChat();
                Navigator.of(context).pop();
              },
            ),
            const Divider(height: 1),
            Expanded(
              child: _savedChats.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('No saved chats yet',
                            style: TextStyle(color: Color(0xFF9CA3AF))),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _savedChats.length,
                      itemBuilder: (context, i) {
                        final chat = _savedChats[i];
                        final isActive = chat.id == _activeChatId;
                        return ListTile(
                          selected: isActive,
                          selectedTileColor: const Color(0xFFF0FDF4),
                          leading: Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 20,
                            color: isActive ? const Color(0xFF16A34A) : const Color(0xFF9CA3AF),
                          ),
                          title: Text(
                            chat.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            '${chat.messages.length} messages',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => _deleteChat(chat.id),
                          ),
                          onTap: () => _loadChat(chat),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcome() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFBBF7D0), width: 3),
              ),
              child: const Center(
                child: Text('\u{1F331}', style: TextStyle(fontSize: 48)),
              ),
            ),
            const SizedBox(height: 24),
            const Text('GreenMind AI',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Climate-friendly AI that runs 100% locally.\nNo cloud servers. No CO\u2082 emissions.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Color(0xFF6B7280), height: 1.5),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.memory_rounded, size: 16, color: Color(0xFF16A34A)),
                  SizedBox(width: 8),
                  Text('Qwen 2.5 · 0.5B · Q4 quantized',
                      style: TextStyle(fontSize: 12, color: Color(0xFF166534))),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 220,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _loadModel,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.download_rounded),
                label: Text(
                  _loading ? 'Loading...' : 'Load Model',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _InfoChip(icon: Icons.lock_outline, label: 'Private'),
                SizedBox(width: 8),
                _InfoChip(icon: Icons.wifi_off_rounded, label: 'Offline'),
                SizedBox(width: 8),
                _InfoChip(icon: Icons.eco_rounded, label: 'Green'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('\u{1F331}', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            const Text('Start a conversation',
                style: TextStyle(fontSize: 16, color: Color(0xFF9CA3AF))),
            const SizedBox(height: 4),
            Text(
              'Your messages stay on this device',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: _messages.length + (_generating ? 0 : 0),
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final isUser = msg.role == 'user';
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!isUser) ...[
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF0FDF4),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text('\u{1F331}', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isUser
                        ? const Color(0xFF16A34A)
                        : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isUser ? 18 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: msg.text.isEmpty
                      ? const _TypingDots()
                      : SelectableText(
                          msg.text,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            color: isUser ? Colors.white : const Color(0xFF1F2937),
                          ),
                        ),
                ),
              ),
              if (isUser) ...[
                const SizedBox(width: 8),
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: Color(0xFF16A34A),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person, color: Colors.white, size: 18),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 8,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              onSubmitted: (_) => _sendMessage(),
              textInputAction: TextInputAction.send,
              maxLines: 4,
              minLines: 1,
              decoration: InputDecoration(
                hintText: 'Ask GreenMind anything...',
                hintStyle: const TextStyle(color: Color(0xFFBBBBBB)),
                filled: true,
                fillColor: const Color(0xFFF9FAFB),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: Color(0xFF22C55E), width: 1.5),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _generating ? const Color(0xFF86EFAC) : const Color(0xFF16A34A),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: _generating ? null : _sendMessage,
                child: Center(
                  child: _generating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.arrow_upward_rounded,
                          color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Data classes ──────────────────────────────────────────────

class _ChatMsg {
  final String role;
  final String text;
  const _ChatMsg({required this.role, required this.text});

  Map<String, dynamic> toJson() => {'role': role, 'text': text};
  factory _ChatMsg.fromJson(Map<String, dynamic> json) =>
      _ChatMsg(role: json['role'] as String, text: json['text'] as String);
}

class _SavedChat {
  final String id;
  final String title;
  final List<_ChatMsg> messages;
  final DateTime timestamp;

  _SavedChat({
    required this.id,
    required this.title,
    required this.messages,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'messages': messages.map((m) => m.toJson()).toList(),
        'timestamp': timestamp.toIso8601String(),
      };

  factory _SavedChat.fromJson(Map<String, dynamic> json) => _SavedChat(
        id: json['id'] as String,
        title: json['title'] as String,
        messages: (json['messages'] as List)
            .map((m) => _ChatMsg.fromJson(m as Map<String, dynamic>))
            .toList(),
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}

// ── Widgets ──────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF16A34A)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF166534))),
        ],
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.2;
            final t = ((_anim.value - delay) % 1.0).clamp(0.0, 1.0);
            final y = t < 0.5 ? -4.0 * (2 * t) : -4.0 * (2 * (1 - t));
            return Transform.translate(
              offset: Offset(0, y),
              child: Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: const BoxDecoration(
                  color: Color(0xFF4ADE80),
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
