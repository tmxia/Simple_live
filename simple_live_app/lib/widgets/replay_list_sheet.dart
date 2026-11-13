import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/widgets/net_image.dart';
import 'package:simple_live_core/simple_live_core.dart';

class ReplayListSheet extends StatefulWidget {
  final String roomId;
  final ReplaySite site;
  final Function(String url) onPlay;

  const ReplayListSheet({Key? key, required this.roomId, required this.site, required this.onPlay}) : super(key: key);

  @override
  State<ReplayListSheet> createState() => _ReplayListSheetState();
}

class _ReplayListSheetState extends State<ReplayListSheet> {
  final ScrollController _scrollController = ScrollController();
  List<LiveReplayItem> items = [];
  bool isLoading = true;
  bool hasMore = true;
  int page = 1;

  @override
  void initState() {
    super.initState();
    _loadData();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 100) {
        _loadData();
      }
    });
  }

  Future<void> _loadData() async {
    if (!hasMore || !mounted) return;
    setState(() => isLoading = true);
    try {
      var res = await widget.site.getReplays(roomId: widget.roomId, page: page);
      setState(() {
        items.addAll(res.items);
        hasMore = res.hasMore;
        if (hasMore) page++;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  Future<void> _playReplay(LiveReplayItem item) async {
    // 弹出原生 Loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      var qualities = await widget.site.getReplayQualities(videoId: item.id);
      if (mounted) Navigator.of(context).pop(); // 关闭 Loading
      
      if (qualities.isNotEmpty) {
        var url = qualities.first.data["url"].toString();
        if (mounted) Navigator.of(context).pop(); // 关闭底部弹窗
        widget.onPlay(url);
      } else {
        _showMsg("未获取到播放地址");
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop(); // 关闭 Loading
      _showMsg("获取播放地址失败");
    }
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Padding(
            padding: AppStyle.edgeInsetsA12,
            child: const Text("历史回放", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 1),
          Expanded(
            child: items.isEmpty && isLoading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? const Center(child: Text("暂无回放"))
                    : ListView.separated(
                        controller: _scrollController,
                        padding: AppStyle.edgeInsetsA12,
                        itemCount: items.length + (hasMore ? 1 : 0),
                        separatorBuilder: (_, i) => AppStyle.vGap12,
                        itemBuilder: (context, index) {
                          if (index == items.length) {
                            return const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()));
                          }
                          var item = items[index];
                          return InkWell(
                            onTap: () => _playReplay(item),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: AppStyle.radius8,
                                  child: NetImage(
                                    item.cover,
                                    width: 120,
                                    height: 68,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                AppStyle.hGap12,
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                      ),
                                      AppStyle.vGap4,
                                      Text(
                                        "${item.date}  ${item.duration}",
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
