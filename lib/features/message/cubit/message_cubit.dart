import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/network/api_client.dart';
import '../../../core/models/models.dart';
import '../data/message_repository.dart';
import 'message_state.dart';

class MessageCubit extends Cubit<MessageState> {
  MessageCubit() : super(const MessageState());

  final MessageRepository _repository = MessageRepository();
  String? _currentChannelId;

  String? get currentChannelId => _currentChannelId;

  Future<void> loadMessages(String channelId, {bool refresh = false}) async {
    _currentChannelId = channelId;
    
    if (refresh) {
      emit(state.copyWith(status: MessageStatus.loading, messages: []));
    } else if (state.status == MessageStatus.initial) {
      emit(state.copyWith(status: MessageStatus.loading));
    }

    try {
      final result = await _repository.getChannelMessages(channelId, limit: 30);
      emit(state.copyWith(
        status: MessageStatus.success,
        messages: result.items,
        nextCursor: result.nextCursor,
        hasMore: result.hasMore,
      ));
    } on ApiException catch (e) {
      emit(state.copyWith(status: MessageStatus.failure, error: e.message));
    } catch (e) {
      emit(state.copyWith(status: MessageStatus.failure, error: 'Không thể tải tin nhắn'));
    }
  }

  Future<void> loadMore(String channelId) async {
    if (!state.hasMore || state.nextCursor == null) return;
    
    try {
      final result = await _repository.getChannelMessages(
        channelId,
        limit: 30,
        cursor: state.nextCursor,
      );
      emit(state.copyWith(
        messages: [...state.messages, ...result.items],
        nextCursor: result.nextCursor,
        hasMore: result.hasMore,
      ));
    } catch (e) {
      // Silent fail for load more
    }
  }

  Future<bool> sendMessage(String channelId, String content, {String? parentId}) async {
    if (content.trim().isEmpty) return false;
    
    // Create temporary message for optimistic UI
    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    emit(state.copyWith(status: MessageStatus.sending, sendingMessageId: tempId));

    try {
      final message = await _repository.sendChannelMessage(
        channelId,
        content,
        parentId: parentId,
      );
      
      // Add the real message to the list
      emit(state.copyWith(
        status: MessageStatus.success,
        messages: [message, ...state.messages],
        sendingMessageId: null,
      ));
      return true;
    } on ApiException catch (e) {
      emit(state.copyWith(
        status: MessageStatus.success,
        error: e.message,
        sendingMessageId: null,
      ));
      return false;
    } catch (e) {
      emit(state.copyWith(
        status: MessageStatus.success,
        error: 'Không thể gửi tin nhắn',
        sendingMessageId: null,
      ));
      return false;
    }
  }

  Future<bool> editMessage(String messageId, String content) async {
    try {
      final message = await _repository.editMessage(messageId, content);
      final updated = state.messages.map((m) => m.id == messageId ? message : m).toList();
      emit(state.copyWith(messages: updated));
      return true;
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
      return false;
    } catch (e) {
      emit(state.copyWith(error: 'Không thể sửa tin nhắn'));
      return false;
    }
  }

  Future<bool> deleteMessage(String messageId) async {
    try {
      await _repository.deleteMessage(messageId);
      final updated = state.messages.where((m) => m.id != messageId).toList();
      emit(state.copyWith(messages: updated));
      return true;
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
      return false;
    } catch (e) {
      emit(state.copyWith(error: 'Không thể xóa tin nhắn'));
      return false;
    }
  }

  Future<void> addReaction(String messageId, String emoji) async {
    try {
      await _repository.addReaction(messageId, emoji);
      // Refresh messages to get updated reactions
      if (_currentChannelId != null) {
        await loadMessages(_currentChannelId!, refresh: true);
      }
    } catch (e) {
      emit(state.copyWith(error: 'Không thể thêm reaction'));
    }
  }

  Future<void> removeReaction(String messageId, String emoji) async {
    try {
      await _repository.removeReaction(messageId, emoji);
      if (_currentChannelId != null) {
        await loadMessages(_currentChannelId!, refresh: true);
      }
    } catch (e) {
      emit(state.copyWith(error: 'Không thể xóa reaction'));
    }
  }

  // Add message from WebSocket
  void addMessageFromSocket(MessageModel message) {
    if (!state.messages.any((m) => m.id == message.id)) {
      emit(state.copyWith(messages: [message, ...state.messages]));
    }
  }

  // Update message from WebSocket
  void updateMessageFromSocket(MessageModel message) {
    final updated = state.messages.map((m) => m.id == message.id ? message : m).toList();
    emit(state.copyWith(messages: updated));
  }

  // Delete message from WebSocket
  void deleteMessageFromSocket(String messageId) {
    final updated = state.messages.where((m) => m.id != messageId).toList();
    emit(state.copyWith(messages: updated));
  }

  void clearError() {
    emit(state.copyWith(error: null));
  }

  void reset() {
    _currentChannelId = null;
    emit(const MessageState());
  }
}
