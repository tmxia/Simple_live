class LiveReplayItem {
  final String id;
  final String title;
  final String cover;
  final String author;
  final String duration;
  final String date;

  LiveReplayItem({
    required this.id,
    required this.title,
    required this.cover,
    required this.author,
    required this.duration,
    required this.date,
  });
}

class LiveReplayResult {
  final List<LiveReplayItem> items;
  final bool hasMore;

  LiveReplayResult({required this.items, required this.hasMore});
}
