import 'package:PiliPlus/models_new/fav/fav_folder/list.dart';
import 'package:flutter/material.dart';

/// 收藏夹选择对话框
/// 
/// 用于在长按视频卡片收藏时选择要添加到的收藏夹
class FavSelectDialog extends StatefulWidget {
  const FavSelectDialog({
    super.key,
    required this.folders,
    required this.initialSelected,
  });

  final List<FavFolderInfo> folders;
  final Set<int> initialSelected; // 已收藏的文件夹ID

  @override
  State<FavSelectDialog> createState() => _FavSelectDialogState();

  /// 显示收藏夹选择对话框
  /// 
  /// 返回 ({add: [], del: []}) 或 null（用户取消）
  /// - add: 需要添加的收藏夹ID列表
  /// - del: 需要删除的收藏夹ID列表
  static Future<({List<int> add, List<int> del})?> show(
    BuildContext context,
    List<FavFolderInfo> folders,
    Set<int> initialSelected,
  ) {
    return showDialog<({List<int> add, List<int> del})>(
      context: context,
      builder: (context) => FavSelectDialog(
        folders: folders,
        initialSelected: initialSelected,
      ),
    );
  }
}

class _FavSelectDialogState extends State<FavSelectDialog> {
  late final Set<int> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.initialSelected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return AlertDialog(
      title: const Text('选择收藏夹'),
      content: SizedBox(
        width: double.maxFinite,
        child: widget.folders.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('暂无收藏夹'),
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: widget.folders.length,
                itemBuilder: (context, index) {
                  final folder = widget.folders[index];
                  final isSelected = _selected.contains(folder.id);
                  
                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selected.add(folder.id);
                        } else {
                          _selected.remove(folder.id);
                        }
                      });
                    },
                    title: Text(
                      folder.title,
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      '${folder.mediaCount} 个内容',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            '取消',
            style: TextStyle(color: theme.colorScheme.outline),
          ),
        ),
        TextButton(
          onPressed: () {
            // 计算需要添加和删除的ID
            final add = _selected.difference(widget.initialSelected).toList();
            final del = widget.initialSelected.difference(_selected).toList();
            Navigator.of(context).pop((add: add, del: del));
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}
