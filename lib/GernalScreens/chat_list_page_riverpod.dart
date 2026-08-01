import 'package:flutter/material.dart';
import 'package:vero360_app/GernalScreens/chat_list_page.dart';

/// Legacy Riverpod/Firebase chat list.
///
/// Use [ChatListPage] with [BackendChatService] / [MessagePageBackendApi] instead.
@Deprecated(
  'Firebase chat list is deprecated. Use ChatListPage (backend API) instead.',
)
class ChatListPageRiverpod extends StatelessWidget {
  const ChatListPageRiverpod({super.key});

  @override
  Widget build(BuildContext context) => const ChatListPage();
}
