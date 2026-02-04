import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_client.dart';
import '../../../core/models/models.dart';
import '../data/workspace_repository.dart';
import 'workspace_state.dart';

class WorkspaceCubit extends Cubit<WorkspaceState> {
  WorkspaceCubit() : super(const WorkspaceState());

  final WorkspaceRepository _repository = WorkspaceRepository();

  Future<void> loadWorkspaces() async {
    emit(state.copyWith(status: WorkspaceStatus.loading));
    try {
      final workspaces = await _repository.list();
      emit(state.copyWith(
        status: WorkspaceStatus.success,
        workspaces: workspaces,
      ));
    } on ApiException catch (e) {
      emit(state.copyWith(status: WorkspaceStatus.failure, error: e.message));
    } catch (e) {
      emit(state.copyWith(status: WorkspaceStatus.failure, error: 'Không thể tải danh sách workspace'));
    }
  }

  Future<void> createWorkspace(String name, {String? slug}) async {
    try {
      final workspace = await _repository.create(name, slug: slug);
      emit(state.copyWith(
        workspaces: [...state.workspaces, workspace],
      ));
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
    } catch (e) {
      emit(state.copyWith(error: 'Không thể tạo workspace'));
    }
  }

  Future<void> updateWorkspace(String workspaceId, {String? name, String? slug}) async {
    try {
      final workspace = await _repository.update(workspaceId, name: name, slug: slug);
      final updated = state.workspaces.map((w) => w.id == workspaceId ? workspace : w).toList();
      emit(state.copyWith(workspaces: updated));
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
    } catch (e) {
      emit(state.copyWith(error: 'Không thể cập nhật workspace'));
    }
  }

  Future<void> deleteWorkspace(String workspaceId) async {
    try {
      await _repository.delete(workspaceId);
      final updated = state.workspaces.where((w) => w.id != workspaceId).toList();
      emit(state.copyWith(workspaces: updated));
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
    } catch (e) {
      emit(state.copyWith(error: 'Không thể xóa workspace'));
    }
  }

  void selectWorkspace(WorkspaceModel workspace) {
    emit(state.copyWith(selectedWorkspace: workspace));
  }

  // Members management
  Future<void> loadMembers(String workspaceId) async {
    emit(state.copyWith(status: WorkspaceStatus.loading));
    try {
      final members = await _repository.getMembers(workspaceId);
      emit(state.copyWith(
        status: WorkspaceStatus.success,
        members: members,
      ));
    } on ApiException catch (e) {
      emit(state.copyWith(status: WorkspaceStatus.failure, error: e.message));
    } catch (e) {
      emit(state.copyWith(status: WorkspaceStatus.failure, error: 'Không thể tải danh sách thành viên'));
    }
  }

  Future<bool> inviteMember(String workspaceId, String email, {String role = 'member'}) async {
    try {
      await _repository.inviteMember(workspaceId, email, role: role);
      await loadMembers(workspaceId);
      return true;
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
      return false;
    } catch (e) {
      emit(state.copyWith(error: 'Không thể gửi lời mời'));
      return false;
    }
  }

  Future<bool> removeMember(String workspaceId, String userId) async {
    try {
      await _repository.removeMember(workspaceId, userId);
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

  Future<bool> updateMemberRole(String workspaceId, String userId, String role) async {
    try {
      await _repository.updateMemberRole(workspaceId, userId, role);
      final updated = state.members.map((m) {
        if (m.id == userId) {
          return WorkspaceMember(
            id: m.id,
            name: m.name,
            email: m.email,
            role: role,
            avatar: m.avatar,
            joinedAt: m.joinedAt,
          );
        }
        return m;
      }).toList();
      emit(state.copyWith(members: updated));
      return true;
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
      return false;
    } catch (e) {
      emit(state.copyWith(error: 'Không thể cập nhật vai trò'));
      return false;
    }
  }

  void clearError() {
    emit(state.copyWith(error: null));
  }
}
