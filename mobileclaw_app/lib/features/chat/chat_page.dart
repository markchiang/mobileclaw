import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../core/models/chat_models.dart';
import 'chat_controller.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.controller});

  final ChatController controller;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int _lastMessageCount = 0;
  String _lastSessionKey = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _lastMessageCount = widget.controller.messages.length;
    _lastSessionKey = widget.controller.currentSessionKey;
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _input.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      final nextCount = widget.controller.messages.length;
      final countIncreased = nextCount > _lastMessageCount;
      final sessionChanged =
          widget.controller.currentSessionKey != _lastSessionKey;
      _lastMessageCount = nextCount;
      _lastSessionKey = widget.controller.currentSessionKey;
      setState(() {});
      if (countIncreased || sessionChanged) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
      }
    }
  }

  void _jumpToBottom() {
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    final bottom = _scrollController.position.maxScrollExtent;
    _scrollController.jumpTo(bottom);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.controller.messages;
    final currentSession = widget.controller.currentSessionKey;

    return Scaffold(
      appBar: AppBar(
        title: Text('MobileClaw · $currentSession'),
        actions: <Widget>[
          IconButton(
            tooltip: '歷史對話',
            icon: const Icon(Icons.history),
            onPressed: _openHistorySheet,
          ),
          IconButton(
            tooltip: '新對話',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: widget.controller.isBusy
                ? null
                : () async {
                    await widget.controller.createNewChat();
                    _input.clear();
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _jumpToBottom());
                  },
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView.builder(
              key: const PageStorageKey<String>('chat_list'),
              controller: _scrollController,
              reverse: false,
              itemCount: items.length,
              itemBuilder: (BuildContext context, int index) {
                final msg = items[index];
                return _MessageCard(msg: msg);
              },
            ),
          ),
          if (widget.controller.isBusy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: '輸入訊息 (支援 Markdown 回覆)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: widget.controller.isBusy
                      ? null
                      : () async {
                          final text = _input.text;
                          _input.clear();
                          await widget.controller.send(text);
                        },
                  child: const Text('送出'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openHistorySheet() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext context) {
        final sessions = widget.controller.sessions;
        final current = widget.controller.currentSessionKey;
        return SafeArea(
          child: ListView(
            children: <Widget>[
              const ListTile(
                title: Text('聊天歷史'),
                subtitle: Text('選擇對話繼續'),
              ),
              for (final s in sessions)
                ListTile(
                  title: Text(
                    s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    s.key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: s.key == current
                      ? const Icon(Icons.check, size: 18)
                      : null,
                  onTap: () => Navigator.of(context).pop(s.key),
                ),
            ],
          ),
        );
      },
    );
    if (!mounted || selected == null) {
      return;
    }
    await widget.controller.switchSession(selected);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.msg});

  final ChatMessage msg;

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == ChatRole.user;
    final color = isUser
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: msg.content));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已複製訊息'),
              duration: Duration(seconds: 1),
            ),
          );
        },
        child: Card(
          color: color,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: MarkdownBody(data: msg.content),
          ),
        ),
      ),
    );
  }
}
