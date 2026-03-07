import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _input.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.controller.messages;

    return Scaffold(
      appBar: AppBar(title: const Text('MobileClaw')),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView.builder(
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
      child: Card(
        color: color,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: MarkdownBody(data: msg.content),
        ),
      ),
    );
  }
}
