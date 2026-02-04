import 'package:equatable/equatable.dart';

import '../../../core/models/models.dart';

enum ChannelStatus { initial, loading, success, failure }

class ChannelState extends Equatable {
  final ChannelStatus status;
  final List<ChannelModel> channels;
  final ChannelModel? selectedChannel;
  final List<ChannelMember> members;
  final String? error;

  const ChannelState({
    this.status = ChannelStatus.initial,
    this.channels = const [],
    this.selectedChannel,
    this.members = const [],
    this.error,
  });

  ChannelState copyWith({
    ChannelStatus? status,
    List<ChannelModel>? channels,
    ChannelModel? selectedChannel,
    List<ChannelMember>? members,
    String? error,
  }) {
    return ChannelState(
      status: status ?? this.status,
      channels: channels ?? this.channels,
      selectedChannel: selectedChannel ?? this.selectedChannel,
      members: members ?? this.members,
      error: error,
    );
  }

  @override
  List<Object?> get props => [status, channels, selectedChannel, members, error];
}
