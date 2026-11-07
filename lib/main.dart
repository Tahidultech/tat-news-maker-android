import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:webfeed_revised/webfeed_revised.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:webview_windows/webview_windows.dart' as windows;
import 'dart:async';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:screenshot/screenshot.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'app_browser_controller.dart';

// গ্লোবাল ভেরিয়েবল
Stream<String>? _globalBroadcastStream;
StreamSubscription<String>? _currentSubscription;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NewsMakerApp());
}

String? _headlineWithoutSource(String? title, String? source) {
  if (title == null) return null;
  final normalizedTitle = title.trim();
  final normalizedSource = source?.trim();
  if (normalizedTitle.isEmpty ||
      normalizedSource == null ||
      normalizedSource.isEmpty) {
    return normalizedTitle;
  }

  final sourceSuffix = ' - $normalizedSource';
  if (normalizedTitle.endsWith(sourceSuffix)) {
    return normalizedTitle
        .substring(0, normalizedTitle.length - sourceSuffix.length)
        .trimRight();
  }
  return normalizedTitle;
}

String _headlineWithSource(String? title, String? source) {
  final headline = title?.trim() ?? '';
  final portalName = source?.trim();
  if (headline.isEmpty ||
      portalName == null ||
      portalName.isEmpty ||
      headline.toLowerCase().endsWith(' - ${portalName.toLowerCase()}')) {
    return headline;
  }
  return '$headline - $portalName';
}

class NewsMakerApp extends StatelessWidget {
  const NewsMakerApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // গ্লোবাল ডার্ক থিম কনফিগারেশন
      // ThemeData থেকে const সরিয়ে ফেলুন কারণ ভেতরে ডাইনামিক কালার থাকতে পারে
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF448AFF),
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        // এখান থেকে const সরিয়ে ফেলুন
        tabBarTheme: TabBarThemeData(
          labelColor: const Color(0xFF448AFF),
          unselectedLabelColor: Colors.white38,
          indicatorColor: const Color(0xFF448AFF),
        ),
        useMaterial3: true,
      ),
      home: const MainHomeScreen(),
    );
  }
}

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});
  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  final _webviewController = AppBrowserController();
  bool _isWebviewInitialized = false;

  @override
  void initState() {
    super.initState();
    _initBackgroundBrowser();
  }

  Future<void> _initBackgroundBrowser() async {
    try {
      await _webviewController.initialize();
      await _webviewController.setPopupWindowPolicy(
        windows.WebviewPopupWindowPolicy.deny,
      );
      _globalBroadcastStream = _webviewController.url.asBroadcastStream();
      if (mounted) setState(() => _isWebviewInitialized = true);
      debugPrint('Webview initialized successfully');
    } catch (e) {
      debugPrint('Webview Error: $e');
      if (mounted) setState(() => _isWebviewInitialized = false);
    }
  }

  @override
  void dispose() {
    unawaited(_webviewController.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('TAT News Card Solutions'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Latest'),
              Tab(text: 'Search'),
              Tab(text: 'Via URL'),
              Tab(text: 'Manual'),
            ],
          ),
        ),
        body: Stack(
          children: [
            if (_isWebviewInitialized)
              Positioned(
                left: _webviewController.isWindows ? -9999 : -1,
                top: _webviewController.isWindows ? -9999 : -1,
                width: _webviewController.isWindows ? 800 : 1,
                height: _webviewController.isWindows ? 600 : 1,
                child: IgnorePointer(child: _webviewController.buildView()),
              ),
            TabBarView(
              children: [
                NewsListScreen(
                    url: 'https://news.google.com/rss?hl=bn&gl=BD&ceid=BD:bn',
                    browser: _webviewController),
                SearchTab(browser: _webviewController),
                ViaUrlTab(browser: _webviewController),

                // এই নিচের লাইনটি পরিবর্তন করুন:
                const NewsCardEditor(initialTitle: "এখানে শিরোনাম লিখুন"),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SearchTab extends StatefulWidget {
  final dynamic browser;
  const SearchTab({super.key, required this.browser});

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedTime = 'all';
  String? _generatedUrl;

  final Map<String, String> _timeFilters = {
    'Recent': 'all',
    '1 Hour': '1h',
    '24 Hour': '1d',
    '7 Days': '7d',
  };

  void _handleSearch() {
    String query = _searchController.text.trim();
    if (query.isEmpty) return;

    // RSS Search URL জেনারেট
    String url =
        "https://news.google.com/rss/search?q=${Uri.encodeComponent(query)}";
    if (_selectedTime != 'all') {
      url += "+when:${_selectedTime}";
    }
    url += "&hl=bn&gl=BD&ceid=BD:bn";

    setState(() {
      _generatedUrl = url;
    });

    FocusScope.of(context).unfocus(); // কিবোর্ড হাইড করার জন্য
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // এক লাইনে সার্চ বক্স, কম্বো বক্স এবং বাটন
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 15.0),
          child: Row(
            children: [
              // ১. টেক্সট বক্স (বেশি জায়গা নিবে)
              Expanded(
                flex: 6,
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF2B2B2B),
                    hintText: "সার্চ...",
                    hintStyle: const TextStyle(color: Colors.white38),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 15),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _handleSearch(),
                ),
              ),
              const SizedBox(width: 5),

              // ২. কম্বো বক্স (টাইম ফিল্টার)
              Expanded(
                flex: 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2B2B2B),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedTime,
                      dropdownColor: const Color(0xFF2B2B2B),
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down,
                          color: Colors.white38),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      items: _timeFilters.entries.map((entry) {
                        return DropdownMenuItem(
                          value: entry.value,
                          child: Text(entry.key),
                        );
                      }).toList(),
                      onChanged: (val) => setState(() => _selectedTime = val!),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 5),

              // ৩. সার্চ বাটন (আইকন বাটন ছোট জায়গার জন্য)
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _handleSearch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF448AFF),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child:
                      const Icon(Icons.search, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ),

        const Divider(color: Colors.white10, height: 1),

        // নিউজ লিস্ট অংশ
        Expanded(
          child: _generatedUrl == null
              ? const Center(
                  child: Text(
                    "খবর খুঁজতে সার্চ করুন",
                    style: TextStyle(color: Colors.white24, fontSize: 13),
                  ),
                )
              : NewsListScreen(
                  key: ValueKey(_generatedUrl),
                  url: _generatedUrl!,
                  browser: widget.browser,
                ),
        ),
      ],
    );
  }
}

// তারিখ ফরম্যাট ফাংশন
String formatDateTime(DateTime? date) {
  if (date == null) return "সময় পাওয়া যায়নি";
  return DateFormat('dd MMM, hh:mm a').format(date.toLocal());
}

// রিডাইরেক্ট লজিক
Future<void> resolveAndNavigate(
  BuildContext context,
  AppBrowserController browser,
  String inputUrl, {
  String? articleTitle,
}) async {
  debugPrint('resolveAndNavigate called with URL: $inputUrl');
  await _currentSubscription?.cancel();
  if (!context.mounted) return;

  var dialogOpen = true;
  final dialogFuture = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const Center(
      child: CircularProgressIndicator(color: Color(0xFF448AFF)),
    ),
  );
  unawaited(dialogFuture.whenComplete(() => dialogOpen = false));

  void closeProgressDialog() {
    if (dialogOpen && context.mounted) {
      dialogOpen = false;
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void showResolutionError(Object error) {
    debugPrint('Error in resolveAndNavigate: $error');
    closeProgressDialog();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("নিউজ লিংকটি খোলা যায়নি।")),
      );
    }
  }

  Timer? navigationTimeout;
  try {
    final trimmedUrl = inputUrl.trim();
    final parsedUrl = Uri.tryParse(trimmedUrl);
    final url = parsedUrl != null &&
            (parsedUrl.scheme == 'http' || parsedUrl.scheme == 'https')
        ? parsedUrl
        : Uri.tryParse('https://$trimmedUrl');
    if (url == null || url.host.isEmpty) {
      throw const FormatException('A valid news URL is required.');
    }

    final urlStream = _globalBroadcastStream;
    if (urlStream == null) {
      throw StateError('The in-app browser is not initialized.');
    }

    late final StreamSubscription<String> subscription;
    subscription = urlStream.listen(
      (changedUrl) async {
        final changedUri = Uri.tryParse(changedUrl);
        if (changedUri == null ||
            (changedUri.scheme != 'http' && changedUri.scheme != 'https') ||
            changedUri.host.contains('news.google.com')) {
          return;
        }

        navigationTimeout?.cancel();
        await subscription.cancel();
        if (identical(_currentSubscription, subscription)) {
          _currentSubscription = null;
        }

        try {
          final response =
              await http.get(changedUri).timeout(const Duration(seconds: 30));
          if (response.statusCode < 200 || response.statusCode >= 400) {
            throw HttpException(
              'The article server returned ${response.statusCode}.',
              uri: changedUri,
            );
          }

          final document = html_parser.parse(response.body);
          final title = document
                  .querySelector('meta[property="og:title"]')
                  ?.attributes['content'] ??
              document.querySelector('title')?.text ??
              '';
          final imageUrl = document
              .querySelector('meta[property="og:image"]')
              ?.attributes['content'];

          if (context.mounted) {
            closeProgressDialog();
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => NewsCardEditor(
                  initialTitle: articleTitle ?? title,
                  initialImageUrl: imageUrl,
                ),
              ),
            );
          }
        } on Exception catch (error) {
          showResolutionError(error);
        }
      },
      onError: (Object error) => showResolutionError(error),
    );
    _currentSubscription = subscription;
    navigationTimeout = Timer(const Duration(seconds: 30), () async {
      await subscription.cancel();
      if (identical(_currentSubscription, subscription)) {
        _currentSubscription = null;
      }
      showResolutionError(
        TimeoutException('The article redirect did not complete.'),
      );
    });

    debugPrint('Loading URL: $url');
    await browser.loadUrl(url.toString());
  } catch (e) {
    await _currentSubscription?.cancel();
    _currentSubscription = null;
    showResolutionError(e);
  }
}

class NewsListScreen extends StatefulWidget {
  final String url;
  final String? title;
  final AppBrowserController browser;
  const NewsListScreen(
      {super.key, required this.url, this.title, required this.browser});
  @override
  State<NewsListScreen> createState() => _NewsListScreenState();
}

class _NewsListScreenState extends State<NewsListScreen> {
  List<RssItem>? _items;
  String? _loadError;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRss();
  }

  Future<void> _fetchRss() async {
    try {
      final response = await http
          .get(Uri.parse(widget.url))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'The RSS server returned ${response.statusCode}.',
          uri: Uri.parse(widget.url),
        );
      }
      if (mounted) {
        var feed = RssFeed.parse(response.body);
        List<RssItem> sortedItems = feed.items ?? [];
        sortedItems.sort((a, b) => (b.pubDate ?? DateTime(2000))
            .compareTo(a.pubDate ?? DateTime(2000)));
        setState(() {
          _items = sortedItems;
          _loadError = null;
          _isLoading = false;
        });
      }
    } on Exception catch (error) {
      debugPrint('Failed to load RSS feed ${widget.url}: $error');
      if (mounted) {
        setState(() {
          _loadError = 'সংবাদ তালিকা লোড করা যায়নি।';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.title != null ? AppBar(title: Text(widget.title!)) : null,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF448AFF)))
          : _loadError != null
              ? Center(
                  child: Text(
                    _loadError!,
                    style: const TextStyle(color: Colors.white70),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  itemCount: _items?.length ?? 0,
                  separatorBuilder: (context, index) =>
                      const Divider(color: Colors.white10, height: 1),
                  itemBuilder: (context, index) {
                    final item = _items![index];
                    final itemUrl = item.link;
                    return ListTile(
                      tileColor: const Color(0xFF1A1A1A),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      title: Text(
                          _headlineWithSource(item.title, item.source?.value),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              fontSize: 14)),
                      subtitle: Text(formatDateTime(item.pubDate),
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11)),
                      trailing: const Icon(Icons.chevron_right,
                          color: Colors.white24),
                      onTap: itemUrl == null
                          ? null
                          : () => resolveAndNavigate(
                                context,
                                widget.browser,
                                itemUrl,
                                articleTitle: _headlineWithoutSource(
                                    item.title, item.source?.value),
                              ),
                    );
                  },
                ),
    );
  }
}

class PortalListTab extends StatelessWidget {
  final String type;
  final AppBrowserController browser;
  const PortalListTab({super.key, required this.type, required this.browser});
  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> portals = type == 'direct'
        ? [
            {
              'name': 'প্রথম আলো',
              'url': 'https://rss.app/feeds/Z1VF2jqbskYfrkT0.xml'
            }
          ]
        : [
            {
              'name': 'Google News',
              'url': 'https://news.google.com/rss?hl=bn&gl=BD&ceid=BD:bn'
            }
          ];

    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: portals.length,
      itemBuilder: (context, index) => Card(
        color: const Color(0xFF2B2B2B),
        child: ListTile(
          title: Text(portals[index]['name']!,
              style: const TextStyle(color: Colors.white)),
          trailing: const Icon(Icons.arrow_forward_ios,
              size: 16, color: Colors.white54),
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (c) => NewsListScreen(
                      url: portals[index]['url']!,
                      title: portals[index]['name'],
                      browser: browser))),
        ),
      ),
    );
  }
}

class ViaUrlTab extends StatelessWidget {
  final AppBrowserController browser;
  const ViaUrlTab({super.key, required this.browser});
  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController();
    return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF2B2B2B),
                  hintText: "URL পেস্ট করুন",
                  hintStyle: const TextStyle(color: Colors.white38),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none))),
          const SizedBox(height: 15),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF448AFF),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 45),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () =>
                  resolveAndNavigate(context, browser, controller.text.trim()),
              child: const Text("নিউজ রিসিভ করুন",
                  style: TextStyle(fontWeight: FontWeight.bold))),
        ]));
  }
}

class NewsCardEditor extends StatefulWidget {
  final String initialTitle;
  final String? initialImageUrl;
  const NewsCardEditor(
      {super.key, required this.initialTitle, this.initialImageUrl});

  @override
  State<NewsCardEditor> createState() => _NewsCardEditorState();
}

class _NewsCardEditorState extends State<NewsCardEditor> {
  final ScreenshotController _screenshotController = ScreenshotController();
  late TextEditingController _titleController;

  ImageProvider? _displayImage;
  Color _textColor = Colors.white;
  String _selectedFontFamily = 'SolaimanLipi';
  String _selectedWeight = 'Bold';
  String _selectedSize = '80';
  double _lineHeight = 1.2;
  double _textTop = 780.0;
  double _textLeft = 40.0;

  // Per-selection coloring: list of maps with start/end char indices and color
  List<Map<String, dynamic>> _coloredRanges = [];
  int? _selectionStart;
  int? _selectionEnd;
  final GlobalKey _titleBoxKey = GlobalKey();
  bool _isSelectMode = false;

  final List<Color> _colorPalette = [
    Colors.white,
    Colors.black,
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.yellow,
    Colors.purple,
    Colors.orange,
    Colors.pink,
    Colors.teal,
    Colors.brown,
    Colors.grey,
    Colors.cyan,
    Colors.lime,
    Colors.indigo,
    Colors.amber,
  ];

  // Image position and scale variables
  Offset _imageOffset = Offset.zero;
  double _imageScale = 1.0;
  Offset _lastFocalPoint = Offset.zero;
  double _lastScale = 1.0;

  // Bottom elements customization variables
  double _dateTop = 8.0;
  double _dateRight = 24.0;
  double _dateFontSize = 28.0;
  Color _dateColor = Colors.white;

  double _dayTop = 40.0;
  double _dayRight = 24.0;
  double _dayFontSize = 28.0;
  Color _dayColor = Colors.white;

  double _commentTop = 5.0;
  double _commentLeft = 400.0;
  double _commentFontSize = 28.0;
  Color _commentColor = Colors.white;

  bool _showComment = false;
  bool _showDate = true;
  bool _showDay = true;
  bool _showCollected = false;
  bool _showFilePhoto = false;
  String _selectedCardFormat = 'Card 1';

  String get _cardFrameAsset => _selectedCardFormat == 'Card 2'
      ? 'assets/system_file/webmeta_extractor_2.dll'
      : 'assets/system_file/webmeta_extractor.dll';

  Map<String, dynamic> _defaultCardTextSettings() => {
        'textColor': Colors.white.toARGB32(),
        'selectedFontFamily': 'SolaimanLipi',
        'selectedWeight': 'Bold',
        'selectedSize': '80',
        'lineHeight': 1.2,
        'textTop': 780.0,
        'textLeft': 40.0,
        'coloredRanges': <Map<String, dynamic>>[],
        'dateTop': 8.0,
        'dateRight': 24.0,
        'dateFontSize': 28.0,
        'dateColor': Colors.white.toARGB32(),
        'dayTop': 40.0,
        'dayRight': 24.0,
        'dayFontSize': 28.0,
        'dayColor': Colors.white.toARGB32(),
        'commentTop': 5.0,
        'commentLeft': 400.0,
        'commentFontSize': 28.0,
        'commentColor': Colors.white.toARGB32(),
        'showComment': false,
        'showDate': true,
        'showDay': true,
        'showCollected': false,
        'showFilePhoto': false,
      };

  Map<String, dynamic> _captureCardTextSettings() => {
        'textColor': _textColor.toARGB32(),
        'selectedFontFamily': _selectedFontFamily,
        'selectedWeight': _selectedWeight,
        'selectedSize': _selectedSize,
        'lineHeight': _lineHeight,
        'textTop': _textTop,
        'textLeft': _textLeft,
        'coloredRanges': _coloredRanges
            .map((range) => {
                  'start': range['start'],
                  'end': range['end'],
                  'color': (range['color'] as Color).toARGB32(),
                })
            .toList(),
        'dateTop': _dateTop,
        'dateRight': _dateRight,
        'dateFontSize': _dateFontSize,
        'dateColor': _dateColor.toARGB32(),
        'dayTop': _dayTop,
        'dayRight': _dayRight,
        'dayFontSize': _dayFontSize,
        'dayColor': _dayColor.toARGB32(),
        'commentTop': _commentTop,
        'commentLeft': _commentLeft,
        'commentFontSize': _commentFontSize,
        'commentColor': _commentColor.toARGB32(),
        'showComment': _showComment,
        'showDate': _showDate,
        'showDay': _showDay,
        'showCollected': _showCollected,
        'showFilePhoto': _showFilePhoto,
      };

  void _applyCardTextSettings(Map<String, dynamic> settings) {
    _textColor = _savedColor(settings, 'textColor', _textColor);
    _selectedFontFamily =
        _savedString(settings, 'selectedFontFamily', _selectedFontFamily);
    _selectedWeight = _savedString(settings, 'selectedWeight', _selectedWeight);
    _selectedSize = _savedString(settings, 'selectedSize', _selectedSize);
    _lineHeight = _savedDouble(settings, 'lineHeight', _lineHeight);
    _textTop = _savedDouble(settings, 'textTop', _textTop);
    _textLeft = _savedDouble(settings, 'textLeft', _textLeft);
    _coloredRanges = _savedColoredRanges(settings['coloredRanges']);
    _dateTop = _savedDouble(settings, 'dateTop', _dateTop);
    _dateRight = _savedDouble(settings, 'dateRight', _dateRight);
    _dateFontSize = _savedDouble(settings, 'dateFontSize', _dateFontSize);
    _dateColor = _savedColor(settings, 'dateColor', _dateColor);
    _dayTop = _savedDouble(settings, 'dayTop', _dayTop);
    _dayRight = _savedDouble(settings, 'dayRight', _dayRight);
    _dayFontSize = _savedDouble(settings, 'dayFontSize', _dayFontSize);
    _dayColor = _savedColor(settings, 'dayColor', _dayColor);
    _commentTop = _savedDouble(settings, 'commentTop', _commentTop);
    _commentLeft = _savedDouble(settings, 'commentLeft', _commentLeft);
    _commentFontSize =
        _savedDouble(settings, 'commentFontSize', _commentFontSize);
    _commentColor = _savedColor(settings, 'commentColor', _commentColor);
    _showComment = _savedBool(settings, 'showComment', _showComment);
    _showDate = _savedBool(settings, 'showDate', _showDate);
    _showDay = _savedBool(settings, 'showDay', _showDay);
    _showCollected = _savedBool(settings, 'showCollected', _showCollected);
    _showFilePhoto = _savedBool(settings, 'showFilePhoto', _showFilePhoto);
    _selectionStart = null;
    _selectionEnd = null;
  }

  void _switchCardFormat(String cardFormat) {
    if (cardFormat == _selectedCardFormat) return;
    setState(() {
      _cardTextSettings[_selectedCardFormat] = _captureCardTextSettings();
      _selectedCardFormat = cardFormat;
      _applyCardTextSettings(
        _cardTextSettings[cardFormat] ?? _defaultCardTextSettings(),
      );
    });
  }

  final Map<String, Map<String, dynamic>> _cardTextSettings = {};

  Timer? _settingsSaveTimer;
  Future<void> _settingsWriteQueue = Future<void>.value();
  bool _settingsLoaded = false;

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _scheduleSettingsSave();
  }

  void _scheduleSettingsSave() {
    if (!_settingsLoaded) return;
    _settingsSaveTimer?.cancel();
    _settingsSaveTimer = Timer(const Duration(milliseconds: 300), () {
      _queueSettingsSave();
    });
  }

  void _queueSettingsSave() {
    _cardTextSettings[_selectedCardFormat] = _captureCardTextSettings();
    final settingsJson = jsonEncode({
      'textColor': _textColor.toARGB32(),
      'selectedFontFamily': _selectedFontFamily,
      'selectedWeight': _selectedWeight,
      'selectedSize': _selectedSize,
      'lineHeight': _lineHeight,
      'textTop': _textTop,
      'textLeft': _textLeft,
      'coloredRanges': _coloredRanges
          .map((range) => {
                'start': range['start'],
                'end': range['end'],
                'color': (range['color'] as Color).toARGB32(),
              })
          .toList(),
      'dateTop': _dateTop,
      'dateRight': _dateRight,
      'dateFontSize': _dateFontSize,
      'dateColor': _dateColor.toARGB32(),
      'dayTop': _dayTop,
      'dayRight': _dayRight,
      'dayFontSize': _dayFontSize,
      'dayColor': _dayColor.toARGB32(),
      'commentTop': _commentTop,
      'commentLeft': _commentLeft,
      'commentFontSize': _commentFontSize,
      'commentColor': _commentColor.toARGB32(),
      'showComment': _showComment,
      'showDate': _showDate,
      'showDay': _showDay,
      'showCollected': _showCollected,
      'showFilePhoto': _showFilePhoto,
      'selectedCardFormat': _selectedCardFormat,
      'cardTextSettings': _cardTextSettings,
    });
    _settingsWriteQueue = _settingsWriteQueue.then((_) async {
      try {
        final directory = await getApplicationSupportDirectory();
        final file = File(
            '${directory.path}${Platform.pathSeparator}news_card_settings.json');
        await file.writeAsString(settingsJson, flush: true);
      } on FileSystemException catch (error) {
        debugPrint('Failed to save editor settings: $error');
      }
    });
  }

  Future<void> _loadEditorSettings() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final file = File(
          '${directory.path}${Platform.pathSeparator}news_card_settings.json');
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) {
          _textColor = _savedColor(decoded, 'textColor', _textColor);
          _selectedFontFamily =
              _savedString(decoded, 'selectedFontFamily', _selectedFontFamily);
          _selectedWeight =
              _savedString(decoded, 'selectedWeight', _selectedWeight);
          _selectedSize = _savedString(decoded, 'selectedSize', _selectedSize);
          _lineHeight = _savedDouble(decoded, 'lineHeight', _lineHeight);
          _textTop = _savedDouble(decoded, 'textTop', _textTop);
          _textLeft = _savedDouble(decoded, 'textLeft', _textLeft);
          _coloredRanges = _savedColoredRanges(decoded['coloredRanges']);
          _dateTop = _savedDouble(decoded, 'dateTop', _dateTop);
          _dateRight = _savedDouble(decoded, 'dateRight', _dateRight);
          _dateFontSize = _savedDouble(decoded, 'dateFontSize', _dateFontSize);
          _dateColor = _savedColor(decoded, 'dateColor', _dateColor);
          _dayTop = _savedDouble(decoded, 'dayTop', _dayTop);
          _dayRight = _savedDouble(decoded, 'dayRight', _dayRight);
          _dayFontSize = _savedDouble(decoded, 'dayFontSize', _dayFontSize);
          _dayColor = _savedColor(decoded, 'dayColor', _dayColor);
          _commentTop = _savedDouble(decoded, 'commentTop', _commentTop);
          _commentLeft = _savedDouble(decoded, 'commentLeft', _commentLeft);
          _commentFontSize =
              _savedDouble(decoded, 'commentFontSize', _commentFontSize);
          _commentColor = _savedColor(decoded, 'commentColor', _commentColor);
          _showComment = _savedBool(decoded, 'showComment', _showComment);
          _showDate = _savedBool(decoded, 'showDate', _showDate);
          _showDay = _savedBool(decoded, 'showDay', _showDay);
          _showCollected = _savedBool(decoded, 'showCollected', _showCollected);
          _showFilePhoto = _savedBool(decoded, 'showFilePhoto', _showFilePhoto);
          final savedCardFormat = decoded['selectedCardFormat'];
          if (savedCardFormat == 'Card 1' || savedCardFormat == 'Card 2') {
            _selectedCardFormat = savedCardFormat;
          }
          final savedCardTextSettings = decoded['cardTextSettings'];
          if (savedCardTextSettings is Map) {
            for (final entry in savedCardTextSettings.entries) {
              if ((entry.key == 'Card 1' || entry.key == 'Card 2') &&
                  entry.value is Map) {
                _cardTextSettings[entry.key as String] =
                    Map<String, dynamic>.from(entry.value as Map);
              }
            }
          }
          _cardTextSettings.putIfAbsent(
            _selectedCardFormat,
            _captureCardTextSettings,
          );
          _applyCardTextSettings(
            _cardTextSettings[_selectedCardFormat]!,
          );
        }
      }
    } on FileSystemException catch (error) {
      debugPrint('Failed to load editor settings: $error');
    } on FormatException catch (error) {
      debugPrint('Editor settings file is invalid: $error');
    } finally {
      _settingsLoaded = true;
      if (mounted) setState(() {});
    }
  }

  double _savedDouble(
      Map<String, dynamic> settings, String key, double fallback) {
    final value = settings[key];
    return value is num && value.toDouble().isFinite
        ? value.toDouble()
        : fallback;
  }

  String _savedString(
      Map<String, dynamic> settings, String key, String fallback) {
    final value = settings[key];
    return value is String ? value : fallback;
  }

  bool _savedBool(Map<String, dynamic> settings, String key, bool fallback) {
    final value = settings[key];
    return value is bool ? value : fallback;
  }

  Color _savedColor(Map<String, dynamic> settings, String key, Color fallback) {
    final value = settings[key];
    return value is int ? Color(value) : fallback;
  }

  List<Map<String, dynamic>> _savedColoredRanges(dynamic value) {
    if (value is! List) return [];
    return value.whereType<Map<String, dynamic>>().where((range) {
      return range['start'] is int &&
          range['end'] is int &&
          range['color'] is int;
    }).map((range) {
      return {
        'start': range['start'] as int,
        'end': range['end'] as int,
        'color': Color(range['color'] as int),
      };
    }).toList();
  }

  // ইমেজ সেভ করার মূল ফাংশন
  Future<void> _exportImage() async {
    try {
      // Create a widget that matches the current display scaling
      final screenshotWidget = LayoutBuilder(
        builder: (context, constraints) {
          double containerSize = constraints.maxWidth < constraints.maxHeight
              ? constraints.maxWidth
              : constraints.maxHeight;
          double scaleFactor = containerSize / 1080.0;

          return SizedBox(
            width: containerSize,
            height: containerSize,
            child: Container(
              color: Colors.black,
              child: Stack(
                children: [
                  // Background image with drag support
                  Positioned.fill(
                    child: Transform(
                      transform: Matrix4.identity()
                        ..translate(_imageOffset.dx * scaleFactor,
                            _imageOffset.dy * scaleFactor)
                        ..scale(_imageScale),
                      alignment: Alignment.center,
                      child: _displayImage != null
                          ? Image(
                              image: _displayImage!,
                              fit: BoxFit.fitWidth,
                              alignment: Alignment.topCenter)
                          : const SizedBox(),
                    ),
                  ),
                  // Frame overlay
                  Positioned.fill(
                    child: Image.asset(_cardFrameAsset, fit: BoxFit.fill),
                  ),
                  // Title text - responsive sizing (export uses RichText with per-selection colors)
                  Positioned(
                    top: _textTop * scaleFactor,
                    left: _textLeft * scaleFactor,
                    child: SizedBox(
                      width: 1000 * scaleFactor,
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(children: _buildTitleSpans(scaleFactor)),
                      ),
                    ),
                  ),
                  // Bottom elements - customizable positioning
                  Stack(
                    children: [
                      if (_showDate)
                        Positioned(
                          top: _dateTop * scaleFactor,
                          right: _dateRight * scaleFactor,
                          child: Text(
                            getBanglaDate(),
                            style: TextStyle(
                              color: _dateColor,
                              fontSize: _dateFontSize * scaleFactor,
                              fontFamily: 'SolaimanLipi',
                            ),
                          ),
                        ),
                      if (_showDay)
                        Positioned(
                          top: _dayTop * scaleFactor,
                          right: _dayRight * scaleFactor,
                          child: Text(
                            getBanglaDay(),
                            style: TextStyle(
                              color: _dayColor,
                              fontSize: _dayFontSize * scaleFactor,
                              fontFamily: 'SolaimanLipi',
                            ),
                          ),
                        ),
                      if (_showComment)
                        Positioned(
                          top: _commentTop * scaleFactor,
                          left: _commentLeft * scaleFactor,
                          child: Text(
                            "নিউজ লিংক কমেন্টে",
                            style: TextStyle(
                              color: _commentColor,
                              fontSize: _commentFontSize * scaleFactor,
                              fontFamily: 'SolaimanLipi',
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );

      // Render at the target export resolution to avoid upscaling a smaller capture.
      final imageBytes = await _screenshotController.captureFromWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1080, 1080)),
          child: screenshotWidget,
        ),
        pixelRatio: 1.0,
        delay: const Duration(milliseconds: 100),
      );

      final pngImage = img.decodePng(imageBytes);
      if (pngImage == null) {
        throw const FormatException('The card preview could not be encoded.');
      }
      final resizedImage = img.copyResize(
        pngImage,
        width: 1080,
        height: 1080,
        interpolation: img.Interpolation.linear,
      );
      final jpgBytes = Uint8List.fromList(
        img.encodeJpg(resizedImage, quality: 95),
      );

      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'কোথায় নিউজ কার্ডটি সেভ করতে চান?',
        fileName: 'news_card_${DateTime.now().millisecondsSinceEpoch}.jpg',
        type: FileType.image,
        bytes: Platform.isAndroid ? jpgBytes : null,
      );

      if (outputFile == null) return;

      if (!Platform.isAndroid) {
        if (!outputFile.toLowerCase().endsWith('.jpg') &&
            !outputFile.toLowerCase().endsWith('.jpeg')) {
          outputFile += '.jpg';
        }
        await File(outputFile).writeAsBytes(jpgBytes, flush: true);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("নিউজ কার্ডটি সফলভাবে সেভ হয়েছে!")),
        );
      }
    } catch (e) {
      debugPrint("Export Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("নিউজ কার্ডটি সেভ করা যায়নি।")),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _loadEditorSettings();
    if (widget.initialImageUrl != null) {
      _displayImage = NetworkImage(widget.initialImageUrl!);
    }
  }

  @override
  void dispose() {
    _settingsSaveTimer?.cancel();
    if (_settingsLoaded) _queueSettingsSave();
    _titleController.dispose();
    super.dispose();
  }

  String getBanglaDate() {
    DateTime now = DateTime.now();
    List<String> months = [
      'জানুয়ারি',
      'ফেব্রুয়ারি',
      'মার্চ',
      'এপ্রিল',
      'মে',
      'জুন',
      'জুলাই',
      'আগস্ট',
      'সেপ্টেম্বর',
      'অক্টোবর',
      'নভেম্বর',
      'ডিসেম্বর'
    ];
    String day = _toBanglaNumber(now.day.toString());
    String year = _toBanglaNumber(now.year.toString());
    String month = months[now.month - 1];
    return '$day $month $year';
  }

  String getBanglaDay() {
    DateTime now = DateTime.now();
    List<String> days = [
      'সোমবার',
      'মঙ্গলবার',
      'বুধবার',
      'বৃহস্পতিবার',
      'শুক্রবার',
      'শনিবার',
      'রবিবার'
    ];
    return days[now.weekday - 1];
  }

  String _toBanglaNumber(String number) {
    Map<String, String> digits = {
      '0': '০',
      '1': '১',
      '2': '২',
      '3': '৩',
      '4': '৪',
      '5': '৫',
      '6': '৬',
      '7': '৭',
      '8': '৮',
      '9': '৯',
    };
    return number.split('').map((c) => digits[c] ?? c).join('');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("News Designer",
            style: TextStyle(color: Colors.white, fontSize: 14)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context)),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isWide = constraints.maxWidth > 950;
          return Flex(
            direction: isWide ? Axis.horizontal : Axis.vertical,
            children: [
              // --- প্রিভিউ এরিয়া ---
              Expanded(
                flex: 3,
                child: Container(
                  color: Colors.black,
                  alignment: Alignment.center,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      double containerSize =
                          constraints.maxWidth < constraints.maxHeight
                              ? constraints.maxWidth
                              : constraints.maxHeight;
                      double scaleFactor = containerSize / 1080.0;

                      return SizedBox(
                        width: containerSize,
                        height: containerSize,
                        child: Container(
                          color: Colors.black,
                          child: Stack(
                            children: [
                              // Background image with drag support
                              Positioned.fill(
                                child: GestureDetector(
                                  onScaleStart: (details) {
                                    _lastFocalPoint = details.focalPoint;
                                    _lastScale = _imageScale;
                                  },
                                  onScaleUpdate: (details) {
                                    setState(() {
                                      // Use focalPointDelta and normalize by preview scale so offsets scale with container
                                      final Offset delta =
                                          details.focalPointDelta;
                                      _imageOffset += Offset(
                                          delta.dx / scaleFactor,
                                          delta.dy / scaleFactor);
                                      _lastFocalPoint = details.focalPoint;

                                      // Handle scale (zoom)
                                      _imageScale = _lastScale * details.scale;
                                    });
                                  },
                                  onScaleEnd: (details) {
                                    // Reset last scale for next gesture
                                    _lastScale = _imageScale;
                                  },
                                  child: ClipRect(
                                    child: Transform(
                                      transform: Matrix4.identity()
                                        ..translate(
                                            _imageOffset.dx * scaleFactor,
                                            _imageOffset.dy * scaleFactor)
                                        ..scale(_imageScale),
                                      alignment: Alignment.center,
                                      child: _displayImage != null
                                          ? Image(
                                              image: _displayImage!,
                                              fit: BoxFit.fitWidth,
                                              alignment: Alignment.topCenter,
                                            )
                                          : Container(
                                              color: Colors.transparent),
                                    ),
                                  ),
                                ),
                              ),
                              // Frame overlay
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      image: DecorationImage(
                                        image: AssetImage(_cardFrameAsset),
                                        fit: BoxFit.fill,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // Title text - responsive sizing
                              Positioned(
                                top: _textTop * scaleFactor,
                                left: _textLeft * scaleFactor,
                                child: GestureDetector(
                                  // Drag to move title position or select text based on mode
                                  onPanUpdate: !_isSelectMode
                                      ? (d) => setState(() {
                                            _textTop +=
                                                d.delta.dy / scaleFactor;
                                            _textLeft +=
                                                d.delta.dx / scaleFactor;
                                          })
                                      : (d) {
                                          final box = _titleBoxKey
                                                  .currentContext
                                                  ?.findRenderObject()
                                              as RenderBox?;
                                          if (box != null) {
                                            final idx =
                                                _charIndexFromLocalOffset(
                                                    d.localPosition,
                                                    box.size.width,
                                                    scaleFactor);
                                            setState(() => _selectionEnd = idx);
                                          }
                                        },
                                  onPanStart: _isSelectMode
                                      ? (details) {
                                          final box = _titleBoxKey
                                                  .currentContext
                                                  ?.findRenderObject()
                                              as RenderBox?;
                                          if (box != null) {
                                            final idx =
                                                _charIndexFromLocalOffset(
                                                    details.localPosition,
                                                    box.size.width,
                                                    scaleFactor);
                                            setState(() {
                                              _selectionStart = idx;
                                              _selectionEnd = idx;
                                            });
                                          }
                                        }
                                      : null,
                                  child: SizedBox(
                                    key: _titleBoxKey,
                                    width: 1000 * scaleFactor,
                                    child: RichText(
                                      textAlign: TextAlign.center,
                                      text: TextSpan(
                                          children:
                                              _buildTitleSpans(scaleFactor)),
                                    ),
                                  ),
                                ),
                              ),
                              // Bottom elements - customizable positioning
                              Stack(
                                children: [
                                  if (_showDate)
                                    Positioned(
                                      top: _dateTop * scaleFactor,
                                      right: _dateRight * scaleFactor,
                                      child: GestureDetector(
                                        onPanUpdate: (d) => setState(() {
                                          _dateTop += d.delta.dy / scaleFactor;
                                          _dateRight -=
                                              d.delta.dx / scaleFactor;
                                        }),
                                        child: Text(
                                          getBanglaDate(),
                                          style: TextStyle(
                                            color: _dateColor,
                                            fontSize:
                                                _dateFontSize * scaleFactor,
                                            fontFamily: 'SolaimanLipi',
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (_showDay)
                                    Positioned(
                                      top: _dayTop * scaleFactor,
                                      right: _dayRight * scaleFactor,
                                      child: GestureDetector(
                                        onPanUpdate: (d) => setState(() {
                                          _dayTop += d.delta.dy / scaleFactor;
                                          _dayRight -= d.delta.dx / scaleFactor;
                                        }),
                                        child: Text(
                                          getBanglaDay(),
                                          style: TextStyle(
                                            color: _dayColor,
                                            fontSize:
                                                _dayFontSize * scaleFactor,
                                            fontFamily: 'SolaimanLipi',
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (_showComment)
                                    Positioned(
                                      top: _commentTop * scaleFactor,
                                      left: _commentLeft * scaleFactor,
                                      child: GestureDetector(
                                        onPanUpdate: (d) => setState(() {
                                          _commentTop +=
                                              d.delta.dy / scaleFactor;
                                          _commentLeft +=
                                              d.delta.dx / scaleFactor;
                                        }),
                                        child: Text(
                                          "নিউজ লিংক কমেন্টে",
                                          style: TextStyle(
                                            color: _commentColor,
                                            fontSize:
                                                _commentFontSize * scaleFactor,
                                            fontFamily: 'SolaimanLipi',
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // --- কন্ট্রোল প্যানেল ---
              Container(
                width: isWide ? 350 : double.infinity,
                height: isWide ? double.infinity : 400,
                color: const Color(0xFF212121),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader("IMAGE SETTINGS"),
                      _buildHeader("CARD FORMAT"),
                      _buildDarkDropdown(
                        _selectedCardFormat,
                        const ['Card 1', 'Card 2'],
                        (value) {
                          if (value != null) {
                            _switchCardFormat(value);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      const Text("Zoom View",
                          style:
                              TextStyle(color: Colors.white54, fontSize: 10)),
                      Slider(
                        value: _imageScale,
                        min: 0.5,
                        max: 3.0,
                        activeColor: const Color(0xFF7E57C2),
                        onChanged: (v) => setState(() {
                          _imageScale = v;
                          _lastScale =
                              v; // Update last scale when slider changes
                        }),
                      ),
                      ElevatedButton(
                        onPressed: _pickBackgroundImage,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF333333),
                            minimumSize: const Size(double.infinity, 36)),
                        child: const Text("Change Image",
                            style: TextStyle(
                                color: Color(0xFF7E57C2), fontSize: 12)),
                      ),
                      const SizedBox(height: 15),
                      _buildHeader("CHARACTER"),

                      // Title Input with AI Button
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _titleController,
                              maxLines: 3,
                              onChanged: (v) => setState(() {}),
                              enableInteractiveSelection: true,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: const Color(0xFF2B2B2B),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(4),
                                    borderSide: BorderSide.none),
                                hintText: "এখানে শিরোনাম লিখুন",
                                hintStyle: const TextStyle(
                                    color: Colors.white24, fontSize: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // AI Button
                        ],
                      ),

                      if (_isSelectMode)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: ElevatedButton(
                            onPressed: _isSelectMode
                                ? () {
                                    if (_selectionStart != null &&
                                        _selectionEnd != null) {
                                      _showColorPickerForSelection();
                                    } else if (_titleController
                                        .selection.isValid) {
                                      final sel = _titleController.selection;
                                      setState(() {
                                        _selectionStart = sel.start;
                                        _selectionEnd = sel.end;
                                      });
                                      _showColorPickerForSelection();
                                    } else {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: Text(
                                                  "প্রথমে টেক্সট সিলেক্ট করুন")));
                                    }
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF7E57C2),
                                minimumSize: const Size(double.infinity, 36)),
                            child: const Text("Apply Color to Selected Text",
                                style: TextStyle(
                                    color: Colors.white, fontSize: 12)),
                          ),
                        ),

                      const SizedBox(height: 10),
                      const Text("Font Name",
                          style:
                              TextStyle(color: Colors.white54, fontSize: 10)),
                      _buildDarkDropdown(
                          _selectedFontFamily,
                          ['SolaimanLipi', 'SutonnyMJ'],
                          (v) => setState(() => _selectedFontFamily = v!)),
                      const SizedBox(height: 10),
                      const Text("Weight",
                          style:
                              TextStyle(color: Colors.white54, fontSize: 10)),
                      _buildDarkDropdown(_selectedWeight, ['Bold', 'Regular'],
                          (v) => setState(() => _selectedWeight = v!)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Size",
                                    style: TextStyle(
                                        color: Colors.white54, fontSize: 10)),
                                _buildFontSizeInput(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Height",
                                    style: TextStyle(
                                        color: Colors.white54, fontSize: 10)),
                                _buildDarkInput(
                                    "1.2",
                                    (v) => setState(() => _lineHeight =
                                        double.tryParse(v) ?? 1.2)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Color",
                                  style: TextStyle(
                                      color: Colors.white54, fontSize: 10)),
                              GestureDetector(
                                onTap: _showColorPicker,
                                child: Container(
                                    width: 45,
                                    height: 35,
                                    decoration: BoxDecoration(
                                        color: _textColor,
                                        borderRadius:
                                            BorderRadius.circular(4))),
                              )
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Text("Select Mode",
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 10)),
                          const SizedBox(width: 10),
                          Switch(
                            value: _isSelectMode,
                            onChanged: (v) => setState(() => _isSelectMode = v),
                            activeColor: const Color(0xFF7E57C2),
                          ),
                        ],
                      ),
                      _buildHeader("CARD INFO"),
                      _buildSquareCheckbox("বিস্তারিত কমেন্টে", _showComment,
                          (v) => setState(() => _showComment = v!)),
                      _buildSquareCheckbox("তারিখ", _showDate,
                          (v) => setState(() => _showDate = v!)),
                      _buildSquareCheckbox("বার", _showDay,
                          (v) => setState(() => _showDay = v!)),
                      _buildSquareCheckbox("সংগৃহীত", _showCollected,
                          (v) => setState(() => _showCollected = v!)),
                      _buildSquareCheckbox("ফাইল ফটো", _showFilePhoto,
                          (v) => setState(() => _showFilePhoto = v!)),
                      const SizedBox(height: 15),
                      _buildHeader("BOTTOM ELEMENTS"),

                      // Date controls
                      /* if (_showDate) ...[
                        const Text("তারিখ (Date)",
                            style: TextStyle(color: Colors.white54, fontSize: 10)),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Top",
                                      style: TextStyle(color: Colors.white54, fontSize: 8)),
                                  _buildDarkInput("5.0", (v) => setState(() => _dateTop = double.tryParse(v) ?? 5.0)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Left",
                                      style: TextStyle(color: Colors.white54, fontSize: 8)),
                                  _buildDarkInput("60.0", (v) => setState(() => _dateRight = double.tryParse(v) ?? 60.0)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Size",
                                      style: TextStyle(color: Colors.white54, fontSize: 8)),
                                  _buildDarkInput("28.0", (v) => setState(() => _dateFontSize = double.tryParse(v) ?? 28.0)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 5),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Color",
                                    style: TextStyle(color: Colors.white54, fontSize: 8)),
                                GestureDetector(
                                  onTap: () => _showColorPickerForElement('date'),
                                  child: Container(
                                      width: 30, height: 30, decoration: BoxDecoration(color: _dateColor, borderRadius: BorderRadius.circular(4))),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ], */

                      // Day controls
                      /* if (_showDay) ...[
                        const Text("বার (Day)",
                            style: TextStyle(color: Colors.white54, fontSize: 10)),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Top",
                                      style: TextStyle(color: Colors.white54, fontSize: 8)),
                                  _buildDarkInput("5.0", (v) => setState(() => _dayTop = double.tryParse(v) ?? 5.0)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Left",
                                      style: TextStyle(color: Colors.white54, fontSize: 8)),
                                  _buildDarkInput("200.0", (v) => setState(() => _dayRight = double.tryParse(v) ?? 200.0)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Size",
                                      style: TextStyle(color: Colors.white54, fontSize: 8)),
                                  _buildDarkInput("28.0", (v) => setState(() => _dayFontSize = double.tryParse(v) ?? 28.0)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 5),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Color",
                                    style: TextStyle(color: Colors.white54, fontSize: 8)),
                                GestureDetector(
                                  onTap: () => _showColorPickerForElement('day'),
                                  child: Container(
                                      width: 30, height: 30, decoration: BoxDecoration(color: _dayColor, borderRadius: BorderRadius.circular(4))),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ], */

                      // Comment controls
                      /* if (_showComment) ...[
                        const Text("নিউজ লিংক কমেন্টে (Comment)",
                            style: TextStyle(color: Colors.white54, fontSize: 10)),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Top",
                                      style: TextStyle(color: Colors.white54, fontSize: 8)),
                                  _buildDarkInput("5.0", (v) => setState(() => _commentTop = double.tryParse(v) ?? 5.0)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Left",
                                      style: TextStyle(color: Colors.white54, fontSize: 8)),
                                  _buildDarkInput("400.0", (v) => setState(() => _commentLeft = double.tryParse(v) ?? 400.0)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Size",
                                      style: TextStyle(color: Colors.white54, fontSize: 8)),
                                  _buildDarkInput("28.0", (v) => setState(() => _commentFontSize = double.tryParse(v) ?? 28.0)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 5),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Color",
                                    style: TextStyle(color: Colors.white54, fontSize: 8)),
                                GestureDetector(
                                  onTap: () => _showColorPickerForElement('comment'),
                                  child: Container(
                                      width: 30, height: 30, decoration: BoxDecoration(color: _commentColor, borderRadius: BorderRadius.circular(4))),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ], */

                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _exportImage,
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text("EXPORT JPG"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF448AFF),
                          minimumSize: const Size(double.infinity, 45),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickBackgroundImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (!mounted || result == null || result.files.isEmpty) return;

      final path = result.files.single.path;
      if (path == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("নির্বাচিত ছবিটি পড়া যায়নি।")),
        );
        return;
      }
      final file = File(path);
      if (!await file.exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("নির্বাচিত ছবিটি পড়া যায়নি।")),
        );
        return;
      }

      if (!mounted) return;
      setState(() => _displayImage = FileImage(file));
    } on PlatformException catch (error) {
      debugPrint('Image picker failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("ছবি নির্বাচন করা যায়নি।")),
        );
      }
    } on FileSystemException catch (error) {
      debugPrint('Selected image is unavailable: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("নির্বাচিত ছবিটি পড়া যায়নি।")),
        );
      }
    }
  }

  // --- হেল্পার উইজেটস ---
  Widget _buildHeader(String title) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
        const Divider(color: Colors.white12, thickness: 1),
        const SizedBox(height: 8),
      ]);

  Widget _buildDarkDropdown(
      String value, List<String> items, Function(String?) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
          color: const Color(0xFF2B2B2B),
          borderRadius: BorderRadius.circular(4)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: const Color(0xFF2B2B2B),
          icon: const Icon(Icons.arrow_drop_down, color: Colors.white38),
          style: const TextStyle(color: Colors.white, fontSize: 12),
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildDarkInput(String hint, Function(String) onChanged) {
    return Container(
      height: 40,
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
          color: const Color(0xFF2B2B2B),
          borderRadius: BorderRadius.circular(4)),
      child: TextField(
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 12),
        decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white38),
            border: InputBorder.none),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildSquareCheckbox(
      String title, bool value, Function(bool?) onChanged) {
    return Row(
      children: [
        Theme(
          data: ThemeData(unselectedWidgetColor: Colors.white24),
          child: Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: const Color(0xFF448AFF),
              side: const BorderSide(color: Colors.white24)),
        ),
        Text(title,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }

  Widget _buildFontSizeInput() {
    return Container(
      height: 40,
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
          color: const Color(0xFF2B2B2B),
          borderRadius: BorderRadius.circular(4)),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: TextEditingController(text: _selectedSize),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: const InputDecoration(
                  hintText: "Size",
                  hintStyle: TextStyle(color: Colors.white38),
                  border: InputBorder.none),
              onChanged: (value) {
                setState(() => _selectedSize = value);
              },
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() => _selectedSize = value);
            },
            itemBuilder: (context) => ['40', '60', '80', '100', '120']
                .map((size) => PopupMenuItem(value: size, child: Text(size)))
                .toList(),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child:
                  Icon(Icons.arrow_drop_down, color: Colors.white38, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorGrid(Function(Color) onColorSelected) {
    return SizedBox(
      width: 300,
      height: 300,
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: _colorPalette.length,
        itemBuilder: (context, index) {
          final color = _colorPalette[index];
          return GestureDetector(
            onTap: () => onColorSelected(color),
            child: Container(
              decoration: BoxDecoration(
                color: color,
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showColorPicker() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF212121),
        content: _buildColorGrid((c) {
          setState(() => _textColor = c);
          Navigator.pop(context);
        }),
      ),
    );
  }

  void _showColorPickerForElement(String element) {
    Color currentColor;
    Function(Color) onColorChanged;

    switch (element) {
      case 'date':
        currentColor = _dateColor;
        onColorChanged = (c) => setState(() => _dateColor = c);
        break;
      case 'day':
        currentColor = _dayColor;
        onColorChanged = (c) => setState(() => _dayColor = c);
        break;
      case 'comment':
        currentColor = _commentColor;
        onColorChanged = (c) => setState(() => _commentColor = c);
        break;
      default:
        return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF212121),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: currentColor,
            onColorChanged: onColorChanged,
          ),
        ),
      ),
    );
  }

  // Show color picker and apply to currently selected title range
  void _showColorPickerForSelection() {
    if (_selectionStart == null || _selectionEnd == null) return;
    int start =
        _selectionStart! < _selectionEnd! ? _selectionStart! : _selectionEnd!;
    int end =
        _selectionStart! < _selectionEnd! ? _selectionEnd! : _selectionStart!;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF212121),
        content: _buildColorGrid((c) {
          setState(() {
            // Add range mapping; new selection overrides existing overlaps
            _coloredRanges
                .removeWhere((r) => !(r['end'] <= start || r['start'] >= end));
            _coloredRanges.add({'start': start, 'end': end, 'color': c});
            // clear selection
            _selectionStart = null;
            _selectionEnd = null;
          });
          Navigator.pop(context);
        }),
      ),
    );
  }

  // Build list of TextSpan for the title using colored ranges
  List<TextSpan> _buildTitleSpans(double scaleFactor) {
    final String text = _titleController.text;
    if (text.isEmpty) {
      return [
        TextSpan(
            text: 'এখানে শিরোনাম লিখুন',
            style: TextStyle(
                color: Colors.white24,
                fontSize: double.parse(_selectedSize) * scaleFactor,
                fontFamily: _selectedFontFamily))
      ];
    }

    int len = text.length;
    List<TextSpan> spans = [];

    int selStart = _selectionStart != null && _selectionEnd != null
        ? (_selectionStart! < _selectionEnd!
            ? _selectionStart!
            : _selectionEnd!)
        : -1;
    int selEnd = _selectionStart != null && _selectionEnd != null
        ? (_selectionStart! < _selectionEnd!
            ? _selectionEnd!
            : _selectionStart!)
        : -1;

    int i = 0;
    while (i < len) {
      // determine color for char i
      Color c = _textColor;
      for (var r in _coloredRanges) {
        if (i >= r['start'] && i < r['end']) {
          c = r['color'] as Color;
        }
      }

      int j = i + 1;
      while (j < len) {
        Color c2 = _textColor;
        for (var r in _coloredRanges) {
          if (j >= r['start'] && j < r['end']) {
            c2 = r['color'] as Color;
          }
        }
        if (c2 != c) break;
        j++;
      }

      // Check if this span overlaps with selection
      bool isSelected = selStart != -1 && i < selEnd && j > selStart;

      spans.add(TextSpan(
        text: text.substring(i, j),
        style: TextStyle(
          color: c,
          fontSize: double.parse(_selectedSize) * scaleFactor,
          fontFamily: _selectedFontFamily,
          height: _lineHeight,
          fontWeight:
              _selectedWeight == 'Bold' ? FontWeight.bold : FontWeight.normal,
          backgroundColor: isSelected ? Colors.blue.withOpacity(0.3) : null,
        ),
      ));

      i = j;
    }

    return spans;
  }

  // Convert local offset within the title box to character index
  int _charIndexFromLocalOffset(
      Offset local, double maxWidth, double scaleFactor) {
    final text = _titleController.text;
    if (text.isEmpty) return 0;
    final tp = TextPainter(
      text: TextSpan(children: _buildTitleSpans(scaleFactor)),
      textDirection: Directionality.of(context),
      textAlign: TextAlign.center,
    );
    tp.layout(maxWidth: maxWidth);
    final pos = tp.getPositionForOffset(local);
    return pos.offset.clamp(0, text.length).toInt();
  }
}
