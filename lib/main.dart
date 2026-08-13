import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

const String libraryBoxName = 'mangashelf_library';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  await Hive.openBox(libraryBoxName);

  runApp(const MangaShelfApp());
}

class MangaShelfApp extends StatefulWidget {
  const MangaShelfApp({super.key});

  @override
  State<MangaShelfApp> createState() =>
      _MangaShelfAppState();
}

class _MangaShelfAppState extends State<MangaShelfApp> {
  bool isDarkMode = true;

  void setDarkMode(bool value) {
    setState(() {
      isDarkMode = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme lightScheme =
        ColorScheme.fromSeed(
      seedColor: Colors.deepPurple,
      brightness: Brightness.light,
    );

    final ColorScheme darkScheme =
        ColorScheme.fromSeed(
      seedColor: Colors.deepPurple,
      brightness: Brightness.dark,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MangaShelf',
      themeMode:
          isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: lightScheme,
        scaffoldBackgroundColor:
            const Color(0xFFF5F3F8),
        cardColor: Colors.white,
        dividerColor:
            const Color(0xFFE1DDE8),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: darkScheme,
        scaffoldBackgroundColor:
            const Color(0xFF0A0B12),
        cardColor:
            const Color(0xFF151822),
        dividerColor:
            const Color(0xFF242734),
        useMaterial3: true,
      ),
      home: LibraryScreen(
        isDarkMode: isDarkMode,
        onThemeChanged: setDarkMode,
      ),
    );
  }
}

class MangaPage {
  final String name;
  final Uint8List bytes;

  MangaPage({
    required this.name,
    required this.bytes,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'bytes': bytes,
    };
  }

  factory MangaPage.fromMap(Map<dynamic, dynamic> map) {
    return MangaPage(
      name: map['name']?.toString() ?? 'Página',
      bytes: bytesFromDynamic(map['bytes']),
    );
  }
}

class MangaItem {
  final String id;
  final String title;
  final String fileName;
  final String author;
  final String format;
  final Uint8List coverBytes;
  final List<MangaPage> pages;

  int lastPage;

  MangaItem({
    required this.id,
    required this.title,
    required this.fileName,
    required this.pages,
    this.author = '',
    this.format = 'CBZ',
    Uint8List? coverBytes,
    this.lastPage = -1,
  }) : coverBytes = coverBytes ?? Uint8List(0);

  Uint8List get cover {
    if (coverBytes.isNotEmpty) {
      return coverBytes;
    }

    if (pages.isNotEmpty) {
      return pages.first.bytes;
    }

    return Uint8List(0);
  }

  bool get hasStarted => lastPage >= 0;

  bool get isFinished =>
      pages.isNotEmpty && lastPage >= pages.length - 1;

  double get progress {
    if (!hasStarted || pages.isEmpty) {
      return 0;
    }

    return (lastPage + 1) / pages.length;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'fileName': fileName,
      'author': author,
      'format': format,
      'coverBytes': coverBytes,
      'lastPage': lastPage,
      'pages': pages.map((page) => page.toMap()).toList(),
    };
  }

  factory MangaItem.fromMap(Map<dynamic, dynamic> map) {
    final List<MangaPage> pages = [];

    final dynamic rawPages = map['pages'];

    if (rawPages is List) {
      for (final dynamic rawPage in rawPages) {
        if (rawPage is Map) {
          pages.add(MangaPage.fromMap(rawPage));
        }
      }
    }

    int lastPage = -1;

    final dynamic rawLastPage = map['lastPage'];

    if (rawLastPage is int) {
      lastPage = rawLastPage;
    } else if (rawLastPage is num) {
      lastPage = rawLastPage.toInt();
    }

    if (pages.isNotEmpty && lastPage >= pages.length) {
      lastPage = pages.length - 1;
    }

    return MangaItem(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Mangá',
      fileName: map['fileName']?.toString() ?? '',
      author: map['author']?.toString() ?? '',
      format: map['format']?.toString() ?? 'CBZ',
      coverBytes: bytesFromDynamic(map['coverBytes']),
      pages: pages,
      lastPage: lastPage,
    );
  }
}

class EpubData {
  final String title;
  final String author;
  final Uint8List cover;
  final List<MangaPage> pages;

  EpubData({
    required this.title,
    required this.author,
    required this.cover,
    required this.pages,
  });
}

Uint8List bytesFromDynamic(dynamic value) {
  if (value is Uint8List) {
    return value;
  }

  if (value is List<int>) {
    return Uint8List.fromList(value);
  }

  if (value is List) {
    return Uint8List.fromList(value.cast<int>());
  }

  return Uint8List(0);
}

Uint8List archiveFileBytes(ArchiveFile file) {
  return bytesFromDynamic(file.content);
}

String decodeArchiveText(ArchiveFile file) {
  final Uint8List bytes = archiveFileBytes(file);

  return utf8.decode(
    bytes,
    allowMalformed: true,
  );
}

String decodeXmlEntities(String text) {
  return text
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}

ArchiveFile? findArchiveFile(
  Archive archive,
  String path,
) {
  final String normalized = path.replaceAll('\\', '/');

  for (final ArchiveFile file in archive) {
    if (file.name.replaceAll('\\', '/') == normalized) {
      return file;
    }
  }

  return null;
}

bool isImageFile(String path) {
  final String lower = path.toLowerCase();

  return lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.webp');
}

String resolveEpubPath(
  String baseFile,
  String relativePath,
) {
  final Uri base = Uri.parse(baseFile);

  return base.resolve(relativePath).path;
}

String? regexValue(
  String text,
  RegExp regex,
) {
  final Match? match = regex.firstMatch(text);

  if (match == null) {
    return null;
  }

  return match.group(1);
}

String seriesTitleFromTitle(String title) {
  String result = title.replaceAll(
    RegExp(
      r'\s*Vol\.?\s*\d+.*$',
      caseSensitive: false,
    ),
    '',
  );

  result = result.trim();

  return result.isEmpty ? title : result;
}

EpubData parseEpub(
  Archive archive,
  String fallbackTitle,
) {
  String opfPath = 'OEBPS/content.opf';

  final ArchiveFile? containerFile = findArchiveFile(
    archive,
    'META-INF/container.xml',
  );

  if (containerFile != null) {
    final String containerXml = decodeArchiveText(containerFile);

    final String? foundPath = regexValue(
      containerXml,
      RegExp(
        r'''full-path=["']([^"']+)''',
        caseSensitive: false,
      ),
    );

    if (foundPath != null && foundPath.isNotEmpty) {
      opfPath = foundPath;
    }
  }

  final ArchiveFile? opfFile = findArchiveFile(
    archive,
    opfPath,
  );

  if (opfFile == null) {
    throw Exception(
      'EPUB inválido: content.opf não encontrado.',
    );
  }

  final String opf = decodeArchiveText(opfFile);

  String title =
      regexValue(
        opf,
        RegExp(
          r'<dc:title[^>]*>(.*?)</dc:title>',
          caseSensitive: false,
          dotAll: true,
        ),
      ) ??
      fallbackTitle;

  String author =
      regexValue(
        opf,
        RegExp(
          r'<dc:creator[^>]*>(.*?)</dc:creator>',
          caseSensitive: false,
          dotAll: true,
        ),
      ) ??
      '';

  title = decodeXmlEntities(title.trim());
  author = decodeXmlEntities(author.trim());

  final Map<String, String> manifest = {};

  final RegExp itemRegex = RegExp(
    r'<item\s+([^>]+?)/?>',
    caseSensitive: false,
  );

  for (final Match match in itemRegex.allMatches(opf)) {
    final String attributes = match.group(1) ?? '';

    final String? id = regexValue(
      attributes,
      RegExp(
        r'''id=["']([^"']+)''',
        caseSensitive: false,
      ),
    );

    final String? href = regexValue(
      attributes,
      RegExp(
        r'''href=["']([^"']+)''',
        caseSensitive: false,
      ),
    );

    if (id != null && href != null) {
      manifest[id] = href;
    }
  }

  Uint8List coverBytes = Uint8List(0);

  final String? coverId = regexValue(
    opf,
    RegExp(
      r'''<meta[^>]+name=["']cover["'][^>]+content=["']([^"']+)''',
      caseSensitive: false,
    ),
  );

  String? coverHref;

  if (coverId != null) {
    coverHref = manifest[coverId];
  }

  if (coverHref != null) {
    final String coverPath = resolveEpubPath(
      opfPath,
      coverHref,
    );

    final ArchiveFile? coverFile = findArchiveFile(
      archive,
      coverPath,
    );

    if (coverFile != null) {
      coverBytes = archiveFileBytes(coverFile);
    }
  }

  if (coverBytes.isEmpty) {
    for (final ArchiveFile file in archive) {
      final String lower = file.name.toLowerCase();

      if (file.isFile &&
          isImageFile(lower) &&
          lower.contains('cover')) {
        coverBytes = archiveFileBytes(file);
        break;
      }
    }
  }

  final List<String> spineIds = [];

  final RegExp spineRegex = RegExp(
    r'''<itemref[^>]+idref=["']([^"']+)''',
    caseSensitive: false,
  );

  for (final Match match in spineRegex.allMatches(opf)) {
    final String? idref = match.group(1);

    if (idref != null) {
      spineIds.add(idref);
    }
  }

  final List<MangaPage> pages = [];
  final Set<String> addedImages = {};

  for (final String idref in spineIds) {
    final String? href = manifest[idref];

    if (href == null) {
      continue;
    }

    final String xhtmlPath = resolveEpubPath(
      opfPath,
      href,
    );

    final ArchiveFile? xhtmlFile = findArchiveFile(
      archive,
      xhtmlPath,
    );

    if (xhtmlFile == null) {
      continue;
    }

    final String xhtml = decodeArchiveText(xhtmlFile);

    String? imageReference;

    imageReference = regexValue(
      xhtml,
      RegExp(
        r'''<img[^>]+src=["']([^"']+)''',
        caseSensitive: false,
      ),
    );

    imageReference ??= regexValue(
      xhtml,
      RegExp(
        r'''<image[^>]+(?:href|xlink:href)=["']([^"']+)''',
        caseSensitive: false,
      ),
    );

    if (imageReference == null) {
      continue;
    }

    imageReference = imageReference.split('#').first;

    final String imagePath = resolveEpubPath(
      xhtmlPath,
      imageReference,
    );

    if (addedImages.contains(imagePath)) {
      continue;
    }

    final ArchiveFile? imageFile = findArchiveFile(
      archive,
      imagePath,
    );

    if (imageFile == null ||
        !imageFile.isFile ||
        !isImageFile(imagePath)) {
      continue;
    }

    final Uint8List bytes = archiveFileBytes(imageFile);

    if (bytes.isEmpty) {
      continue;
    }

    addedImages.add(imagePath);

    pages.add(
      MangaPage(
        name: imagePath,
        bytes: bytes,
      ),
    );
  }

  if (pages.isEmpty) {
    final List<ArchiveFile> images = archive.files
        .where(
          (file) =>
              file.isFile &&
              isImageFile(file.name) &&
              !file.name.toLowerCase().contains('cover'),
        )
        .toList();

    images.sort(
      (a, b) => naturalCompareStatic(
        a.name.toLowerCase(),
        b.name.toLowerCase(),
      ),
    );

    for (final ArchiveFile file in images) {
      final Uint8List bytes = archiveFileBytes(file);

      if (bytes.isEmpty) {
        continue;
      }

      pages.add(
        MangaPage(
          name: file.name,
          bytes: bytes,
        ),
      );
    }
  }

  if (pages.isEmpty) {
    throw Exception(
      'Nenhuma página de imagem foi encontrada no EPUB.',
    );
  }

  if (coverBytes.isEmpty) {
    coverBytes = pages.first.bytes;
  }

  return EpubData(
    title: title,
    author: author,
    cover: coverBytes,
    pages: pages,
  );
}

int naturalCompareStatic(
  String a,
  String b,
) {
  final RegExp regex = RegExp(r'(\d+)|(\D+)');

  final List<String> partsA = regex
      .allMatches(a)
      .map((match) => match.group(0)!)
      .toList();

  final List<String> partsB = regex
      .allMatches(b)
      .map((match) => match.group(0)!)
      .toList();

  final int length =
      partsA.length < partsB.length ? partsA.length : partsB.length;

  for (int i = 0; i < length; i++) {
    final int? numberA = int.tryParse(partsA[i]);
    final int? numberB = int.tryParse(partsB[i]);

    if (numberA != null && numberB != null) {
      final int comparison = numberA.compareTo(numberB);

      if (comparison != 0) {
        return comparison;
      }
    } else {
      final int comparison = partsA[i].compareTo(partsB[i]);

      if (comparison != 0) {
        return comparison;
      }
    }
  }

  return partsA.length.compareTo(partsB.length);
}


class SeriesGroup {
  final String name;
  final List<MangaItem> volumes;

  SeriesGroup({
    required this.name,
    required this.volumes,
  });

  String get author {
    for (final volume in volumes) {
      if (volume.author.trim().isNotEmpty) {
        return volume.author.trim();
      }
    }
    return '';
  }

  int get totalPages =>
      volumes.fold(0, (sum, volume) => sum + volume.pages.length);

  int get startedVolumes =>
      volumes.where((volume) => volume.hasStarted).length;

  int get finishedVolumes =>
      volumes.where((volume) => volume.isFinished).length;

  bool get hasProgress => startedVolumes > 0;

  double get progress {
    if (volumes.isEmpty) {
      return 0;
    }

    double sum = 0;

    for (final volume in volumes) {
      sum += volume.progress;
    }

    return (sum / volumes.length).clamp(0.0, 1.0);
  }

  MangaItem get fallbackCoverVolume {
    final sorted = [...volumes]
      ..sort(
        (a, b) => volumeNumber(b.title)
            .compareTo(volumeNumber(a.title)),
      );

    return sorted.first;
  }

  MangaItem? get currentVolume {
    final started = volumes
        .where(
          (volume) =>
              volume.hasStarted &&
              !volume.isFinished,
        )
        .toList()
      ..sort(
        (a, b) => volumeNumber(a.title)
            .compareTo(volumeNumber(b.title)),
      );

    if (started.isNotEmpty) {
      return started.first;
    }

    final unread = volumes
        .where((volume) => !volume.hasStarted)
        .toList()
      ..sort(
        (a, b) => volumeNumber(a.title)
            .compareTo(volumeNumber(b.title)),
      );

    if (unread.isNotEmpty) {
      return unread.first;
    }

    final sorted = [...volumes]
      ..sort(
        (a, b) => volumeNumber(b.title)
            .compareTo(volumeNumber(a.title)),
      );

    return sorted.isEmpty ? null : sorted.first;
  }
}

int volumeNumber(String title) {
  final match = RegExp(
    r'(?:vol(?:ume)?\.?\s*)(\d+)',
    caseSensitive: false,
  ).firstMatch(title);

  if (match == null) {
    return 0;
  }

  return int.tryParse(match.group(1) ?? '') ?? 0;
}

String normalizedSeriesName(String title) {
  var name = title.replaceAll(
    RegExp(
      r'\s*[-–—]?\s*vol(?:ume)?\.?\s*\d+.*$',
      caseSensitive: false,
    ),
    '',
  );

  name = name.replaceAll(
    RegExp(r'\s+'),
    ' ',
  );

  return name.trim().isEmpty ? title.trim() : name.trim();
}

String volumeLabel(MangaItem manga) {
  final number = volumeNumber(manga.title);

  if (number > 0) {
    return 'Vol. $number';
  }

  return manga.title;
}

String formatInteger(int value) {
  final text = value.toString();
  final buffer = StringBuffer();

  for (int i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) {
      buffer.write('.');
    }

    buffer.write(text[i]);
  }

  return buffer.toString();
}

const String haikyuuSeriesCoverUrl =
    'https://m.media-amazon.com/images/I/814zeD6s4HS.jpg';

Widget seriesCoverImage(
  SeriesGroup series, {
  BoxFit fit = BoxFit.cover,
}) {
  final lower = series.name.toLowerCase();

  if (lower.contains('haikyu')) {
    return Image.network(
      haikyuuSeriesCoverUrl,
      fit: fit,
      errorBuilder: (
        context,
        error,
        stackTrace,
      ) {
        return Image.memory(
          series.fallbackCoverVolume.cover,
          fit: fit,
          gaplessPlayback: true,
        );
      },
    );
  }

  return Image.memory(
    series.fallbackCoverVolume.cover,
    fit: fit,
    gaplessPlayback: true,
  );
}

enum LibrarySection {
  library,
  reading,
  settings,
}

class LibraryScreen extends StatefulWidget {
  final bool isDarkMode;
  final ValueChanged<bool> onThemeChanged;

  const LibraryScreen({
    super.key,
    required this.isDarkMode,
    required this.onThemeChanged,
  });

  @override
  State<LibraryScreen> createState() =>
      _LibraryScreenState();
}

class _LibraryScreenState
    extends State<LibraryScreen> {
  final List<MangaItem> library = [];

  final TextEditingController searchController =
      TextEditingController();

  bool loading = true;
  String? errorMessage;
  String searchQuery = '';

  LibrarySection section =
      LibrarySection.library;

  String? selectedSeriesName;

  // false = Vol. 1 -> Vol. 45
  // true  = Vol. 45 -> Vol. 1
  bool volumesDescending = false;

  Box get libraryBox =>
      Hive.box(libraryBoxName);

  @override
  void initState() {
    super.initState();
    loadLibrary();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  List<SeriesGroup> get allSeries {
    final Map<String, List<MangaItem>> grouped =
        {};

    for (final manga in library) {
      final String seriesName =
          normalizedSeriesName(manga.title);

      grouped.putIfAbsent(
        seriesName,
        () => [],
      );

      grouped[seriesName]!.add(manga);
    }

    final groups = grouped.entries
        .map(
          (entry) => SeriesGroup(
            name: entry.key,
            volumes: entry.value
              ..sort(
                (a, b) =>
                    volumeNumber(a.title)
                        .compareTo(
                  volumeNumber(b.title),
                ),
              ),
          ),
        )
        .toList();

    groups.sort(
      (a, b) => a.name
          .toLowerCase()
          .compareTo(
            b.name.toLowerCase(),
          ),
    );

    return groups;
  }

  List<SeriesGroup> get visibleSeries {
    var groups = allSeries;

    if (section == LibrarySection.reading) {
      groups = groups
          .where(
            (group) => group.hasProgress,
          )
          .toList();
    }

    final query =
        searchQuery.trim().toLowerCase();

    if (query.isNotEmpty) {
      groups = groups.where(
        (group) {
          final haystack = [
            group.name,
            group.author,
            ...group.volumes.map(
              (volume) => volume.title,
            ),
          ].join(' ').toLowerCase();

          return haystack.contains(query);
        },
      ).toList();
    }

    return groups;
  }

  SeriesGroup? get selectedSeries {
    if (selectedSeriesName == null) {
      return null;
    }

    for (final group in allSeries) {
      if (group.name == selectedSeriesName) {
        return group;
      }
    }

    return null;
  }

  void loadLibrary() {
    try {
      final List<MangaItem> loaded = [];

      for (final dynamic value
          in libraryBox.values) {
        if (value is Map) {
          final MangaItem manga =
              MangaItem.fromMap(value);

          if (manga.pages.isNotEmpty) {
            loaded.add(manga);
          }
        }
      }

      setState(() {
        library
          ..clear()
          ..addAll(loaded);

        loading = false;

        final groups = allSeries;

        if (groups.isNotEmpty &&
            selectedSeriesName == null) {
          selectedSeriesName =
              groups.first.name;
        }
      });
    } catch (error) {
      setState(() {
        loading = false;
        errorMessage =
            'Erro ao carregar biblioteca: $error';
      });
    }
  }

  Future<void> saveManga(
    MangaItem manga,
  ) async {
    await libraryBox.put(
      manga.id,
      manga.toMap(),
    );
  }

  void updateProgress(
    MangaItem manga,
    int pageIndex,
  ) {
    if (pageIndex < 0 ||
        pageIndex >= manga.pages.length) {
      return;
    }

    if (manga.lastPage == pageIndex) {
      return;
    }

    manga.lastPage = pageIndex;

    saveManga(manga);

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> importManga() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });

    try {
      final FilePickerResult? result =
          await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'cbz',
          'zip',
          'epub',
        ],
        withData: true,
        allowMultiple: true,
      );

      if (result == null) {
        setState(() {
          loading = false;
        });

        return;
      }

      final List<MangaItem>
          importedMangas = [];

      int fileCounter = 0;

      for (final file in result.files) {
        fileCounter++;

        if (file.bytes == null) {
          continue;
        }

        final String extension =
            file.extension
                    ?.toLowerCase() ??
                '';

        final Archive archive =
            ZipDecoder().decodeBytes(
          file.bytes!,
        );

        late MangaItem manga;

        if (extension == 'epub') {
          final EpubData epub =
              parseEpub(
            archive,
            titleFromFileName(
              file.name,
            ),
          );

          manga = MangaItem(
            id:
                '${DateTime.now().microsecondsSinceEpoch}-$fileCounter-${file.name}',
            title: epub.title,
            fileName: file.name,
            author: epub.author,
            format: 'EPUB',
            coverBytes: epub.cover,
            pages: epub.pages,
          );
        } else {
          final List<MangaPage>
              extractedPages = [];

          for (final ArchiveFile archiveFile
              in archive) {
            if (!archiveFile.isFile) {
              continue;
            }

            if (!isImageFile(
              archiveFile.name,
            )) {
              continue;
            }

            final Uint8List imageBytes =
                archiveFileBytes(
              archiveFile,
            );

            if (imageBytes.isEmpty) {
              continue;
            }

            extractedPages.add(
              MangaPage(
                name: archiveFile.name,
                bytes: imageBytes,
              ),
            );
          }

          extractedPages.sort(
            (a, b) =>
                naturalCompareStatic(
              a.name.toLowerCase(),
              b.name.toLowerCase(),
            ),
          );

          if (extractedPages.isEmpty) {
            continue;
          }

          manga = MangaItem(
            id:
                '${DateTime.now().microsecondsSinceEpoch}-$fileCounter-${file.name}',
            title: titleFromFileName(
              file.name,
            ),
            fileName: file.name,
            format: extension == 'cbz'
                ? 'CBZ'
                : 'ZIP',
            coverBytes:
                extractedPages.first.bytes,
            pages: extractedPages,
          );
        }

        await saveManga(manga);

        importedMangas.add(manga);
      }

      if (importedMangas.isEmpty) {
        throw Exception(
          'Nenhum mangá válido foi encontrado.',
        );
      }

      setState(() {
        library.addAll(
          importedMangas,
        );

        loading = false;

        final String firstSeries =
            normalizedSeriesName(
          importedMangas.first.title,
        );

        selectedSeriesName =
            firstSeries;
      });
    } catch (error) {
      setState(() {
        loading = false;
        errorMessage =
            error.toString();
      });
    }
  }

  String titleFromFileName(
    String fileName,
  ) {
    String title = fileName;

    title = title.replaceAll(
      RegExp(
        r'\.(cbz|zip|epub)$',
        caseSensitive: false,
      ),
      '',
    );

    title =
        title.replaceAll('_', ' ');

    title =
        title.replaceAll('-', ' ');

    title = title.replaceAll(
      RegExp(r'\s+'),
      ' ',
    );

    return title.trim();
  }

  Future<void> openVolume(
    MangaItem manga,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            MangaDetailsScreen(
          manga: manga,
          onProgressChanged: (
            int pageIndex,
          ) {
            updateProgress(
              manga,
              pageIndex,
            );
          },
        ),
      ),
    );

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> continueSeries(
    SeriesGroup series,
  ) async {
    final MangaItem? volume =
        series.currentVolume;

    if (volume == null) {
      return;
    }

    await openVolume(volume);
  }

  Future<void> removeManga(
    MangaItem manga,
  ) async {
    await libraryBox.delete(
      manga.id,
    );

    setState(() {
      library.removeWhere(
        (item) =>
            item.id == manga.id,
      );

      if (selectedSeriesName != null &&
          !allSeries.any(
            (group) =>
                group.name ==
                selectedSeriesName,
          )) {
        selectedSeriesName =
            allSeries.isEmpty
                ? null
                : allSeries.first.name;
      }
    });
  }

  Future<void> removeSeries(
    SeriesGroup series,
  ) async {
    for (final volume
        in series.volumes) {
      await libraryBox.delete(
        volume.id,
      );
    }

    setState(() {
      final ids = series.volumes
          .map((volume) => volume.id)
          .toSet();

      library.removeWhere(
        (volume) =>
            ids.contains(volume.id),
      );

      selectedSeriesName =
          allSeries.isEmpty
              ? null
              : allSeries.first.name;
    });
  }

  Future<void> clearLibrary() async {
    await libraryBox.clear();

    setState(() {
      library.clear();
      selectedSeriesName = null;
    });
  }

  void showDeleteVolumeDialog(
    MangaItem manga,
  ) {
    showDialog(
      context: context,
      builder: (
        BuildContext dialogContext,
      ) {
        return AlertDialog(
          title:
              const Text('Remover volume?'),
          content: Text(
            'Deseja remover "${manga.title}" da biblioteca?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                );
              },
              child:
                  const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(
                  dialogContext,
                );

                await removeManga(
                  manga,
                );
              },
              child:
                  const Text('Remover'),
            ),
          ],
        );
      },
    );
  }

  void showDeleteSeriesDialog(
    SeriesGroup series,
  ) {
    showDialog(
      context: context,
      builder: (
        BuildContext dialogContext,
      ) {
        return AlertDialog(
          title:
              const Text('Remover série?'),
          content: Text(
            'Isso removerá os ${series.volumes.length} volumes de "${series.name}" da biblioteca.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                );
              },
              child:
                  const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(
                  dialogContext,
                );

                await removeSeries(
                  series,
                );
              },
              child:
                  const Text('Remover'),
            ),
          ],
        );
      },
    );
  }

  void showClearLibraryDialog() {
    showDialog(
      context: context,
      builder: (
        BuildContext dialogContext,
      ) {
        return AlertDialog(
          title:
              const Text('Limpar biblioteca?'),
          content: const Text(
            'Todos os mangás importados e o progresso local serão removidos.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                );
              },
              child:
                  const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(
                  dialogContext,
                );

                await clearLibrary();
              },
              child:
                  const Text('Limpar'),
            ),
          ],
        );
      },
    );
  }

  void selectSection(
    LibrarySection newSection,
  ) {
    setState(() {
      section = newSection;

      final groups = visibleSeries;

      if (groups.isEmpty) {
        selectedSeriesName = null;
      } else if (!groups.any(
        (group) =>
            group.name ==
            selectedSeriesName,
      )) {
        selectedSeriesName =
            groups.first.name;
      }
    });
  }

  void selectSeries(
    SeriesGroup series,
  ) {
    setState(() {
      selectedSeriesName =
          series.name;
    });
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor:
          Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: loading
            ? const Center(
                child:
                    CircularProgressIndicator(),
              )
            : errorMessage != null &&
                    library.isEmpty
                ? _buildError()
                : LayoutBuilder(
                    builder: (
                      context,
                      constraints,
                    ) {
                      final bool wide =
                          constraints.maxWidth >=
                              1050;

                      if (!wide) {
                        return _buildMobile();
                      }

                      return _buildDesktop();
                    },
                  ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding:
            const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 72,
            ),
            const SizedBox(
              height: 18,
            ),
            const Text(
              'Erro no MangaShelf',
              style: TextStyle(
                fontSize: 24,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            const SizedBox(
              height: 10,
            ),
            Text(
              errorMessage ?? '',
              textAlign:
                  TextAlign.center,
            ),
            const SizedBox(
              height: 24,
            ),
            FilledButton.icon(
              onPressed: importManga,
              icon: const Icon(
                Icons.refresh,
              ),
              label: const Text(
                'Tentar novamente',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktop() {
    final SeriesGroup? selected =
        selectedSeries;

    return Column(
      children: [
        _TopBar(
          searchController:
              searchController,
          searchQuery:
              searchQuery,
          onSearchChanged: (
            value,
          ) {
            setState(() {
              searchQuery = value;

              final groups =
                  visibleSeries;

              if (groups.isNotEmpty &&
                  !groups.any(
                    (group) =>
                        group.name ==
                        selectedSeriesName,
                  )) {
                selectedSeriesName =
                    groups.first.name;
              }
            });
          },
          onImport: importManga,
          onMore:
              showClearLibraryDialog,
        ),
        Expanded(
          child: Row(
            children: [
              _SideRail(
                selected:
                    section,
                onSelected:
                    selectSection,
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color:
                    Theme.of(context).dividerColor,
              ),
              Expanded(
                flex: 9,
                child: section ==
                        LibrarySection
                            .settings
                    ? _buildSettings()
                    : _buildSeriesList(
                        desktop: true,
                      ),
              ),
              if (section !=
                      LibrarySection
                          .settings &&
                  selected != null) ...[
                const VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color:
                      Color(0xFF1E202B),
                ),
                Expanded(
                  flex: 11,
                  child:
                      _SeriesDetailPane(
                    series:
                        selected,
                    volumesDescending:
                        volumesDescending,
                    onToggleVolumeOrder:
                        () {
                      setState(() {
                        volumesDescending =
                            !volumesDescending;
                      });
                    },
                    onOpenVolume:
                        openVolume,
                    onContinue:
                        () =>
                            continueSeries(
                      selected,
                    ),
                    onDeleteVolume:
                        showDeleteVolumeDialog,
                    onDeleteSeries:
                        () =>
                            showDeleteSeriesDialog(
                      selected,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobile() {
    if (section ==
        LibrarySection.settings) {
      return Column(
        children: [
          _TopBar(
            searchController:
                searchController,
            searchQuery:
                searchQuery,
            onSearchChanged: (
              value,
            ) {
              setState(() {
                searchQuery =
                    value;
              });
            },
            onImport:
                importManga,
            onMore:
                showClearLibraryDialog,
            compact: true,
          ),
          Expanded(
            child:
                _buildSettings(),
          ),
        ],
      );
    }

    return Column(
      children: [
        _TopBar(
          searchController:
              searchController,
          searchQuery:
              searchQuery,
          onSearchChanged: (
            value,
          ) {
            setState(() {
              searchQuery = value;
            });
          },
          onImport:
              importManga,
          onMore:
              showClearLibraryDialog,
          compact: true,
        ),
        Padding(
          padding:
              const EdgeInsets.fromLTRB(
            12,
            8,
            12,
            4,
          ),
          child: SegmentedButton<
              LibrarySection>(
            segments: const [
              ButtonSegment(
                value:
                    LibrarySection
                        .library,
                label:
                    Text('Biblioteca'),
                icon:
                    Icon(Icons.book),
              ),
              ButtonSegment(
                value:
                    LibrarySection
                        .reading,
                label:
                    Text('Em leitura'),
                icon: Icon(
                  Icons
                      .auto_stories_outlined,
                ),
              ),
            ],
            selected: {
              section ==
                      LibrarySection
                          .settings
                  ? LibrarySection
                      .library
                  : section,
            },
            onSelectionChanged:
                (values) {
              selectSection(
                values.first,
              );
            },
          ),
        ),
        Expanded(
          child:
              _buildSeriesList(
            desktop: false,
          ),
        ),
      ],
    );
  }

  Widget _buildSeriesList({
    required bool desktop,
  }) {
    final groups = visibleSeries;

    if (library.isEmpty) {
      return _EmptyLibrary(
        onImport: importManga,
      );
    }

    if (groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.search_off,
              size: 64,
              color: Colors.white38,
            ),
            const SizedBox(
              height: 16,
            ),
            Text(
              section ==
                      LibrarySection
                          .reading
                  ? 'Nenhuma série em leitura'
                  : 'Nenhum resultado encontrado',
              style:
                  const TextStyle(
                fontSize: 20,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final int columns;

        if (desktop) {
          columns =
              constraints.maxWidth >
                      820
                  ? 3
                  : 2;
        } else if (constraints
                .maxWidth >
            700) {
          columns = 3;
        } else if (constraints
                .maxWidth >
            430) {
          columns = 2;
        } else {
          columns = 1;
        }

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding:
                  const EdgeInsets.fromLTRB(
                24,
                24,
                24,
                12,
              ),
              sliver:
                  SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          Text(
                            section ==
                                    LibrarySection
                                        .reading
                                ? 'Em leitura'
                                : 'Biblioteca',
                            style:
                                const TextStyle(
                              fontSize:
                                  26,
                              fontWeight:
                                  FontWeight
                                      .bold,
                            ),
                          ),
                          const SizedBox(
                            height: 3,
                          ),
                          Text(
                            '${groups.length} ${groups.length == 1 ? 'obra' : 'obras'}',
                            style:
                                const TextStyle(
                              color:
                                  Colors.white54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding:
                  const EdgeInsets.fromLTRB(
                20,
                6,
                20,
                28,
              ),
              sliver:
                  SliverGrid.builder(
                gridDelegate:
                    SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount:
                      columns,
                  mainAxisSpacing:
                      16,
                  crossAxisSpacing:
                      16,
                  childAspectRatio:
                      desktop
                          ? 0.72
                          : columns == 1
                              ? 1.5
                              : 0.72,
                ),
                itemCount:
                    groups.length,
                itemBuilder: (
                  context,
                  index,
                ) {
                  final series =
                      groups[index];

                  return _SeriesLibraryCard(
                    series:
                        series,
                    selected: desktop &&
                        selectedSeriesName ==
                            series.name,
                    horizontal:
                        !desktop &&
                            columns == 1,
                    onTap: () async {
                      if (desktop) {
                        selectSeries(
                          series,
                        );
                        return;
                      }

                      await Navigator.of(
                        context,
                      ).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              SeriesMobileScreen(
                            series:
                                series,
                            onOpenVolume:
                                openVolume,
                            onContinue:
                                () =>
                                    continueSeries(
                              series,
                            ),
                            onDeleteVolume:
                                showDeleteVolumeDialog,
                          ),
                        ),
                      );

                      if (mounted) {
                        setState(
                          () {},
                        );
                      }
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSettings() {
    return ListView(
      padding:
          const EdgeInsets.all(28),
      children: [
        const Text(
          'Configurações',
          style: TextStyle(
            fontSize: 28,
            fontWeight:
                FontWeight.bold,
          ),
        ),
        const SizedBox(
          height: 8,
        ),
        const Text(
          'Preferências locais do MangaShelf.',
          style: TextStyle(
            color: Colors.white54,
          ),
        ),
        const SizedBox(
          height: 28,
        ),
        Card(
          child: ListTile(
            leading: const Icon(
              Icons.dark_mode_outlined,
            ),
            title: const Text(
              'Tema escuro',
            ),
            subtitle: Text(
              widget.isDarkMode
                  ? 'Tema escuro ativado.'
                  : 'Tema claro ativado.',
            ),
            trailing: Switch(
              value: widget.isDarkMode,
              onChanged: widget.onThemeChanged,
            ),
          ),
        ),
        const SizedBox(
          height: 12,
        ),
        Card(
          child: ListTile(
            leading: const Icon(
              Icons.delete_sweep_outlined,
            ),
            title: const Text(
              'Limpar biblioteca',
            ),
            subtitle: const Text(
              'Remove todos os volumes e progresso salvos localmente.',
            ),
            onTap:
                showClearLibraryDialog,
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  final TextEditingController
      searchController;
  final String searchQuery;
  final ValueChanged<String>
      onSearchChanged;
  final VoidCallback onImport;
  final VoidCallback onMore;
  final bool compact;

  const _TopBar({
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onImport,
    required this.onMore,
    this.compact = false,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      height: 68,
      decoration:
          BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context)
                .dividerColor,
          ),
        ),
      ),
      padding:
          const EdgeInsets.symmetric(
        horizontal: 16,
      ),
      child: Row(
        children: [
          const Text(
            'MangaShelf',
            style: TextStyle(
              fontSize: 22,
              fontWeight:
                  FontWeight.w800,
            ),
          ),
          SizedBox(
            width:
                compact ? 14 : 34,
          ),
          Expanded(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(
                maxWidth: 430,
              ),
              child: TextField(
                controller:
                    searchController,
                onChanged:
                    onSearchChanged,
                decoration:
                    InputDecoration(
                  hintText:
                      'Pesquisar na biblioteca...',
                  prefixIcon:
                      const Icon(
                    Icons.search,
                  ),
                  suffixIcon:
                      searchQuery.isEmpty
                          ? null
                          : IconButton(
                              tooltip:
                                  'Limpar',
                              onPressed:
                                  () {
                                searchController
                                    .clear();
                                onSearchChanged(
                                  '',
                                );
                              },
                              icon:
                                  const Icon(
                                Icons.close,
                              ),
                            ),
                  filled: true,
                  fillColor:
                      Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                  border:
                      OutlineInputBorder(
                    borderRadius:
                        BorderRadius
                            .circular(
                      10,
                    ),
                    borderSide:
                        BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(
                    vertical: 13,
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed:
                onImport,
            icon: const Icon(
              Icons.add,
            ),
            label: Text(
              compact
                  ? 'Importar'
                  : 'Importar',
            ),
          ),
          const SizedBox(
            width: 6,
          ),
          IconButton(
            tooltip:
                'Mais opções',
            onPressed:
                onMore,
            icon: const Icon(
              Icons.more_vert,
            ),
          ),
        ],
      ),
    );
  }
}

class _SideRail extends StatelessWidget {
  final LibrarySection selected;
  final ValueChanged<LibrarySection>
      onSelected;

  const _SideRail({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return SizedBox(
      width: 150,
      child: Padding(
        padding:
            const EdgeInsets.fromLTRB(
          10,
          18,
          10,
          18,
        ),
        child: Column(
          children: [
            _RailButton(
              icon:
                  Icons.book_rounded,
              label:
                  'Biblioteca',
              selected: selected ==
                  LibrarySection
                      .library,
              onTap: () =>
                  onSelected(
                LibrarySection
                    .library,
              ),
            ),
            const SizedBox(
              height: 8,
            ),
            _RailButton(
              icon: Icons
                  .auto_stories_outlined,
              label:
                  'Em leitura',
              selected: selected ==
                  LibrarySection
                      .reading,
              onTap: () =>
                  onSelected(
                LibrarySection
                    .reading,
              ),
            ),
            const SizedBox(
              height: 8,
            ),
            _RailButton(
              icon:
                  Icons.settings_outlined,
              label:
                  'Configurações',
              selected: selected ==
                  LibrarySection
                      .settings,
              onTap: () =>
                  onSelected(
                LibrarySection
                    .settings,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailButton
    extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RailButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Material(
      color: selected
          ? Theme.of(context)
              .colorScheme
              .secondaryContainer
          : Colors.transparent,
      borderRadius:
          BorderRadius.circular(
        10,
      ),
      child: InkWell(
        borderRadius:
            BorderRadius.circular(
          10,
        ),
        onTap: onTap,
        child: Container(
          height: 62,
          padding:
              const EdgeInsets.symmetric(
            horizontal: 14,
          ),
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(
              10,
            ),
            border: selected
                ? Border(
                    left:
                        BorderSide(
                      color: Theme.of(context)
                          .colorScheme
                          .primary,
                      width: 3,
                    ),
                  )
                : null,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected
                    ? Theme.of(context)
                        .colorScheme
                        .primary
                    : Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
              ),
              const SizedBox(
                width: 12,
              ),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? Theme.of(context)
                            .colorScheme
                            .primary
                        : Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                    fontWeight: selected
                        ? FontWeight
                            .bold
                        : FontWeight
                            .normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeriesLibraryCard
    extends StatelessWidget {
  final SeriesGroup series;
  final bool selected;
  final bool horizontal;
  final VoidCallback onTap;

  const _SeriesLibraryCard({
    required this.series,
    required this.selected,
    required this.horizontal,
    required this.onTap,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final content = horizontal
        ? Row(
            children: [
              AspectRatio(
                aspectRatio: 0.68,
                child:
                    seriesCoverImage(
                  series,
                ),
              ),
              Expanded(
                child: _SeriesCardText(
                  series:
                      series,
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment:
                CrossAxisAlignment
                    .stretch,
            children: [
              Expanded(
                child: Stack(
                  fit:
                      StackFit.expand,
                  children: [
                    seriesCoverImage(
                      series,
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child:
                          _CountBadge(
                        count:
                            series.volumes.length,
                      ),
                    ),
                  ],
                ),
              ),
              _SeriesCardText(
                series:
                    series,
              ),
            ],
          );

    return Material(
      color:
          Theme.of(context).colorScheme.surface,
      borderRadius:
          BorderRadius.circular(
        10,
      ),
      clipBehavior:
          Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child:
            AnimatedContainer(
          duration:
              const Duration(
            milliseconds: 160,
          ),
          decoration:
              BoxDecoration(
            borderRadius:
                BorderRadius.circular(
              10,
            ),
            border: Border.all(
              color: selected
                  ? Theme.of(context)
                      .colorScheme
                      .primary
                  : Theme.of(context)
                      .dividerColor,
              width:
                  selected ? 2 : 1,
            ),
          ),
          child: content,
        ),
      ),
    );
  }
}

class _SeriesCardText
    extends StatelessWidget {
  final SeriesGroup series;

  const _SeriesCardText({
    required this.series,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Padding(
      padding:
          const EdgeInsets.all(
        12,
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Text(
            series.name,
            maxLines: 1,
            overflow:
                TextOverflow.ellipsis,
            style:
                const TextStyle(
              fontSize: 17,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          if (series.author
              .isNotEmpty) ...[
            const SizedBox(
              height: 4,
            ),
            Text(
              series.author,
              maxLines: 1,
              overflow:
                  TextOverflow.ellipsis,
              style:
                  const TextStyle(
                color:
                    Color(0xFFA577DF),
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(
            height: 10,
          ),
          Text(
            '${series.volumes.length} ${series.volumes.length == 1 ? 'volume' : 'volumes'}',
            style:
                TextStyle(
              color:
                  Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          if (series.hasProgress) ...[
            const SizedBox(
              height: 8,
            ),
            ClipRRect(
              borderRadius:
                  BorderRadius.circular(
                99,
              ),
              child:
                  LinearProgressIndicator(
                value:
                    series.progress,
                minHeight: 4,
                backgroundColor:
                    Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CountBadge
    extends StatelessWidget {
  final int count;

  const _CountBadge({
    required this.count,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 7,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xD8442A61,
        ),
        borderRadius:
            BorderRadius.circular(
          8,
        ),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style:
                const TextStyle(
              fontWeight:
                  FontWeight.bold,
              fontSize: 14,
            ),
          ),
          Text(
            'Volumes',
            style: TextStyle(
              fontSize: 9,
              color:
                  Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SeriesDetailPane
    extends StatelessWidget {
  final SeriesGroup series;
  final bool volumesDescending;
  final VoidCallback onToggleVolumeOrder;
  final Future<void> Function(MangaItem)
      onOpenVolume;
  final VoidCallback onContinue;
  final ValueChanged<MangaItem>
      onDeleteVolume;
  final VoidCallback onDeleteSeries;

  const _SeriesDetailPane({
    required this.series,
    required this.volumesDescending,
    required this.onToggleVolumeOrder,
    required this.onOpenVolume,
    required this.onContinue,
    required this.onDeleteVolume,
    required this.onDeleteSeries,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final double progress =
        series.progress;

    final List<MangaItem> orderedVolumes =
        [...series.volumes]
          ..sort(
            (a, b) {
              final int aNumber =
                  volumeNumber(a.title);
              final int bNumber =
                  volumeNumber(b.title);

              return volumesDescending
                  ? bNumber.compareTo(aNumber)
                  : aNumber.compareTo(bNumber);
            },
          );

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding:
              const EdgeInsets.fromLTRB(
            28,
            28,
            28,
            18,
          ),
          sliver:
              SliverToBoxAdapter(
            child: Row(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
              children: [
                ClipRRect(
                  borderRadius:
                      BorderRadius.circular(
                    12,
                  ),
                  child: SizedBox(
                    width: 220,
                    height: 320,
                    child:
                        seriesCoverImage(
                      series,
                    ),
                  ),
                ),
                const SizedBox(
                  width: 28,
                ),
                Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.only(
                      top: 8,
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                series.name,
                                style:
                                    const TextStyle(
                                  fontSize:
                                      30,
                                  fontWeight:
                                      FontWeight
                                          .bold,
                                ),
                              ),
                            ),
                            PopupMenuButton<
                                String>(
                              onSelected:
                                  (value) {
                                if (value ==
                                    'delete') {
                                  onDeleteSeries();
                                }
                              },
                              itemBuilder:
                                  (context) =>
                                      const [
                                PopupMenuItem(
                                  value:
                                      'delete',
                                  child:
                                      Text(
                                    'Remover série',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (series.author
                            .isNotEmpty) ...[
                          const SizedBox(
                            height: 4,
                          ),
                          Text(
                            series.author,
                            style:
                                const TextStyle(
                              color: Color(
                                0xFFA577DF,
                              ),
                              fontSize:
                                  16,
                            ),
                          ),
                        ],
                        const SizedBox(
                          height: 22,
                        ),
                        Wrap(
                          spacing: 22,
                          runSpacing: 10,
                          children: [
                            _MetaInfo(
                              icon: Icons
                                  .calendar_view_month_outlined,
                              text:
                                  '${series.volumes.length} volumes',
                            ),
                            _MetaInfo(
                              icon: Icons
                                  .menu_book_outlined,
                              text:
                                  '${formatInteger(series.totalPages)} páginas',
                            ),
                          ],
                        ),
                        const SizedBox(
                          height: 24,
                        ),
                        Text(
                          'Coleção local de ${series.name}. Seus volumes importados ficam organizados aqui para leitura offline.',
                          style:
                              const TextStyle(
                            color:
                                Colors.white70,
                            height: 1.55,
                          ),
                        ),
                        const SizedBox(
                          height: 22,
                        ),
                        FilledButton.icon(
                          onPressed:
                              onContinue,
                          icon: const Icon(
                            Icons
                                .play_arrow_rounded,
                          ),
                          label: Text(
                            series.hasProgress
                                ? 'Continuar leitura'
                                : 'Começar leitura',
                          ),
                        ),
                        const SizedBox(
                          height: 22,
                        ),
                        Container(
                          padding:
                              const EdgeInsets.all(
                            16,
                          ),
                          decoration:
                              BoxDecoration(
                            color:
                                Theme.of(context)
                                    .colorScheme
                                    .surfaceContainer,
                            borderRadius:
                                BorderRadius.circular(
                              10,
                            ),
                            border:
                                Border.all(
                              color:
                                  Theme.of(context)
                                      .dividerColor,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child:
                                        Text(
                                      'Seu progresso na série',
                                      style:
                                          TextStyle(
                                        fontWeight:
                                            FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${(progress * 100).round()}%',
                                    style:
                                        const TextStyle(
                                      fontWeight:
                                          FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(
                                height: 12,
                              ),
                              ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(
                                  99,
                                ),
                                child:
                                    LinearProgressIndicator(
                                  value:
                                      progress,
                                  minHeight:
                                      5,
                                  backgroundColor:
                                      Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                ),
                              ),
                              const SizedBox(
                                height: 10,
                              ),
                              Text(
                                '${series.finishedVolumes} de ${series.volumes.length} volumes concluídos',
                                style:
                                    const TextStyle(
                                  color:
                                      Colors.white60,
                                  fontSize:
                                      12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: Divider(
            height: 1,
            color:
                Color(0xFF242734),
          ),
        ),
        SliverPadding(
          padding:
              const EdgeInsets.fromLTRB(
            28,
            20,
            28,
            12,
          ),
          sliver:
              SliverToBoxAdapter(
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Volumes',
                    style:
                        TextStyle(
                      fontSize: 22,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
                Tooltip(
                  message: volumesDescending
                      ? 'Mudar para ordem crescente'
                      : 'Mudar para ordem decrescente',
                  child: Material(
                    color:
                        Theme.of(context)
                            .colorScheme
                            .surfaceContainer,
                    borderRadius:
                        BorderRadius.circular(
                      8,
                    ),
                    child: InkWell(
                      borderRadius:
                          BorderRadius.circular(
                        8,
                      ),
                      onTap:
                          onToggleVolumeOrder,
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize:
                              MainAxisSize.min,
                          children: [
                            Icon(
                              volumesDescending
                                  ? Icons
                                      .arrow_downward_rounded
                                  : Icons
                                      .arrow_upward_rounded,
                              size: 17,
                            ),
                            const SizedBox(
                              width: 8,
                            ),
                            Text(
                              volumesDescending
                                  ? 'Ordem decrescente'
                                  : 'Ordem crescente',
                              style:
                                  const TextStyle(
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding:
              const EdgeInsets.fromLTRB(
            28,
            0,
            28,
            32,
          ),
          sliver:
              SliverGrid.builder(
            gridDelegate:
                const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent:
                  175,
              childAspectRatio:
                  0.68,
              crossAxisSpacing:
                  12,
              mainAxisSpacing:
                  12,
            ),
            itemCount:
                orderedVolumes.length,
            itemBuilder: (
              context,
              index,
            ) {
              final manga =
                  orderedVolumes[index];

              return _VolumeCard(
                manga: manga,
                onTap: () =>
                    onOpenVolume(
                  manga,
                ),
                onDelete: () =>
                    onDeleteVolume(
                  manga,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MetaInfo
    extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaInfo({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Row(
      mainAxisSize:
          MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 18,
          color:
              Colors.white60,
        ),
        const SizedBox(
          width: 7,
        ),
        Text(
          text,
          style:
              const TextStyle(
            color:
                Colors.white70,
          ),
        ),
      ],
    );
  }
}

class _VolumeCard
    extends StatelessWidget {
  final MangaItem manga;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _VolumeCard({
    required this.manga,
    required this.onTap,
    required this.onDelete,
  });

  String get statusText {
    if (manga.isFinished) {
      return 'Lido';
    }

    if (manga.hasStarted) {
      return 'Lendo';
    }

    return 'Não lido';
  }

  IconData get statusIcon {
    if (manga.isFinished) {
      return Icons
          .check_circle;
    }

    if (manga.hasStarted) {
      return Icons
          .radio_button_checked;
    }

    return Icons
        .radio_button_unchecked;
  }

  Color get statusColor {
    if (manga.isFinished) {
      return const Color(
        0xFF23C978,
      );
    }

    if (manga.hasStarted) {
      return const Color(
        0xFFA36AE7,
      );
    }

    return Colors.white38;
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Material(
      color:
          Theme.of(context).colorScheme.surface,
      borderRadius:
          BorderRadius.circular(
        9,
      ),
      clipBehavior:
          Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onDelete,
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit:
                    StackFit.expand,
                children: [
                  Image.memory(
                    manga.cover,
                    fit:
                        BoxFit.cover,
                    gaplessPlayback:
                        true,
                  ),
                  Positioned(
                    right: 5,
                    top: 5,
                    child:
                        PopupMenuButton<
                            String>(
                      color:
                          const Color(
                        0xFF1A1D27,
                      ),
                      padding:
                          EdgeInsets.zero,
                      onSelected:
                          (value) {
                        if (value ==
                            'delete') {
                          onDelete();
                        }
                      },
                      itemBuilder:
                          (context) =>
                              const [
                        PopupMenuItem(
                          value:
                              'delete',
                          child: Text(
                            'Remover volume',
                          ),
                        ),
                      ],
                      child:
                          const CircleAvatar(
                        radius: 14,
                        backgroundColor:
                            Color(
                          0xAA151822,
                        ),
                        child: Icon(
                          Icons
                              .more_vert,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(
                10,
                9,
                10,
                2,
              ),
              child: Text(
                volumeLabel(
                  manga,
                ),
                maxLines: 1,
                style:
                    const TextStyle(
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(
                10,
                3,
                10,
                10,
              ),
              child: Row(
                children: [
                  Icon(
                    statusIcon,
                    size: 13,
                    color:
                        statusColor,
                  ),
                  const SizedBox(
                    width: 5,
                  ),
                  Expanded(
                    child: Text(
                      statusText,
                      maxLines: 1,
                      overflow:
                          TextOverflow
                              .ellipsis,
                      style:
                          TextStyle(
                        fontSize: 10,
                        color:
                            statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLibrary
    extends StatelessWidget {
  final VoidCallback onImport;

  const _EmptyLibrary({
    required this.onImport,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,
        children: [
          Icon(
            Icons
                .menu_book_rounded,
            size: 84,
            color:
                Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(
            height: 18,
          ),
          const Text(
            'Sua biblioteca está vazia',
            style: TextStyle(
              fontSize: 22,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          const SizedBox(
            height: 8,
          ),
          Text(
            'Importe EPUB, CBZ ou ZIP para começar.',
            style: TextStyle(
              color:
                  Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(
            height: 22,
          ),
          FilledButton.icon(
            onPressed:
                onImport,
            icon: const Icon(
              Icons.add,
            ),
            label: const Text(
              'Importar mangá',
            ),
          ),
        ],
      ),
    );
  }
}

class SeriesMobileScreen
    extends StatefulWidget {
  final SeriesGroup series;
  final Future<void> Function(MangaItem)
      onOpenVolume;
  final VoidCallback onContinue;
  final ValueChanged<MangaItem>
      onDeleteVolume;

  const SeriesMobileScreen({
    super.key,
    required this.series,
    required this.onOpenVolume,
    required this.onContinue,
    required this.onDeleteVolume,
  });

  @override
  State<SeriesMobileScreen>
      createState() =>
          _SeriesMobileScreenState();
}

class _SeriesMobileScreenState
    extends State<SeriesMobileScreen> {
  @override
  Widget build(
    BuildContext context,
  ) {
    final series =
        widget.series;

    return Scaffold(
      backgroundColor:
          Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor:
            Theme.of(context).colorScheme.surface,
        title: Text(
          series.name,
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding:
                const EdgeInsets.all(
              18,
            ),
            sliver:
                SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Center(
                    child:
                        ClipRRect(
                      borderRadius:
                          BorderRadius.circular(
                        12,
                      ),
                      child: SizedBox(
                        width: 230,
                        height: 335,
                        child:
                            seriesCoverImage(
                          series,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(
                    height: 20,
                  ),
                  Text(
                    series.name,
                    style:
                        const TextStyle(
                      fontSize: 28,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  if (series.author
                      .isNotEmpty) ...[
                    const SizedBox(
                      height: 4,
                    ),
                    Text(
                      series.author,
                      style:
                          const TextStyle(
                        color:
                            Color(
                          0xFFA577DF,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(
                    height: 12,
                  ),
                  Text(
                    '${series.volumes.length} volumes • ${formatInteger(series.totalPages)} páginas',
                    style:
                        const TextStyle(
                      color:
                          Colors.white70,
                    ),
                  ),
                  const SizedBox(
                    height: 18,
                  ),
                  SizedBox(
                    width:
                        double.infinity,
                    child:
                        FilledButton.icon(
                      onPressed:
                          widget.onContinue,
                      icon:
                          const Icon(
                        Icons
                            .play_arrow_rounded,
                      ),
                      label: Text(
                        series.hasProgress
                            ? 'Continuar leitura'
                            : 'Começar leitura',
                      ),
                    ),
                  ),
                  const SizedBox(
                    height: 24,
                  ),
                  const Text(
                    'Volumes',
                    style:
                        TextStyle(
                      fontSize: 22,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding:
                const EdgeInsets.fromLTRB(
              16,
              0,
              16,
              28,
            ),
            sliver:
                SliverGrid.builder(
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio:
                    0.64,
                crossAxisSpacing:
                    12,
                mainAxisSpacing:
                    12,
              ),
              itemCount:
                  series.volumes.length,
              itemBuilder: (
                context,
                index,
              ) {
                final manga =
                    series.volumes[
                        index];

                return _VolumeCard(
                  manga: manga,
                  onTap: () async {
                    await widget
                        .onOpenVolume(
                      manga,
                    );

                    if (mounted) {
                      setState(
                        () {},
                      );
                    }
                  },
                  onDelete: () =>
                      widget
                          .onDeleteVolume(
                    manga,
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

class MangaDetailsScreen
    extends StatefulWidget {
  final MangaItem manga;

  final ValueChanged<int>
      onProgressChanged;

  const MangaDetailsScreen({
    super.key,
    required this.manga,
    required this.onProgressChanged,
  });

  @override
  State<MangaDetailsScreen>
      createState() =>
          _MangaDetailsScreenState();
}

class _MangaDetailsScreenState
    extends State<MangaDetailsScreen> {
  Future<void> openReader() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ReaderScreen(
          title:
              widget.manga.title,
          seriesTitle:
              normalizedSeriesName(
            widget.manga.title,
          ),
          pages:
              widget.manga.pages,
          initialPage:
              widget.manga.hasStarted
                  ? widget.manga
                      .lastPage
                  : 0,
          onProgressChanged: (
            int pageIndex,
          ) {
            widget
                .onProgressChanged(
              pageIndex,
            );

            setState(() {});
          },
        ),
      ),
    );

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final MangaItem manga =
        widget.manga;

    String statusText;

    if (!manga.hasStarted) {
      statusText =
          '${manga.pages.length} páginas';
    } else if (manga.isFinished) {
      statusText =
          'Leitura concluída';
    } else {
      statusText =
          'Página ${manga.lastPage + 1} de ${manga.pages.length}';
    }

    return Scaffold(
      backgroundColor:
          Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor:
            Theme.of(context).colorScheme.surface,
        title:
            Text(manga.title),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.all(
            30,
          ),
          child: Column(
            children: [
              ClipRRect(
                borderRadius:
                    BorderRadius.circular(
                  14,
                ),
                child: Image.memory(
                  manga.cover,
                  width: 220,
                  height: 320,
                  fit: BoxFit.cover,
                  gaplessPlayback:
                      true,
                ),
              ),
              const SizedBox(
                height: 24,
              ),
              Text(
                manga.title,
                textAlign:
                    TextAlign.center,
                style:
                    const TextStyle(
                  fontSize: 26,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              if (manga.author
                  .isNotEmpty) ...[
                const SizedBox(
                  height: 8,
                ),
                Text(
                  manga.author,
                  style:
                      const TextStyle(
                    color:
                        Color(
                      0xFFA577DF,
                    ),
                  ),
                ),
              ],
              const SizedBox(
                height: 8,
              ),
              Text(
                '${manga.format} • $statusText',
              ),
              if (manga.hasStarted) ...[
                const SizedBox(
                  height: 12,
                ),
                SizedBox(
                  width: 220,
                  child:
                      LinearProgressIndicator(
                    value:
                        manga.progress,
                    minHeight: 6,
                  ),
                ),
              ],
              const SizedBox(
                height: 26,
              ),
              FilledButton.icon(
                onPressed:
                    openReader,
                icon: const Icon(
                  Icons
                      .menu_book_rounded,
                ),
                label: Text(
                  manga.hasStarted
                      ? 'Continuar leitura'
                      : 'Ler mangá',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReaderScreen
    extends StatefulWidget {
  final String title;
  final String seriesTitle;
  final List<MangaPage> pages;
  final int initialPage;

  final ValueChanged<int>
      onProgressChanged;

  const ReaderScreen({
    super.key,
    required this.title,
    required this.seriesTitle,
    required this.pages,
    required this.initialPage,
    required this.onProgressChanged,
  });

  @override
  State<ReaderScreen>
      createState() =>
          _ReaderScreenState();
}

class _ReaderScreenState
    extends State<ReaderScreen> {
  static const double
      desktopReaderWidth = 820;

  final ItemScrollController
      itemScrollController =
      ItemScrollController();

  final ItemPositionsListener
      itemPositionsListener =
      ItemPositionsListener.create();

  final TransformationController
      transformationController =
      TransformationController();

  bool showInterface = true;
  bool isZoomed = false;

  int currentPage = 0;

  Timer? saveTimer;

  double get currentZoom =>
      transformationController
          .value
          .getMaxScaleOnAxis();

  @override
  void initState() {
    super.initState();

    currentPage =
        widget.initialPage.clamp(
      0,
      widget.pages.length - 1,
    );

    itemPositionsListener
        .itemPositions
        .addListener(
      handleVisiblePages,
    );

    transformationController
        .addListener(
      handleZoomChanged,
    );

    WidgetsBinding.instance
        .addPostFrameCallback(
      (_) {
        if (itemScrollController
            .isAttached) {
          itemScrollController.jumpTo(
            index:
                currentPage,
          );
        }
      },
    );
  }

  void handleZoomChanged() {
    final bool zoomed =
        currentZoom > 1.01;

    if (zoomed != isZoomed &&
        mounted) {
      setState(() {
        isZoomed = zoomed;
      });
    }
  }

  void handleVisiblePages() {
    final positions =
        itemPositionsListener
            .itemPositions
            .value;

    if (positions.isEmpty) {
      return;
    }

    final visible = positions
        .where(
          (position) =>
              position.itemTrailingEdge >
                  0 &&
              position.itemLeadingEdge <
                  1,
        )
        .toList();

    if (visible.isEmpty) {
      return;
    }

    visible.sort(
      (a, b) {
        final double centerA =
            ((a.itemLeadingEdge +
                        a.itemTrailingEdge) /
                    2 -
                0.5)
                .abs();

        final double centerB =
            ((b.itemLeadingEdge +
                        b.itemTrailingEdge) /
                    2 -
                0.5)
                .abs();

        return centerA.compareTo(
          centerB,
        );
      },
    );

    final int newPage =
        visible.first.index;

    if (newPage ==
        currentPage) {
      return;
    }

    setState(() {
      currentPage = newPage;
    });

    saveTimer?.cancel();

    saveTimer = Timer(
      const Duration(
        milliseconds: 180,
      ),
      () {
        widget.onProgressChanged(
          currentPage,
        );
      },
    );
  }

  void toggleInterface() {
    if (isZoomed) {
      return;
    }

    setState(() {
      showInterface =
          !showInterface;
    });
  }

  void toggleDoubleTapZoom() {
    if (isZoomed) {
      transformationController
              .value =
          Matrix4.identity();

      return;
    }

    transformationController
            .value =
        Matrix4.identity()
          ..scaleByDouble(
            2.0,
            2.0,
            2.0,
            1.0,
          );
  }

  void resetZoom() {
    transformationController.value =
        Matrix4.identity();
  }

  @override
  void dispose() {
    saveTimer?.cancel();

    widget.onProgressChanged(
      currentPage,
    );

    itemPositionsListener
        .itemPositions
        .removeListener(
      handleVisiblePages,
    );

    transformationController
        .removeListener(
      handleZoomChanged,
    );

    transformationController.dispose();

    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final double screenWidth =
        MediaQuery.sizeOf(
      context,
    ).width;

    final bool desktop =
        screenWidth >= 800;

    final double readerWidth =
        desktop
            ? desktopReaderWidth
            : screenWidth;

    return Scaffold(
      backgroundColor:
          const Color(
        0xFF05060B,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (
                context,
                constraints,
              ) {
                return GestureDetector(
                  behavior:
                      HitTestBehavior.translucent,
                  onTap:
                      toggleInterface,
                  onDoubleTap:
                      toggleDoubleTapZoom,
                  child: InteractiveViewer(
                    transformationController:
                        transformationController,

                    // No desktop o mouse wheel fica 100% dedicado
                    // ao scroll vertical. O zoom é feito pelo
                    // double click.
                    //
                    // No celular/tablet continuamos permitindo
                    // pinch-to-zoom com dois dedos.
                    scaleEnabled: !desktop,

                    panEnabled:
                        isZoomed,

                    minScale: 1,
                    maxScale: 4,

                    alignment:
                        Alignment.topCenter,

                    boundaryMargin:
                        const EdgeInsets.all(
                      220,
                    ),

                    clipBehavior:
                        Clip.hardEdge,

                    child: SizedBox(
                      width:
                          constraints.maxWidth,
                      height:
                          constraints.maxHeight,
                      child:
                          ScrollablePositionedList
                              .builder(
                        itemCount:
                            widget.pages.length,
                        itemScrollController:
                            itemScrollController,
                        itemPositionsListener:
                            itemPositionsListener,
                        padding:
                            EdgeInsets.zero,
                        physics: isZoomed
                            ? const NeverScrollableScrollPhysics()
                            : const ClampingScrollPhysics(),
                        itemBuilder: (
                          context,
                          index,
                        ) {
                          final MangaPage page =
                              widget.pages[index];

                          return SizedBox(
                            width:
                                constraints.maxWidth,
                            child: Align(
                              alignment:
                                  Alignment.topCenter,
                              child: SizedBox(
                                width:
                                    readerWidth,
                                child:
                                    Image.memory(
                                  page.bytes,
                                  width:
                                      readerWidth,
                                  fit:
                                      BoxFit.fitWidth,
                                  gaplessPlayback:
                                      true,
                                  filterQuality:
                                      FilterQuality.medium,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          AnimatedPositioned(
            duration:
                const Duration(
              milliseconds: 170,
            ),
            top: showInterface
                ? 0
                : -74,
            left: 0,
            right: 0,
            height: 66,
            child: Container(
              color:
                  const Color(
                0xF5080910,
              ),
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    IconButton(
                      tooltip:
                          'Voltar',
                      onPressed: () =>
                          Navigator.of(
                        context,
                      ).pop(),
                      icon: const Icon(
                        Icons
                            .arrow_back,
                      ),
                    ),
                    const SizedBox(
                      width: 4,
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment:
                            MainAxisAlignment
                                .center,
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          Text(
                            widget.seriesTitle,
                            style:
                                const TextStyle(
                              color:
                                  Colors.white54,
                              fontSize: 10,
                            ),
                          ),
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow:
                                TextOverflow
                                    .ellipsis,
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding:
                          const EdgeInsets.only(
                        right: 6,
                      ),
                      child: Text(
                        '${currentPage + 1}/${widget.pages.length}',
                        style:
                            const TextStyle(
                          color:
                              Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip:
                          'Resetar zoom',
                      onPressed:
                          resetZoom,
                      icon: const Icon(
                        Icons
                            .fit_screen,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
