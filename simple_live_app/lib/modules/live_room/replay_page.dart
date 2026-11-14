import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/widgets/net_image.dart';
import 'package:simple_live_core/simple_live_core.dart';

class ReplayPage extends StatefulWidget {
  final String roomId;
  final Site site;

  const ReplayPage({Key? key, required this.roomId, required this.site}) : super(key: key);

  @override
  State<ReplayPage> createState() => _ReplayPageState();
}

class _ReplayPageState extends State<ReplayPage> {
  final ScrollController _scrollController = ScrollController();
  List<LiveReplayItem> items = [];
  bool isLoading = true;
  bool hasMore = true;
  int page = 1;
  String errorMsg = "";

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
    setState(() {
      isLoading = true;
      errorMsg = "";
    });
    Log.logPrint("[回放] 开始拉取数据，Room: ${widget.roomId}, Page: $page");
    
    try {
      var res = await widget.site.liveSite.getReplays(roomId: widget.roomId, page: page);
      Log.logPrint("[回放] 拉取成功，数据量: ${res.items.length}");
      if (!mounted) return;
      setState(() {
        items.addAll(res.items);
        hasMore = res.hasMore;
        if (hasMore) page++;
        isLoading = false;
      });
    } catch (e) {
      Log.logPrint("[回放] 拉取失败，错误: $e");
      if (!mounted) return;
      setState(() {
        isLoading = false;
        errorMsg = e.toString();
      });
    }
  }

  Future<void> _playReplay(LiveReplayItem item) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      var qualities = await widget.site.liveSite.getReplayQualities(videoId: item.id);
      if (mounted) Navigator.of(context).pop(); // 关闭 Loading
      
      if (qualities.isNotEmpty) {
        var url = qualities.first.data["url"].toString();
        Log.logPrint("[回放] 获取到播放地址，返回直播间: $url");
        // 返回上一页并携带播放地址
        Navigator.of(context).pop(url);
      } else {
        _showMsg("未获取到播放地址");
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop(); // 关闭 Loading
      _showMsg("获取播放地址失败: $e");
    }
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("历史回放"),
        centerTitle: true,
      ),
      body: items.isEmpty && isLoading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Text(
                      errorMsg.isNotEmpty ? "加载失败:\n$errorMsg" : "暂无回放记录",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ),
                )
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
    );
  }
}
