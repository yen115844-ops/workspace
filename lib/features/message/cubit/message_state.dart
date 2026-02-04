import 'package:equatable/equatable.dart';

import '../../../core/models/models.dart';

enum MessageStatus { initial, loading, success, failure, sending }

class MessageState extends Equatable {
  final MessageStatus status;
  final List<MessageModel> messages;
  final String? nextCursor;
  final bool hasMore;
  final String? error;
  final String? sendingMessageId;

  const MessageState({
    this.status = MessageStatus.initial,
    this.messages = const [],
    this.nextCursor,
    this.hasMore = false,
    this.error,
    this.sendingMessageId,
  });

  MessageState copyWith({
    MessageStatus? status,
    List<MessageModel>? messages,
    String? nextCursor,
    bool? hasMore,
    String? error,
    String? sendingMessageId,
  }) {
    return MessageState(
      status: status ?? this.status,
      messages: messages ?? this.messages,
      nextCursor: nextCursor ?? this.nextCursor,
      hasMore: hasMore ?? this.hasMore,
      error: error,
      sendingMessageId: sendingMessageId,
    );
  }

  @override
  List<Object?> get props => [status, messages, nextCursor, hasMore, error, sendingMessageId];
}
