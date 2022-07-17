import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:clipboard_listener/clipboard_listener.dart';
import 'package:flutter_js/flutter_js.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ある辞書',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSwatch().copyWith(
          primary: Colors.pink[300],
          secondary: Colors.pinkAccent[100],
        ),
      ),
      home: const MyHomePage(),
    );
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
  int _searchMode = 0;
  Timer? _debounce;
  static Database? _db;
  Future<Database> get database async {
    if (_db != null) return _db!;

    var databasesPath = await getDatabasesPath();
    var path = join(databasesPath, "arujisho.db");

    var exists = await databaseExists(path);

    if (!exists) {
      try {
        await Directory(dirname(path)).create(recursive: true);
      } catch (_) {}

      ByteData data = await rootBundle.load("db/arujisho.db");
      List<int> bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

      await File(path).writeAsBytes(bytes, flush: true);
    }
    _db = await openDatabase(path, readOnly: true);
    return _db!;
  }

  static JavascriptRuntime? _fjs;
  Future<JavascriptRuntime> get flutterJs async {
    if (_fjs != null) return _fjs!;
    JavascriptRuntime t = getJavascriptRuntime();
    String openccJS = await rootBundle.loadString("js/opencc.js");
    t.evaluate(openccJS);
    t.evaluate("""const converter = Converter({from:'cn', to:'jp'});""");
    _fjs = t;
    return _fjs!;
  }

  _search(int mode) async {
    if (_controller.text.isEmpty) {
      _streamController.add(null);
      return;
    }
    _searchMode = mode;
    JavascriptRuntime t = await flutterJs;
    String s = _controller.text;
    s = s.replaceAll("\\pc", "\\p{Han}");
    s = s.replaceAll("\\ph", "\\p{Hiragana}");
    s = s.replaceAll("\\pk", "\\p{Katakana}");
    s = t.evaluate('converter(${json.encode(s)})').stringResult;
    _streamController.add(s);
  }

  _cpListener() async {
    String cp = (await Clipboard.getData('text/plain'))!.text ?? '';
    if (cp == _controller.text) {
      return;
    }
    _history.add(_controller.text);
    _controller.value = TextEditingValue(
        text: cp,
        selection: TextSelection.fromPosition(TextPosition(offset: cp.length)));
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
    _fjs?.dispose();
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
          _controller.value = TextEditingValue(
              text: temp,
              selection: TextSelection.fromPosition(
                  TextPosition(offset: temp.length)));
          return false;
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text("ある辞書"),
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
                  IconButton(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    icon: const Icon(
                      Icons.filter_list,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      _search(1);
                    },
                  )
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
                      Database db = await database;
                      const pageSize = 35;
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
                            'SELECT tt.word,tt.yomikata,tt.pitchData,tt.freqRank,tt.romaji,imis.imi,imis.orig '
                            'FROM (imis JOIN (SELECT * FROM jpdc '
                            'WHERE $searchField MATCH "${snapshot.data}*" OR r$searchField '
                            'MATCH "${String.fromCharCodes(snapshot.data.runes.toList().reversed)}*" '
                            'ORDER BY _rowid_ LIMIT $nextIndex, $pageSize'
                            ') AS tt ON tt.idex=imis._rowid_)',
                          ));
                        } else {
                          result = List.of(await db.rawQuery(
                            'SELECT tt.word,tt.yomikata,tt.pitchData,tt.freqRank,tt.romaji,imis.imi,imis.orig '
                            'FROM (imis JOIN (SELECT * FROM jpdc '
                            'WHERE word $method "${snapshot.data}" '
                            'OR yomikata $method "${snapshot.data}" '
                            'OR romaji $method "${snapshot.data}" '
                            'ORDER BY _rowid_ LIMIT $nextIndex, $pageSize'
                            ') AS tt ON tt.idex=imis._rowid_)',
                          ));
                        }
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
                                  'romaji': '',
                                  'orig': 'EXCEPTION',
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
                                      "    [\\pc]	候補。任意漢字\n"
                                      "    [\\ph]	候補。任意平仮名\n"
                                      "    [\\pk]	候補。任意片仮名\n"
                                      "    [あいう\\pc]	候補。あ,い,う,任意漢字のいずれか1字\n"
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
                        return ListTileTheme(
                            dense: true,
                            child: ExpansionTile(
                              initiallyExpanded: item.containsKey('expanded') &&
                                  item['expanded'],
                              title: Text(item['word'] == item['orig']
                                  ? item['word']
                                  : '${item['word']} →〔${item['orig']}〕'),
                              trailing: Text(item['freqRank'].toString()),
                              subtitle: Text("${item['yomikata']} "
                                  "${item['pitchData'] != '' ? item['pitchData'] : ''}"),
                              children: imi.keys
                                  .map<List<Widget>>((s) =>
                                      <Widget>[
                                        Container(
                                            decoration: BoxDecoration(
                                                color: Colors.blue[600],
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
                                      List<List<Widget>>.from(
                                          imi[s].map((simi) => <Widget>[
                                                ListTile(
                                                    title: SelectableText(simi,
                                                        toolbarOptions:
                                                            const ToolbarOptions(
                                                                copy: true,
                                                                selectAll:
                                                                    false))),
                                                const Divider(
                                                    color: Colors.grey),
                                              ])).reduce((a, b) => a + b))
                                  .reduce((a, b) => a + b),
                              onExpansionChanged: (_) =>
                                  FocusManager.instance.primaryFocus?.unfocus(),
                            ));
                      },
                      key: ValueKey('$snapshot.data $_searchMode'),
                    );
                  })),
        ));
  }
}
