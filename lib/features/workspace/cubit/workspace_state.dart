import 'package:equatable/equatable.dart';

import '../../../core/models/models.dart';

enum WorkspaceStatus { initial, loading, success, failure }

class WorkspaceState extends Equatable {
  final WorkspaceStatus status;
  final List<WorkspaceModel> workspaces;
  final WorkspaceModel? selectedWorkspace;
  final List<WorkspaceMember> members;
  final String? error;

  const WorkspaceState({
    this.status = WorkspaceStatus.initial,
    this.workspaces = const [],
    this.selectedWorkspace,
    this.members = const [],
    this.error,
  });

  WorkspaceState copyWith({
    WorkspaceStatus? status,
    List<WorkspaceModel>? workspaces,
    WorkspaceModel? selectedWorkspace,
    List<WorkspaceMember>? members,
    String? error,
  }) {
    return WorkspaceState(
      status: status ?? this.status,
      workspaces: workspaces ?? this.workspaces,
      selectedWorkspace: selectedWorkspace ?? this.selectedWorkspace,
      members: members ?? this.members,
      error: error,
    );
  }

  @override
  List<Object?> get props => [status, workspaces, selectedWorkspace, members, error];
}
