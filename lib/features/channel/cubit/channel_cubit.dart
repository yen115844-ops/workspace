import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_client.dart';
import '../../../core/models/models.dart';
import '../data/channel_repository.dart';
import 'channel_state.dart';

class ChannelCubit extends Cubit<ChannelState> {
  ChannelCubit() : super(const ChannelState());

  final ChannelRepository _repository = ChannelRepository();

  Future<void> loadChannels(String workspaceId) async {
    emit(state.copyWith(status: ChannelStatus.loading));
    try {
      final channels = await _repository.listByWorkspace(workspaceId);
      emit(state.copyWith(
        status: ChannelStatus.success,
        channels: channels,
      ));
    } on ApiException catch (e) {
      emit(state.copyWith(status: ChannelStatus.failure, error: e.message));
    } catch (e) {
      emit(state.copyWith(status: ChannelStatus.failure, error: 'Không thể tải danh sách channel'));
    }
  }

  Future<void> createChannel(String workspaceId, String name, {String type = 'public', String? description}) async {
    try {
      final channel = await _repository.create(workspaceId, name, type: type, description: description);
      emit(state.copyWith(
        channels: [...state.channels, channel],
      ));
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
    } catch (e) {
      emit(state.copyWith(error: 'Không thể tạo channel'));
    }
  }

  Future<void> updateChannel(String channelId, {String? name, String? description, String? type}) async {
    try {
      final channel = await _repository.update(channelId, name: name, description: description, type: type);
      final updated = state.channels.map((c) => c.id == channelId ? channel : c).toList();
      emit(state.copyWith(channels: updated));
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
    } catch (e) {
      emit(state.copyWith(error: 'Không thể cập nhật channel'));
    }
  }

  Future<void> deleteChannel(String channelId) async {
    try {
      await _repository.delete(channelId);
      final updated = state.channels.where((c) => c.id != channelId).toList();
      emit(state.copyWith(channels: updated));
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
    } catch (e) {
      emit(state.copyWith(error: 'Không thể xóa channel'));
    }
  }

  void selectChannel(ChannelModel channel) {
    emit(state.copyWith(selectedChannel: channel));
  }

  Future<void> joinChannel(String channelId) async {
    try {
      await _repository.join(channelId);
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
    } catch (e) {
      emit(state.copyWith(error: 'Không thể tham gia channel'));
    }
  }

  Future<void> leaveChannel(String channelId) async {
    try {
      await _repository.leave(channelId);
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
    } catch (e) {
      emit(state.copyWith(error: 'Không thể rời khỏi channel'));
    }
  }

  // Members management
  Future<void> loadMembers(String channelId) async {
    emit(state.copyWith(status: ChannelStatus.loading));
    try {
      final members = await _repository.getMembers(channelId);
      emit(state.copyWith(
        status: ChannelStatus.success,
        members: members,
      ));
    } on ApiException catch (e) {
      emit(state.copyWith(status: ChannelStatus.failure, error: e.message));
    } catch (e) {
      emit(state.copyWith(status: ChannelStatus.failure, error: 'Không thể tải danh sách thành viên'));
    }
  }

  Future<bool> addMember(String channelId, String userId) async {
    try {
      await _repository.addMember(channelId, userId);
      await loadMembers(channelId);
      return true;
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
      return false;
    } catch (e) {
      emit(state.copyWith(error: 'Không thể thêm thành viên'));
      return false;
    }
  }

  Future<bool> removeMember(String channelId, String userId) async {
    try {
      await _repository.removeMember(channelId, userId);
      final updated = state.members.where((m) => m.id != userId).toList();
      emit(state.copyWith(members: updated));
      return true;
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
      return false;
    } catch (e) {
      emit(state.copyWith(error: 'Không thể xóa thành viên'));
      return false;
    }
  }

  void clearError() {
    emit(state.copyWith(error: null));
  }
}
