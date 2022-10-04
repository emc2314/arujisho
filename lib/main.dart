import 'dart:async';
import 'dart:math';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as Path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:clipboard_listener/clipboard_listener.dart';
import 'package:html/parser.dart' show parse;
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:kana_kit/kana_kit.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:bootstrap_icons/bootstrap_icons.dart';
import 'package:icofont_flutter/icofont_flutter.dart';

import 'package:arujisho/splash_screen.dart';
import 'package:arujisho/ffi.io.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  static const isRelease = true;
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'ある辞書',
        theme: isRelease
            ? ThemeData(
                primarySwatch: Colors.blue,
              )
            : ThemeData(
                colorScheme: ColorScheme.fromSwatch().copyWith(
                  primary: Colors.pink[300],
                  secondary: Colors.pinkAccent[100],
                ),
              ),
        initialRoute: '/splash',
        routes: {
          '/': (context) => const MyHomePage(),
          '/splash': (context) => const SplashScreen(),
        });
  }
}

typedef RequestFn<T> = Future<List<T>> Function(int nextIndex);
typedef ItemBuilder<T> = Widget Function(
    BuildContext context, T item, int index);

class InfiniteList<T> extends StatefulWidget {
  final RequestFn<T> onRequest;
  final ItemBuilder<T> itemBuilder;

  const InfiniteList(
      {Key? key, required this.onRequest, required this.itemBuilder})
      : super(key: key);

  @override
  _InfiniteListState<T> createState() => _InfiniteListState<T>();
}

class _InfiniteListState<T> extends State<InfiniteList<T>> {
  List<T> items = [];
  bool end = false;

  _getMoreItems() async {
    final moreItems = await widget.onRequest(items.length);
    if (!mounted) return;

    if (moreItems.isEmpty) {
      setState(() => end = true);
      return;
    }
    setState(() => items = [...items, ...moreItems]);
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemBuilder: (context, index) {
        if (index < items.length) {
          return widget.itemBuilder(context, items[index], index);
        } else if (index == items.length && end) {
          return const Center(child: Text('以上です'));
        } else {
          _getMoreItems();
          return const SizedBox(
            child: Center(
                child: Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator())),
          );
        }
      },
      itemCount: items.length + 1,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _controller = TextEditingController();
  final StreamController _streamController = StreamController();
  final List<String> _history = [''];
  final Map<int, String?> _hatsuonCache = {};
  static const _kanaKit = KanaKit();
  int _searchMode = 0;
  Timer? _debounce;
  static Database? _db;
  Future<Database> get database async {
    if (_db != null) return _db!;

    var databasesPath = await getDatabasesPath();
    var path = Path.join(databasesPath, "arujisho.db");

    _db = await openDatabase(path, readOnly: true);
    return _db!;
  }

  _search(int mode) async {
    if (_controller.text.isEmpty) {
      _streamController.add(null);
      return;
    }
    if (_history.last != _controller.text) {
      _history.add(_controller.text);
    }
    _searchMode = mode;
    String s = _controller.text;
    s = s.replaceAll("\\pc", "\\p{Han}");
    s = s.replaceAll("\\ph", "\\p{Hiragana}");
    s = s.replaceAll("\\pk", "\\p{Katakana}");
    //s = t.evaluate('cj_convert(${json.encode(s)})').stringResult;
    String sp = Path.join(
        (await getApplicationSupportDirectory()).path, "sudachi.json");
    print(await sudachiAPI.parse(data: s, configPath: sp));
    _streamController.add(s);
  }

  void _hatsuon(Map item) async {
    Map<String, String> burpHeader = {
      "Sec-Ch-Ua":
          "\"Chromium\";v=\"104\", \" Not A;Brand\";v=\"99\", \"Google Chrome\";v=\"104\"",
      "Dnt": "1",
      "Sec-Ch-Ua-Mobile": "?0",
      "User-Agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/104.0.0.0 Safari/537.36",
      "Sec-Ch-Ua-Platform": "\"Windows\"",
      "Content-Type": "application/x-www-form-urlencoded",
      "Accept": "*/*",
      "Sec-Fetch-Site": "none",
      "Sec-Fetch-Mode": "cors",
      "Sec-Fetch-Dest": "empty",
      "Accept-Encoding": "gzip, deflate",
      "Accept-Language":
          "en-US,en;q=0.9,zh-TW;q=0.8,zh-CN;q=0.7,zh;q=0.6,ja;q=0.5",
      "Connection": "close"
    };
    String? url;
    if (_hatsuonCache.containsKey(item['idex'])) {
      url = _hatsuonCache[item['idex']];
    }
    if (url == null) {
      try {
        var resp = await http.post(
            Uri.parse(
                'https://www.japanesepod101.com/learningcenter/reference/dictionary_post'),
            headers: burpHeader,
            body: {
              "post": "dictionary_reference",
              "match_type": "exact",
              "search_query": item['word'],
              "vulgar": "true"
            });
        var dom = parse(resp.body);
        for (var row in dom.getElementsByClassName('dc-result-row')) {
          try {
            var audio = row.getElementsByTagName('audio')[0];
            var kana = row.getElementsByClassName('dc-vocab_kana')[0].text;
            if (_kanaKit.toKatakana(item['yomikata']) ==
                    _kanaKit.toKatakana(kana) ||
                _kanaKit.toHiragana(kana) == item['yomikata']) {
              url =
                  "https://assets.languagepod101.com/dictionary/japanese/audiomp3.php?kanji=${item['word']}&kana=$kana";
              setState(() {
                item['loading'] = true;
              });
              var file = await DefaultCacheManager()
                  .getSingleFile(url, headers: burpHeader);
              var hash = await sha256.bind(file.openRead()).first;
              if (hash.toString() ==
                  'ae6398b5a27bc8c0a771df6c907ade794be15518174773c58c7c7ddd17098906') {
                url = audio.getElementsByTagName('source')[0].attributes['src'];
              }
              break;
            }
          } catch (_) {}
        }
      } catch (_) {}
      setState(() {
        item['loading'] = false;
      });
    }
    if (url == null) {
      try {
        var resp = await http.get(
            Uri.parse("https://forvo.com/word/${item['word']}/#ja"),
            headers: burpHeader);
        var dom = parse(resp.body);
        var ja = dom.getElementById('language-container-ja');
        var pronunciation =
            ja!.getElementsByClassName('pronunciations-list')[0];
        String play = pronunciation
            .getElementsByClassName('play')[0]
            .attributes['onclick']!;
        RegExp exp = RegExp(r"Play\(\d+,'.+','.+',\w+,'([^']+)");
        String? match = exp.firstMatch(play)?.group(1);
        if (match != null && match.isNotEmpty) {
          match = utf8.decode(base64.decode(match));
          url = 'https://audio00.forvo.com/audios/mp3/$match';
        } else {
          exp = RegExp(r"Play\(\d+,'[^']+','([^']+)");
          match = exp.firstMatch(play)?.group(1);
          match = utf8.decode(base64.decode(match!));
          url = 'https://audio00.forvo.com/ogg/$match';
        }
      } catch (_) {}
    }
    if (url != null && url.isNotEmpty) {
      setState(() {
        item['loading'] = true;
      });
      try {
        final player = AudioPlayer();
        var file =
            await DefaultCacheManager().getSingleFile(url, headers: burpHeader);
        await player.setFilePath(file.path);
        player.play();
      } catch (_) {}
    }
    setState(() {
      _hatsuonCache[item['idex']] = url;
      item['loading'] = false;
    });
  }

  _setSearchContent(String text) {
    _controller.value = TextEditingValue(
        text: text,
        selection:
            TextSelection.fromPosition(TextPosition(offset: text.length)));
  }

  _cpListener() async {
    String cp = (await Clipboard.getData('text/plain'))!.text ?? '';
    if (cp == _controller.text) {
      return;
    }
    _setSearchContent(cp);
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_debounce?.isActive ?? false) return;
      _debounce = Timer(const Duration(milliseconds: 300), () {
        _search(0);
      });
      setState(() {});
    });
    ClipboardListener.addListener(_cpListener);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    ClipboardListener.removeListener(_cpListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
        onWillPop: () async {
          if (_history.isEmpty) return true;
          String temp = _history.last;
          _history.removeLast();
          _setSearchContent(temp);
          return false;
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text("ある辞書", style: TextStyle(fontSize: 20)),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48.0),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.only(left: 12.0, bottom: 8.0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24.0),
                      ),
                      child: TextFormField(
                        controller: _controller,
                        textAlignVertical: TextAlignVertical.center,
                        decoration: InputDecoration(
                          hintText: "調べたい言葉をご入力してください",
                          contentPadding:
                              const EdgeInsets.fromLTRB(20, 12, 12, 12),
                          border: InputBorder.none,
                          suffixIcon: _controller.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear, size: 20),
                                  onPressed: () {
                                    setState(() => _controller.clear());
                                  },
                                ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: SizedBox(
                          width: 48,
                          height: 48,
                          child: InkWell(
                            onTap: () {
                              _search(-1);
                            },
                            onLongPress: () => showDialog(
                                context: context,
                                builder: (context) {
                                  return AlertDialog(
                                    title: const Text('頻度コントロール'),
                                    content: TextField(
                                      onChanged: (value) {
                                        int v = 0;
                                        try {
                                          v = int.parse(value);
                                          assert(v > 0);
                                        } catch (_) {}
                                        setState(() {
                                          _searchMode = v;
                                        });
                                      },
                                      decoration: const InputDecoration(
                                          hintText: "基準頻度（正整数）"),
                                    ),
                                  );
                                }),
                            child: Ink(
                                child: const Icon(
                              BootstrapIcons.sort_down_alt,
                              color: Colors.white,
                            )),
                          )))
                ],
              ),
            ),
          ),
          body: Container(
              margin: const EdgeInsets.all(8.0),
              child: StreamBuilder(
                  stream: _streamController.stream,
                  builder: (BuildContext ctx, AsyncSnapshot snapshot) {
                    if (snapshot.data == null) {
                      return const Center(
                        child: Text("ご参考になりましたら幸いです"),
                      );
                    }
                    Future<List<Map>> queryAuto(int nextIndex) async {
                      const pageSize = 35;
                      if (nextIndex % pageSize != 0) {
                        return [];
                      }
                      Database db = await database;
                      String searchField = 'word';
                      String method = "MATCH";
                      List<Map> result = <Map>[];
                      if (snapshot.data
                          .toLowerCase()
                          .contains(RegExp(r'^[a-z]+$'))) {
                        searchField = 'romaji';
                      } else if (snapshot.data.contains(RegExp(r'^[ぁ-ゖー]+$'))) {
                        searchField = 'yomikata';
                      } else if (snapshot.data
                          .contains(RegExp(r'[\.\+\[\]\*\^\$\?]'))) {
                        method = 'REGEXP';
                      } else if (snapshot.data.contains(RegExp(r'[_%]'))) {
                        method = 'LIKE';
                      }
                      try {
                        if (method == "MATCH") {
                          result = List.of(await db.rawQuery(
                            'SELECT tt.word,tt.yomikata,tt.pitchData,'
                            'tt.origForm,tt.freqRank,tt.idex,tt.romaji,imis.imi,imis.orig '
                            'FROM (imis JOIN (SELECT * FROM jpdc '
                            'WHERE ($searchField MATCH "${snapshot.data}*" OR r$searchField '
                            'MATCH "${String.fromCharCodes(snapshot.data.runes.toList().reversed)}*") '
                            '${(_searchMode > 0 ? "AND _rowid_ >= $_searchMode" : "")} '
                            'ORDER BY _rowid_ LIMIT $nextIndex, $pageSize'
                            ') AS tt ON tt.idex=imis._rowid_)',
                          ));
                        } else {
                          result = List.of(await db.rawQuery(
                            'SELECT tt.word,tt.yomikata,tt.pitchData,'
                            'tt.origForm,tt.freqRank,tt.idex,tt.romaji,imis.imi,imis.orig '
                            'FROM (imis JOIN (SELECT * FROM jpdc '
                            'WHERE (word $method "${snapshot.data}" '
                            'OR yomikata $method "${snapshot.data}" '
                            'OR romaji $method "${snapshot.data}") '
                            '${(_searchMode > 0 ? "AND _rowid_ >= $_searchMode" : "")} '
                            'ORDER BY _rowid_ LIMIT $nextIndex, $pageSize'
                            ') AS tt ON tt.idex=imis._rowid_)',
                          ));
                        }
                        result = result.map((qRow) {
                          Map map = {};
                          qRow.forEach((key, value) => map[key] = value);
                          return map;
                        }).toList();
                        int balancedWeight(Map item, int bLen) {
                          return (item['freqRank'] *
                                  (item[searchField]
                                              .startsWith(snapshot.data) &&
                                          _searchMode == 0
                                      ? 100
                                      : 500) *
                                  pow(item['romaji'].length / bLen,
                                      _searchMode == 0 ? 2 : 0))
                              .round();
                        }

                        int bLen = 1 << 31;
                        for (var w in result) {
                          if (w['word'].length < bLen) {
                            bLen = w['word'].length;
                          }
                        }
                        result.sort((a, b) => balancedWeight(a, bLen)
                            .compareTo(balancedWeight(b, bLen)));
                        return result;
                      } catch (e) {
                        return nextIndex == 0
                            ? [
                                {
                                  'word': 'EXCEPTION',
                                  'yomikata': '以下の説明をご覧ください',
                                  'pitchData': '',
                                  'freqRank': -1,
                                  'idex': -1,
                                  'romaji': '',
                                  'orig': 'EXCEPTION',
                                  'origForm': '',
                                  'imi': jsonEncode({
                                    'ヘルプ': [
                                      "LIKE 検索:\n"
                                          "    _  任意の1文字\n"
                                          "    %  任意の0文字以上の文字列\n"
                                          "\n"
                                          "REGEX 検索:\n"
                                          "    .  任意の1文字\n"
                                          "    .*  任意の0文字以上の文字列\n"
                                          "    .+  任意の1文字以上の文字列\n"
                                          "    \\pc	任意漢字\n"
                                          "    \\ph	任意平仮名\n"
                                          "    \\pk	任意片仮名\n"
                                          "    []	候補。[]で括られた中の文字は、その中のどれか１つに合致する訳です\n"
                                          "\n"
                                          "例えば：\n"
                                          " \"ta%_eru\" は、食べる、訪ねる、立ち上げる 等\n"
                                          " \"[\\pc][\\pc\\ph]+る\" は、出来る、聞こえる、取り入れる 等\n"
                                    ],
                                    'Debug': [e.toString()],
                                  }),
                                  'expanded': true
                                }
                              ]
                            : [];
                      }
                    }

                    return InfiniteList<Map>(
                      onRequest: queryAuto,
                      itemBuilder: (context, item, index) {
                        Map<String, dynamic> imi = jsonDecode(item['imi']);
                        final String pitchData = item['pitchData'] != ''
                            ? jsonDecode(item['pitchData'])
                                .map((x) =>
                                    x <= 20 ? '⓪①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳'[x] : '?')
                                .toList()
                                .join()
                            : '';
                        final word = item['origForm'] == ''
                            ? item['word']
                            : item['origForm'];

                        return ListTileTheme(
                            dense: true,
                            child: ExpansionTile(
                                initiallyExpanded:
                                    item.containsKey('expanded') &&
                                        item['expanded'],
                                title: Text(word == item['orig']
                                    ? word
                                    : '$word →〔${item['orig']}〕'),
                                trailing: item.containsKey('expanded') &&
                                        item['freqRank'] != -1 &&
                                        item['expanded']
                                    ? Container(
                                        padding: const EdgeInsets.all(0.0),
                                        width: 35.0,
                                        child: item.containsKey('loading') &&
                                                item['loading']
                                            ? const CircularProgressIndicator()
                                            : IconButton(
                                                icon: _hatsuonCache.containsKey(
                                                            item['idex']) &&
                                                        _hatsuonCache[
                                                                item['idex']] ==
                                                            null
                                                    ? const Icon(Icons.error_outline)
                                                    : const Icon(IcoFontIcons.soundWaveAlt),
                                                onPressed: () => _hatsuon(item)))
                                    : Text(item['freqRank'].toString()),
                                subtitle: Text("${item['yomikata']} "
                                    "$pitchData"),
                                children: imi.keys
                                    .map<List<Widget>>((s) =>
                                        <Widget>[
                                          Container(
                                              decoration: BoxDecoration(
                                                  color: MyApp.isRelease
                                                      ? Colors.red[600]
                                                      : Colors.blue[400],
                                                  borderRadius:
                                                      const BorderRadius.all(
                                                          Radius.circular(20))),
                                              child: Padding(
                                                  padding:
                                                      const EdgeInsets.fromLTRB(
                                                          5, 0, 5, 0),
                                                  child: Text(
                                                    s,
                                                    style: const TextStyle(
                                                        color: Colors.white),
                                                  ))),
                                        ] +
                                        List<List<Widget>>.from(imi[s].map((simi) => <Widget>[
                                              ListTile(
                                                  title: SelectableText(simi,
                                                      toolbarOptions:
                                                          const ToolbarOptions(
                                                              copy: true,
                                                              selectAll:
                                                                  false))),
                                              const Divider(color: Colors.grey),
                                            ])).reduce((a, b) => a + b))
                                    .reduce((a, b) => a + b),
                                onExpansionChanged: (expanded) {
                                  FocusManager.instance.primaryFocus?.unfocus();
                                  setState(() => item['expanded'] = expanded);
                                }));
                      },
                      key: ValueKey('$snapshot.data $_searchMode'),
                    );
                  })),
        ));
  }
}
