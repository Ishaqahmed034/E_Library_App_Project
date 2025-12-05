// lib/main.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BookRepository.instance.init();
  runApp(const ELibraryApp());
}

// ---------------------
// Data model
// ---------------------
class Book {
  final String id; // unique id
  final String title;
  final String author;
  final String category; // e.g., Novel, History, Education, Motivation
  final String summary;
  final String content; // full book text (for demo we'll keep short)
  bool isFavorite;

  Book({
    required this.id,
    required this.title,
    required this.author,
    required this.category,
    required this.summary,
    required this.content,
    this.isFavorite = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'category': category,
    'summary': summary,
    'content': content,
    'isFavorite': isFavorite,
  };

  factory Book.fromJson(Map<String, dynamic> j) => Book(
    id: j['id'],
    title: j['title'],
    author: j['author'],
    category: j['category'],
    summary: j['summary'],
    content: j['content'],
    isFavorite: j['isFavorite'] ?? false,
  );
}

// ---------------------
// Sample books (7 items)
// ---------------------
final List<Book> sampleBooks = [
  Book(
    id: 'b1',
    title: 'The Great Gatsby',
    author: 'F. Scott Fitzgerald',
    category: 'Novel',
    summary: 'Wealth, love, and the American Dream in the 1920s.',
    content: 'Full text for The Great Gatsby (demo snippet).',
  ),
  Book(
    id: 'b2',
    title: 'To Kill a Mockingbird',
    author: 'Harper Lee',
    category: 'Novel',
    summary: 'A story exploring racial injustice in the American South.',
    content: 'Full text for To Kill a Mockingbird (demo snippet).',
  ),
  Book(
    id: 'b3',
    title: '1984',
    author: 'George Orwell',
    category: 'Novel',
    summary: 'Dystopia and totalitarianism.',
    content: 'Full text for 1984 (demo snippet).',
  ),
  Book(
    id: 'b4',
    title: 'A History of the World',
    author: 'J. M. Roberts',
    category: 'History',
    summary: 'Concise world history overview.',
    content: 'Full text for A History of the World (demo snippet).',
  ),
  Book(
    id: 'b5',
    title: 'Rich Dad Poor Dad',
    author: 'Robert Kiyosaki',
    category: 'Finance / Motivation',
    summary: 'Personal finance & mindset book.',
    content: 'Full text for Rich Dad Poor Dad (demo snippet).',
  ),
  Book(
    id: 'b6',
    title: 'How to Win Friends & Influence People',
    author: 'Dale Carnegie',
    category: 'Education / Self-help',
    summary: 'Classic guide to people skills.',
    content: 'Full text for How to Win Friends (demo snippet).',
  ),
  Book(
    id: 'b7',
    title: 'Atomic Habits',
    author: 'James Clear',
    category: 'Motivation / Education',
    summary: 'Small habits, big changes.',
    content: 'Full text for Atomic Habits (demo snippet).',
  ),
];

// ---------------------
// Repository: local persistence (shared_preferences)
// - Stores favorites, downloaded book ids, trashed book ids
// - For production use sqflite or remote backend
// ---------------------
class BookRepository {
  static final BookRepository instance = BookRepository._internal();
  BookRepository._internal();

  late SharedPreferences _prefs;
  final String _favKey = 'favorites_v1';
  final String _downloadKey = 'downloads_v1';
  final String _trashKey = 'trash_v1';
  final String _booksKey = 'books_v1';

  List<Book> books = [];

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    // Initialize books: either persist sample or load from prefs
    if (!_prefs.containsKey(_booksKey)) {
      // Save sample to prefs
      final enc = jsonEncode(sampleBooks.map((b) => b.toJson()).toList());
      await _prefs.setString(_booksKey, enc);
    }

    // load books
    final stored = _prefs.getString(_booksKey)!;
    final List parsed = jsonDecode(stored);
    books = parsed.map((j) => Book.fromJson(j)).toList();

    // Apply favorites from fav list
    final favList = _prefs.getStringList(_favKey) ?? [];
    for (var b in books) {
      b.isFavorite = favList.contains(b.id);
    }
  }

  Future<void> toggleFavorite(String id) async {
    final b = books.firstWhere((x) => x.id == id);
    b.isFavorite = !b.isFavorite;
    final favs = books.where((x) => x.isFavorite).map((x) => x.id).toList();
    await _prefs.setStringList(_favKey, favs);
    await _saveBooks();
  }

  Future<void> downloadBook(String id) async {
    final downloads = _prefs.getStringList(_downloadKey) ?? [];
    if (!downloads.contains(id)) {
      downloads.add(id);
      await _prefs.setStringList(_downloadKey, downloads);
    }
  }

  Future<List<Book>> getDownloadedBooks() async {
    final downloads = _prefs.getStringList(_downloadKey) ?? [];
    return books.where((b) => downloads.contains(b.id)).toList();
  }

  Future<void> moveToTrash(String id) async {
    final trash = _prefs.getStringList(_trashKey) ?? [];
    if (!trash.contains(id)) {
      trash.add(id);
      await _prefs.setStringList(_trashKey, trash);
    }
  }

  Future<List<Book>> getTrashedBooks() async {
    final trash = _prefs.getStringList(_trashKey) ?? [];
    return books.where((b) => trash.contains(b.id)).toList();
  }

  Future<void> restoreFromTrash(String id) async {
    final trash = _prefs.getStringList(_trashKey) ?? [];
    trash.remove(id);
    await _prefs.setStringList(_trashKey, trash);
  }

  Future<void> deletePermanently(String id) async {
    // remove from all lists and from books
    books.removeWhere((b) => b.id == id);
    await _prefs.setStringList(_favKey, books.where((b) => b.isFavorite).map((b) => b.id).toList());
    final downloads = _prefs.getStringList(_downloadKey) ?? [];
    downloads.remove(id);
    await _prefs.setStringList(_downloadKey, downloads);
    final trash = _prefs.getStringList(_trashKey) ?? [];
    trash.remove(id);
    await _prefs.setStringList(_trashKey, trash);
    await _saveBooks();
  }

  Future<void> _saveBooks() async {
    final enc = jsonEncode(books.map((b) => b.toJson()).toList());
    await _prefs.setString(_booksKey, enc);
  }

  // Search local books by title/author/category
  List<Book> search(String query) {
    final q = query.toLowerCase();
    return books.where((b) {
      return b.title.toLowerCase().contains(q) ||
          b.author.toLowerCase().contains(q) ||
          b.category.toLowerCase().contains(q);
    }).toList();
  }
}

// ---------------------
// App Widget + Routing
// ---------------------
class ELibraryApp extends StatelessWidget {
  const ELibraryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'E-Library App',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (ctx) => const LoginScreen(),
        '/books': (ctx) => const BookListScreen(),
        '/downloads': (ctx) => const DownloadsScreen(),
      },
    );
  }
}

// ---------------------
// Login / Signup Screen
// (simple local forms for demo)
// ---------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  String _email = '';
  String _password = '';
  bool _isLogin = true; // toggle login/signup

  void _submit() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      // For demo: accept any credentials
      Navigator.of(context).pushReplacementNamed('/books');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isLogin ? 'Logged in as $_email' : 'Signed up as $_email')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('E-Library Login'),
        centerTitle: true,
      ),
      body: Center(
        child: Card(
          margin: const EdgeInsets.all(20),
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_isLogin ? 'Welcome Back' : 'Create Account',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => (v == null || !v.contains('@')) ? 'Enter valid email' : null,
                      onSaved: (v) => _email = v!.trim(),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Password'),
                      obscureText: true,
                      validator: (v) => (v == null || v.length < 4) ? 'Min 4 chars' : null,
                      onSaved: (v) => _password = v!.trim(),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _submit,
                      child: Text(_isLogin ? 'Login' : 'Sign up'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _isLogin = !_isLogin),
                      child: Text(_isLogin ? "Create account" : "Have an account? Login"),
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------
// Book List Screen (search, categories, favorites filter)
// ---------------------
class BookListScreen extends StatefulWidget {
  const BookListScreen({super.key});

  @override
  State<BookListScreen> createState() => _BookListScreenState();
}

class _BookListScreenState extends State<BookListScreen> {
  String _search = '';
  String _selectedCategory = 'All';
  bool _favoritesOnly = false;

  List<String> get categories {
    final cats = {'All'}..addAll(BookRepository.instance.books.map((b) => b.category));
    return cats.toList();
  }

  @override
  Widget build(BuildContext context) {
    List<Book> list = BookRepository.instance.books;
    if (_selectedCategory != 'All') {
      list = list.where((b) => b.category == _selectedCategory).toList();
    }
    if (_search.isNotEmpty) {
      list = BookRepository.instance.search(_search);
    }
    if (_favoritesOnly) {
      list = list.where((b) => b.isFavorite).toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Digital Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Downloads',
            onPressed: () => Navigator.of(context).pushNamed('/downloads'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search by title, author, category...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.search_off),
                  tooltip: 'Search on Google',
                  onPressed: () async {
                    final q = Uri.encodeComponent(_search.isEmpty ? 'books' : _search);
                    final url = 'https://www.google.com/search?q=$q';
                    if (await canLaunchUrl(Uri.parse(url))) {
                      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Cannot open browser')),
                      );
                    }
                  },
                ),
              ],
            ),
          ),

          // Categories and favorite toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                DropdownButton<String>(
                  value: _selectedCategory,
                  items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setState(() => _selectedCategory = v!),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(_favoritesOnly ? Icons.favorite : Icons.favorite_border),
                  onPressed: () => setState(() => _favoritesOnly = !_favoritesOnly),
                  tooltip: _favoritesOnly ? 'Showing favorites' : 'Show favorites only',
                ),
              ],
            ),
          ),

          // Book list
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (ctx, i) {
                final book = list[i];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: ListTile(
                    title: Text(book.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${book.author} • ${book.category}'),
                    trailing: IconButton(
                      icon: Icon(book.isFavorite ? Icons.favorite : Icons.favorite_border,
                          color: book.isFavorite ? Colors.red : null),
                      onPressed: () async {
                        await BookRepository.instance.toggleFavorite(book.id);
                        setState(() {});
                      },
                    ),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => BookDetailScreen(bookId: book.id)),
                      );
                      setState(() {}); // refresh after returning
                    },
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

// ---------------------
// Book Detail Screen
// - Show full content
// - Favorite toggle, Download, Trash/Delete
// ---------------------
class BookDetailScreen extends StatefulWidget {
  final String bookId;
  const BookDetailScreen({super.key, required this.bookId});

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  late Book book;

  @override
  void initState() {
    super.initState();
    book = BookRepository.instance.books.firstWhere((b) => b.id == widget.bookId);
  }

  Future<void> _toggleFavorite() async {
    await BookRepository.instance.toggleFavorite(book.id);
    setState(() {
      book = BookRepository.instance.books.firstWhere((b) => b.id == widget.bookId);
    });
  }

  Future<void> _download() async {
    await BookRepository.instance.downloadBook(book.id);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Book downloaded')));
  }

  Future<void> _moveToTrash() async {
    await BookRepository.instance.moveToTrash(book.id);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Moved to trash')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final downloadedFuture = BookRepository.instance.getDownloadedBooks();
    return Scaffold(
      appBar: AppBar(
        title: Text(book.title),
        actions: [
          IconButton(
            icon: Icon(book.isFavorite ? Icons.favorite : Icons.favorite_border),
            onPressed: _toggleFavorite,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Move to Trash',
            onPressed: _moveToTrash,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(book.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Author: ${book.author}', style: const TextStyle(fontStyle: FontStyle.italic)),
          const SizedBox(height: 12),
          Text('Category: ${book.category}', style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
          const Text('Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Divider(),
          Text(book.summary, style: const TextStyle(height: 1.5)),
          const SizedBox(height: 20),
          const Text('Content', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Divider(),
          Text(book.content, style: const TextStyle(height: 1.6)),
          const SizedBox(height: 30),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _download,
                  icon: const Icon(Icons.download),
                  label: const Text('Download'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    // For demo: open a quick reader that just shows the same content
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ReaderScreen(title: book.title, content: book.content)));
                  },
                  icon: const Icon(Icons.menu_book),
                  label: const Text('Read'),
                ),
              ),
            ],
          ),
        ]),
      ),
    );
  }
}

// ---------------------
// Reader screen (simple full-screen reader)
// ---------------------
class ReaderScreen extends StatelessWidget {
  final String title;
  final String content;
  const ReaderScreen({super.key, required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Reading: $title')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SelectableText(content, style: const TextStyle(height: 1.6)),
      ),
    );
  }
}

// ---------------------
// Downloads / Trash screen
// ---------------------
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  Future<List<Book>>? _downloadsFuture;
  Future<List<Book>>? _trashFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _downloadsFuture = BookRepository.instance.getDownloadedBooks();
    _trashFuture = BookRepository.instance.getTrashedBooks();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads & Trash'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const Text('Downloaded Books', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            FutureBuilder<List<Book>>(
              future: _downloadsFuture,
              builder: (ctx, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final list = snap.data!;
                if (list.isEmpty) return const Text('No downloads yet.');
                return Column(
                  children: list
                      .map((b) => ListTile(
                    title: Text(b.title),
                    subtitle: Text(b.author),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () async {
                        await BookRepository.instance.moveToTrash(b.id);
                        _refresh();
                      },
                    ),
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ReaderScreen(title: b.title, content: b.content)));
                    },
                  ))
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 20),
            const Text('Trash', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            FutureBuilder<List<Book>>(
              future: _trashFuture,
              builder: (ctx, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final list = snap.data!;
                if (list.isEmpty) return const Text('Trash is empty');
                return Column(
                  children: list
                      .map((b) => ListTile(
                    title: Text(b.title),
                    subtitle: Text(b.author),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.restore),
                        onPressed: () async {
                          await BookRepository.instance.restoreFromTrash(b.id);
                          _refresh();
                        },
                        tooltip: 'Restore',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_forever),
                        onPressed: () async {
                          await BookRepository.instance.deletePermanently(b.id);
                          _refresh();
                        },
                        tooltip: 'Delete permanently',
                      ),
                    ]),
                  ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
