import 'dart:convert';
import 'dart:io';

import 'package:birdle/game.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'summary.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Align(
            alignment: Alignment.centerLeft,
            child: Text("Birdle"),
          ),
        ),
        body: const Center(child: GamePage()),
      ),
    );
  }
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  final Game _game = Game();
  late final ArticleViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    // Initialize the ViewModel here so we can pass it down
    _viewModel = ArticleViewModel(ArticleModel());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          // Game Board
          for (var guess in _game.guesses)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var letter in guess)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2.5,
                      vertical: 2.5,
                    ),
                    child: Tile(letter.char, letter.type),
                  ),
              ],
            ),

          // Input Section
          GuessInput(
            onSubmitGuess: (String guess) {
              setState(() {
                _game.guess(guess);
              });
              // Fetch the article based on the inputted word
              _viewModel.fetchArticle(guess);
            },
          ),

          // Article Display Section (Fills remaining space)
          Expanded(child: ArticleView(viewModel: _viewModel)),
        ],
      ),
    );
  }
}

class GuessInput extends StatefulWidget {
  final void Function(String) onSubmitGuess;

  const GuessInput({super.key, required this.onSubmitGuess});

  @override
  State<GuessInput> createState() => _GuessInputState();
}

class _GuessInputState extends State<GuessInput> {
  final TextEditingController _textEditingController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    // Properly dispose of controllers to prevent memory leaks
    _textEditingController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSubmit() {
    final text = _textEditingController.text.trim();
    if (text.isNotEmpty) {
      widget.onSubmitGuess(text);
      _textEditingController.clear();
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _textEditingController,
              focusNode: _focusNode,
              onSubmitted: (_) => _onSubmit(),
              autofocus: true,
              maxLength: 5,
              decoration: const InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(35)),
                ),
              ),
            ),
          ),
        ),
        IconButton(
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.arrow_circle_up),
          onPressed: _onSubmit,
        ),
      ],
    );
  }
}

class ArticleView extends StatelessWidget {
  final ArticleViewModel viewModel;

  // Takes the ViewModel as a parameter rather than managing its own state
  const ArticleView({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    // Removed the Scaffold here so it doesn't break constraints
    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) {
          return switch ((
            viewModel.isLoading,
            viewModel.summary,
            viewModel.error,
          )) {
            (true, _, _) => const Center(child: CircularProgressIndicator()),
            (_, final summary?, _) => ArticlePage(summary: summary),
            (_, _, final Exception e) => Center(child: Text('Error: $e')),
            _ => const Center(
              child: Text('Enter a word to see its Wikipedia article!'),
            ),
          };
        },
      ),
    );
  }
}

class ArticlePage extends StatelessWidget {
  const ArticlePage({super.key, required this.summary});

  final Summary summary;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(children: [ArticleWidget(summary: summary)]),
    );
  }
}

class ArticleWidget extends StatelessWidget {
  const ArticleWidget({super.key, required this.summary});

  final Summary summary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        spacing: 10.0,
        children: [
          if (summary.hasImage) Image.network(summary.originalImage!.source),
          Text(
            summary.titles.normalized,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.displaySmall,
          ),
          if (summary.description != null)
            Text(
              summary.description!,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          Text(summary.extract),
        ],
      ),
    );
  }
}

class Tile extends StatelessWidget {
  const Tile(this.letter, this.hitType, {super.key});

  final String letter;
  final HitType hitType;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.linear,
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        border: Border.all(),
        color: switch (hitType) {
          HitType.hit => Colors.green,
          HitType.partial => Colors.yellow,
          HitType.miss => Colors.grey,
          _ => Colors.white,
        },
      ),
      child: Center(
        child: Text(
          letter.toUpperCase(),
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    );
  }
}

class ArticleModel {
  // Updated to fetch a specific article based on the word provided
  Future<Summary> getArticleSummary(String title) async {
    final uri = Uri.https(
      'en.wikipedia.org',
      '/api/rest_v1/page/summary/$title',
    );
    final response = await http.get(uri);

    if (response.statusCode == 404) {
      throw Exception('Article not found for "$title".');
    } else if (response.statusCode != 200) {
      throw const HttpException('Failed to update resource');
    }

    return Summary.fromJson(jsonDecode(response.body));
  }
}

class ArticleViewModel extends ChangeNotifier {
  final ArticleModel model;
  Summary? summary;
  Exception? error;
  bool isLoading = false;

  ArticleViewModel(this.model);

  // Added 'word' parameter to fetch specifically requested articles
  Future<void> fetchArticle(String word) async {
    isLoading = true;
    error = null;
    notifyListeners();

    try {
      summary = await model.getArticleSummary(word);
      print('Article loaded: ${summary!.titles.normalized}');
    } on Exception catch (e) {
      error = e;
      summary = null;
    }

    isLoading = false;
    notifyListeners();
  }
}
