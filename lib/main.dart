import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:window_manager/window_manager.dart';

import 'platform_file_loader.dart';

const String libraryBoxName = 'mangashelf_library';
const String metadataBoxName = 'mangashelf_metadata';
const MethodChannel androidFileChannel =
    MethodChannel('mangashelf/file_open');

String progressKey(String mangaId) =>
    '__progress__$mangaId';

String metadataKey(String mangaId) =>
    '__meta__$mangaId';

const String androidLastOpenedPathKey =
    '__android_last_opened_path';

// Pasta padrão para capas personalizadas no Windows.
// Exemplos:
// D:\IMAGENS\Capas de manga\One Piece capa.webp
// D:\IMAGENS\Capas de manga\Blue Lock capa.jpg
//
// Se nenhuma capa externa existir, o MangaShelf usa
// automaticamente a capa interna do mangá.
const String windowsSeriesCoverFolder =
    r'D:\IMAGENS\Capas de manga';

final Map<String, Future<Uint8List?>>
    _customSeriesCoverCache = {};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb &&
      defaultTargetPlatform == TargetPlatform.windows) {
    await windowManager.ensureInitialized();
  }

  // Mostra a interface imediatamente. O armazenamento é aberto
  // depois do primeiro frame para não segurar a splash nativa.
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
  final String seriesOverride;
  final Uint8List coverBytes;
  final List<MangaPage> pages;
  final int storedPageCount;

  int lastPage;

  MangaItem({
    required this.id,
    required this.title,
    required this.fileName,
    required this.pages,
    this.author = '',
    this.format = 'CBZ',
    this.seriesOverride = '',
    Uint8List? coverBytes,
    int? pageCount,
    this.lastPage = -1,
  })  : storedPageCount = pageCount ?? pages.length,
        coverBytes = coverBytes ?? Uint8List(0);

  int get pageCount =>
      pages.isNotEmpty ? pages.length : storedPageCount;

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
      pageCount > 0 && lastPage >= pageCount - 1;

  double get progress {
    if (!hasStarted || pageCount <= 0) {
      return 0;
    }

    return (lastPage + 1) / pageCount;
  }

  MangaItem toMetadataOnly() {
    return MangaItem(
      id: id,
      title: title,
      fileName: fileName,
      author: author,
      format: format,
      seriesOverride: seriesOverride,
      coverBytes: coverBytes,
      pages: const <MangaPage>[],
      pageCount: pageCount,
      lastPage: lastPage,
    );
  }

  Map<String, dynamic> toMetadataMap() {
    return {
      'id': id,
      'title': title,
      'fileName': fileName,
      'author': author,
      'format': format,
      'seriesOverride': seriesOverride,
      'coverBytes': coverBytes,
      'lastPage': lastPage,
      'pageCount': pageCount,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'fileName': fileName,
      'author': author,
      'format': format,
      'seriesOverride': seriesOverride,
      'coverBytes': coverBytes,
      'lastPage': lastPage,
      'pageCount': pageCount,
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

    final int pageCount =
        map['pageCount'] is num
            ? (map['pageCount'] as num).toInt()
            : pages.length;

    int lastPage = -1;

    final dynamic rawLastPage = map['lastPage'];

    if (rawLastPage is int) {
      lastPage = rawLastPage;
    } else if (rawLastPage is num) {
      lastPage = rawLastPage.toInt();
    }

    if (pageCount > 0 && lastPage >= pageCount) {
      lastPage = pageCount - 1;
    }

    return MangaItem(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Mangá',
      fileName: map['fileName']?.toString() ?? '',
      author: map['author']?.toString() ?? '',
      format: map['format']?.toString() ?? 'CBZ',
      seriesOverride:
          map['seriesOverride']?.toString() ?? '',
      coverBytes: bytesFromDynamic(map['coverBytes']),
      pages: pages,
      pageCount: pageCount,
      lastPage: lastPage,
    );
  }

  factory MangaItem.fromMetadataMap(
    Map<dynamic, dynamic> map,
  ) {
    final int pageCount =
        map['pageCount'] is num
            ? (map['pageCount'] as num).toInt()
            : map['pages'] is List
                ? (map['pages'] as List).length
                : 0;

    int lastPage = -1;

    final dynamic rawLastPage = map['lastPage'];

    if (rawLastPage is int) {
      lastPage = rawLastPage;
    } else if (rawLastPage is num) {
      lastPage = rawLastPage.toInt();
    }

    if (pageCount > 0 && lastPage >= pageCount) {
      lastPage = pageCount - 1;
    }

    return MangaItem(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Mangá',
      fileName: map['fileName']?.toString() ?? '',
      author: map['author']?.toString() ?? '',
      format: map['format']?.toString() ?? 'CBZ',
      seriesOverride:
          map['seriesOverride']?.toString() ?? '',
      coverBytes: bytesFromDynamic(map['coverBytes']),
      pages: const <MangaPage>[],
      pageCount: pageCount,
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

String titleFromFileName(String fileName) {
  String title = fileName;

  title = title.replaceAll(
    RegExp(
      r'\.(cbz|zip|epub)$',
      caseSensitive: false,
    ),
    '',
  );

  title = title.replaceAll('_', ' ');
  title = title.replaceAll('-', ' ');

  title = title.replaceAll(
    RegExp(r'\s+'),
    ' ',
  );

  return title.trim();
}

class MangaParseRequest {
  final String fileName;
  final Uint8List bytes;
  final int fileCounter;

  const MangaParseRequest({
    required this.fileName,
    required this.bytes,
    required this.fileCounter,
  });
}

// Função top-level (obrigatório para o compute()) que descompacta o
// CBZ/ZIP/EPUB e monta as páginas. Isso roda numa isolate separada,
// então a descompactação de arquivos grandes não trava a UI —
// especialmente importante em Android mais fraco, onde fazer isso
// na thread principal travava a tela durante a importação.
MangaItem? parseMangaFromBytes(MangaParseRequest request) {
  final String fileName = request.fileName;
  final Uint8List bytes = request.bytes;
  final int fileCounter = request.fileCounter;

  final String extension =
      fileName.contains('.')
          ? fileName.split('.').last.toLowerCase()
          : '';

  if (!['epub', 'cbz', 'zip'].contains(extension)) {
    return null;
  }

  final Archive archive = ZipDecoder().decodeBytes(bytes);

  if (extension == 'epub') {
    final EpubData epub = parseEpub(
      archive,
      titleFromFileName(fileName),
    );

    return MangaItem(
      id:
          '${DateTime.now().microsecondsSinceEpoch}-$fileCounter-$fileName',
      title: epub.title,
      fileName: fileName,
      author: epub.author,
      format: 'EPUB',
      coverBytes: epub.cover,
      pages: epub.pages,
    );
  }

  final List<MangaPage> extractedPages = [];

  for (final ArchiveFile archiveFile in archive) {
    if (!archiveFile.isFile || !isImageFile(archiveFile.name)) {
      continue;
    }

    final Uint8List imageBytes = archiveFileBytes(archiveFile);

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
    (a, b) => naturalCompareStatic(
      a.name.toLowerCase(),
      b.name.toLowerCase(),
    ),
  );

  if (extractedPages.isEmpty) {
    return null;
  }

  return MangaItem(
    id:
        '${DateTime.now().microsecondsSinceEpoch}-$fileCounter-$fileName',
    title: titleFromFileName(fileName),
    fileName: fileName,
    format: extension == 'cbz' ? 'CBZ' : 'ZIP',
    coverBytes: extractedPages.first.bytes,
    pages: extractedPages,
  );
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
  return normalizedSeriesName(title);
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

  bool get isChapterSeries =>
      volumes.any(
        (item) => chapterNumber(item.title) > 0,
      );

  String get itemSingular =>
      isChapterSeries ? 'capítulo' : 'volume';

  String get itemPlural =>
      isChapterSeries ? 'capítulos' : 'volumes';

  String get itemHeading =>
      isChapterSeries ? 'Capítulos' : 'Volumes';

  String get badgeLabel =>
      isChapterSeries ? 'Caps.' : 'Volumes';

  String get itemCountLabel =>
      '${volumes.length} '
      '${volumes.length == 1 ? itemSingular : itemPlural}';

  String get totalPagesLabel =>
      '${formatInteger(totalPages)} páginas';

  String get completedLabel =>
      '$finishedVolumes de ${volumes.length} '
      '${volumes.length == 1 ? itemSingular : itemPlural} concluídos';

  int get totalPages =>
      volumes.fold(
        0,
        (sum, volume) =>
            sum + volume.pageCount,
      );

  int get startedVolumes =>
      volumes.where(
        (volume) => volume.hasStarted,
      ).length;

  int get finishedVolumes =>
      volumes.where(
        (volume) => volume.isFinished,
      ).length;

  bool get hasProgress =>
      startedVolumes > 0;

  double get progress {
    if (volumes.isEmpty) {
      return 0;
    }

    double sum = 0;

    for (final volume in volumes) {
      sum += volume.progress;
    }

    return (sum / volumes.length)
        .clamp(0.0, 1.0);
  }

  MangaItem get fallbackCoverVolume {
    final sorted = [...volumes]
      ..sort(
        (a, b) =>
            readingItemNumber(b)
                .compareTo(
              readingItemNumber(a),
            ),
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
        (a, b) =>
            readingItemNumber(a)
                .compareTo(
              readingItemNumber(b),
            ),
      );

    if (started.isNotEmpty) {
      return started.first;
    }

    final unread = volumes
        .where(
          (volume) =>
              !volume.hasStarted,
        )
        .toList()
      ..sort(
        (a, b) =>
            readingItemNumber(a)
                .compareTo(
              readingItemNumber(b),
            ),
      );

    if (unread.isNotEmpty) {
      return unread.first;
    }

    final sorted = [...volumes]
      ..sort(
        (a, b) =>
            readingItemNumber(b)
                .compareTo(
              readingItemNumber(a),
            ),
      );

    return sorted.isEmpty
        ? null
        : sorted.first;
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

  return int.tryParse(
        match.group(1) ?? '',
      ) ??
      0;
}

double chapterNumber(String title) {
  final List<RegExp> patterns = [
    RegExp(
      r'(?:cap(?:[íi]tulo)?|chapter|ch)\.?\s*#?\s*(\d+(?:[.,]\d+)?)',
      caseSensitive: false,
    ),
    RegExp(
      r'#\s*(\d+(?:[.,]\d+)?)',
      caseSensitive: false,
    ),
    // Ex.: "Blue Lock - 413"
    RegExp(
      r'[-–—]\s*(\d+(?:[.,]\d+)?)\s*$',
      caseSensitive: false,
    ),
  ];

  for (final pattern in patterns) {
    final Match? match =
        pattern.firstMatch(title);

    if (match == null) {
      continue;
    }

    final String raw =
        (match.group(1) ?? '')
            .replaceAll(',', '.');

    final double? value =
        double.tryParse(raw);

    if (value != null) {
      return value;
    }
  }

  return 0;
}

bool isChapterTitle(String title) =>
    chapterNumber(title) > 0 &&
    volumeNumber(title) == 0;

double readingItemNumber(
  MangaItem manga,
) {
  final int volume =
      volumeNumber(manga.title);

  if (volume > 0) {
    return volume.toDouble();
  }

  final double chapter =
      chapterNumber(manga.title);

  if (chapter > 0) {
    return chapter;
  }

  return 0;
}

String _stripSeriesItemSuffix(
  String value,
) {
  String name = value.trim();

  // Remove extensão quando o fallback veio do nome do arquivo.
  name = name.replaceFirst(
    RegExp(
      r'\.(cbz|zip|epub)$',
      caseSensitive: false,
    ),
    '',
  );

  // Volumes.
  name = name.replaceFirst(
    RegExp(
      r'\s*[-–—:]?\s*vol(?:ume)?\.?\s*\d+(?:[.,]\d+)?(?:\s.*)?$',
      caseSensitive: false,
    ),
    '',
  );

  // Capítulo / Cap / Chapter / Ch.
  name = name.replaceFirst(
    RegExp(
      r'\s*[-–—:]?\s*(?:cap(?:[íi]tulo)?|chapter|ch)\.?\s*#?\s*\d+(?:[.,]\d+)?(?:\s.*)?$',
      caseSensitive: false,
    ),
    '',
  );

  // "#413" no fim.
  name = name.replaceFirst(
    RegExp(
      r'\s*[-–—:]?\s*#\s*\d+(?:[.,]\d+)?(?:\s.*)?$',
      caseSensitive: false,
    ),
    '',
  );

  // Downloads que chegam como "Blue Lock - 413".
  name = name.replaceFirst(
    RegExp(
      r'\s*[-–—]\s*\d+(?:[.,]\d+)?\s*$',
      caseSensitive: false,
    ),
    '',
  );

  name = name
      .replaceAll('_', ' ')
      .replaceAll(
        RegExp(r'\s+'),
        ' ',
      )
      .trim();

  return name;
}

bool _looksLikeOnlyChapterTitle(
  String value,
) {
  return RegExp(
    r'^\s*(?:cap(?:[íi]tulo)?|chapter|ch)\.?\s*#?\s*\d+(?:[.,]\d+)?\s*$',
    caseSensitive: false,
  ).hasMatch(value);
}

String normalizedSeriesName(
  String title, {
  String? fileName,
}) {
  String name =
      _stripSeriesItemSuffix(title);

  // Alguns EPUBs usam apenas "Capítulo 413" no metadata.
  // Nesse caso recuperamos o nome da obra pelo arquivo importado.
  if ((name.isEmpty ||
          _looksLikeOnlyChapterTitle(
            title,
          ) ||
          name == title.trim()) &&
      fileName != null &&
      fileName.trim().isNotEmpty) {
    final String fileBased =
        _stripSeriesItemSuffix(
      fileName,
    );

    if (fileBased.isNotEmpty &&
        !_looksLikeOnlyChapterTitle(
          fileBased,
        )) {
      name = fileBased;
    }
  }

  return name.trim().isEmpty
      ? title.trim()
      : name.trim();
}

String volumeLabel(MangaItem manga) {
  final int volume =
      volumeNumber(manga.title);

  if (volume > 0) {
    return 'Vol. $volume';
  }

  final double chapter =
      chapterNumber(manga.title);

  if (chapter > 0) {
    final String number =
        chapter == chapter.roundToDouble()
            ? chapter.toInt().toString()
            : chapter
                .toString()
                .replaceAll('.', ',');

    return 'Cap. $number';
  }

  return manga.title;
}

String _seriesKey(String value) {
  return value
      .toLowerCase()
      .replaceAll(
        RegExp(r'[^a-z0-9]+'),
        '',
      );
}

Future<Uint8List?> _readCustomSeriesCover(
  String seriesName,
) {
  final String cacheKey =
      _seriesKey(seriesName);

  return _customSeriesCoverCache.putIfAbsent(
    cacheKey,
    () => readSeriesCoverBytes(
      windowsSeriesCoverFolder,
      seriesName,
    ),
  );
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

Widget seriesCoverImage(
  SeriesGroup series, {
  BoxFit fit = BoxFit.cover,
}) {
  Widget fallback() {
    return Image.memory(
      series.fallbackCoverVolume.cover,
      fit: fit,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
      cacheWidth: 900,
    );
  }

  if (kIsWeb ||
      defaultTargetPlatform !=
          TargetPlatform.windows) {
    return fallback();
  }

  return FutureBuilder<Uint8List?>(
    future:
        _readCustomSeriesCover(
      series.name,
    ),
    builder: (
      context,
      snapshot,
    ) {
      final Uint8List? bytes =
          snapshot.data;

      if (bytes == null ||
          bytes.isEmpty) {
        return fallback();
      }

      return Image.memory(
        bytes,
        fit: fit,
        gaplessPlayback: true,
        filterQuality:
            FilterQuality.medium,
        cacheWidth: 900,
        errorBuilder: (
          context,
          error,
          stackTrace,
        ) {
          return fallback();
        },
      );
    },
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
  bool mobileSearchOpen = false;

  LibrarySection section =
      LibrarySection.library;

  String? selectedSeriesName;

  // false = Vol. 1 -> Vol. 45
  // true  = Vol. 45 -> Vol. 1
  bool volumesDescending = false;

  LazyBox? _libraryBox;
  Box? _metadataBox;
  Future<LazyBox>? _contentBoxFuture;
  bool _storageInitializationStarted = false;
  bool _contentWarmUpScheduled = false;

  String? _cachedVolumeId;
  MangaItem? _cachedVolume;

  Box get metadataBox {
    final Box? box = _metadataBox;

    if (box == null) {
      throw StateError(
        'O armazenamento ainda não foi inicializado.',
      );
    }

    return box;
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback(
      (_) {
        _initializeStorage();
      },
    );
  }

  Future<void> _initializeStorage() async {
    if (_storageInitializationStarted) {
      return;
    }

    _storageInitializationStarted = true;

    try {
      await Hive.initFlutter();

      // Esta box guarda somente dados leves da biblioteca.
      // Ela abre muito mais rápido do que a box com todas as páginas.
      _metadataBox =
          await Hive.openBox(metadataBoxName);

      if (metadataBox.isEmpty) {
        await _migrateLegacyMetadata();
      }

      _loadLibraryFromMetadata();

      // Só configura a integração Android depois que a biblioteca
      // já está pronta para uso.
      unawaited(
        _configureAndroidFileOpen(),
      );

      // Mantém o startup rápido, mas prepara a box pesada logo
      // depois. Assim as funções não ficam esperando a primeira
      // abertura do armazenamento ao serem tocadas.
      _scheduleContentWarmUp();
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        loading = false;
        errorMessage =
            'Erro ao inicializar biblioteca: $error';
      });
    }
  }

  void _scheduleContentWarmUp() {
    if (_contentWarmUpScheduled) {
      return;
    }

    _contentWarmUpScheduled = true;

    // A box pesada é preparada imediatamente em segundo plano,
    // sem atrasar a primeira pintura da biblioteca. Isso elimina
    // a espera artificial de 500 ms que podia fazer o primeiro
    // capítulo parecer lento ao ser aberto logo após o startup.
    unawaited(
      _ensureContentBox().then<void>(
        (_) {},
        onError: (_) {},
      ),
    );
  }

  Future<LazyBox> _ensureContentBox() {
    final LazyBox? existing = _libraryBox;

    if (existing != null && existing.isOpen) {
      return Future<LazyBox>.value(existing);
    }

    final Future<LazyBox>? pending =
        _contentBoxFuture;

    if (pending != null) {
      return pending;
    }

    final Future<LazyBox> future =
        Hive.openLazyBox(libraryBoxName)
            .then(
      (LazyBox box) {
        _libraryBox = box;
        _contentBoxFuture = null;
        return box;
      },
    );

    _contentBoxFuture = future;
    return future;
  }

  Future<void> _migrateLegacyMetadata() async {
    final LazyBox contentBox =
        await _ensureContentBox();

    final List<dynamic> keys =
        contentBox.keys.toList();

    // A versão anterior já gravava __meta__ na box grande.
    // Copiamos essas entradas pequenas para a nova box rápida.
    final List<dynamic> metadataKeys =
        keys.where(
      (dynamic key) =>
          key is String &&
          key.startsWith('__meta__'),
    ).toList();

    if (metadataKeys.isNotEmpty) {
      for (final dynamic key in metadataKeys) {
        final dynamic value =
            await contentBox.get(key);

        if (value is! Map) {
          continue;
        }

        final MangaItem manga =
            MangaItem.fromMetadataMap(value);

        final dynamic progress =
            await contentBox.get(
          progressKey(manga.id),
        );

        if (progress is num) {
          manga.lastPage = progress
              .toInt()
              .clamp(
                -1,
                manga.pageCount <= 0
                    ? -1
                    : manga.pageCount - 1,
              )
              .toInt();
        }

        if (manga.id.isNotEmpty &&
            manga.pageCount > 0) {
          await metadataBox.put(
            manga.id,
            manga.toMetadataMap(),
          );
        }

        await Future<void>.delayed(
          Duration.zero,
        );
      }

      return;
    }

    // Compatibilidade com bibliotecas da v1 original.
    // É uma migração única; as próximas aberturas usam só metadataBox.
    for (final dynamic key in keys) {
      if (key is String &&
          key.startsWith('__')) {
        continue;
      }

      final dynamic value =
          await contentBox.get(key);

      if (value is! Map) {
        continue;
      }

      final MangaItem manga =
          MangaItem.fromMetadataMap(value);

      if (manga.id.isEmpty ||
          manga.pageCount <= 0) {
        continue;
      }

      final dynamic progress =
          await contentBox.get(
        progressKey(manga.id),
      );

      if (progress is num) {
        manga.lastPage = progress
            .toInt()
            .clamp(
              -1,
              manga.pageCount - 1,
            )
            .toInt();
      }

      await metadataBox.put(
        manga.id,
        manga.toMetadataMap(),
      );

      await Future<void>.delayed(
        Duration.zero,
      );
    }
  }

  void _loadLibraryFromMetadata() {
    final List<MangaItem> loaded = [];

    for (final dynamic value
        in metadataBox.values) {
      if (value is! Map) {
        continue;
      }

      final MangaItem manga =
          MangaItem.fromMetadataMap(value);

      if (manga.id.isNotEmpty &&
          manga.pageCount > 0) {
        loaded.add(manga);
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      library
        ..clear()
        ..addAll(loaded);

      loading = false;
      errorMessage = null;

      final List<SeriesGroup> groups =
          allSeries;

      if (groups.isNotEmpty &&
          selectedSeriesName == null) {
        selectedSeriesName =
            groups.first.name;
      }
    });
  }

  @override
  void dispose() {
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      androidFileChannel.setMethodCallHandler(null);
    }

    searchController.dispose();
    super.dispose();
  }

  Future<void> _configureAndroidFileOpen() async {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    androidFileChannel.setMethodCallHandler(
      (MethodCall call) async {
        if (call.method != 'openFile') {
          return;
        }

        final dynamic arguments = call.arguments;

        if (arguments is Map) {
          await _importAndroidOpenedFile(
            Map<dynamic, dynamic>.from(arguments),
          );
        }
      },
    );

    WidgetsBinding.instance.addPostFrameCallback(
      (_) async {
        try {
          final Map<dynamic, dynamic>? initial =
              await androidFileChannel.invokeMapMethod<
                  dynamic, dynamic>('getInitialFile');

          if (initial != null && mounted) {
            await _importAndroidOpenedFile(initial);
          }
        } catch (_) {
          // O canal existe apenas no Android. Falhas aqui não
          // devem impedir a biblioteca de abrir normalmente.
        }
      },
    );
  }

  List<SeriesGroup> get allSeries {
    final Map<String, List<MangaItem>> grouped =
        {};

    for (final manga in library) {
      final String seriesName =
          manga.seriesOverride.trim().isNotEmpty
              ? manga.seriesOverride.trim()
              : normalizedSeriesName(
                  manga.title,
                  fileName: manga.fileName,
                );

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
                    readingItemNumber(a)
                        .compareTo(
                  readingItemNumber(b),
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

  Future<void> loadLibrary() async {
    if (_metadataBox == null) {
      await _initializeStorage();
      return;
    }

    _loadLibraryFromMetadata();
  }

  Future<void> saveManga(
    MangaItem manga,
  ) async {
    final LazyBox contentBox =
        await _ensureContentBox();

    // Só grava o conteúdo pesado (páginas) na box grande.
    // Metadados (título, capa, progresso) já vivem só na
    // metadataBox — gravá-los de novo aqui duplicava a escrita
    // dos bytes da capa em disco a cada importação, à toa.
    await contentBox.put(
      manga.id,
      manga.toMap(),
    );

    await metadataBox.put(
      manga.id,
      manga.toMetadataMap(),
    );
  }

  void updateProgress(
    MangaItem manga,
    int pageIndex,
  ) {
    if (pageIndex < 0 ||
        pageIndex >= manga.pageCount) {
      return;
    }

    if (manga.lastPage == pageIndex) {
      return;
    }

    manga.lastPage = pageIndex;

    MangaItem metadataManga = manga;

    for (final MangaItem item in library) {
      if (item.id == manga.id) {
        item.lastPage = pageIndex;
        metadataManga = item;
        break;
      }
    }

    // Atualiza somente o registro leve. Não toca nas páginas
    // durante a rolagem.
    unawaited(
      metadataBox.put(
        metadataManga.id,
        metadataManga.toMetadataMap(),
      ),
    );
  }

  Future<MangaItem?> _buildMangaFromBytes(
    String fileName,
    Uint8List bytes,
    int fileCounter,
  ) {
    // compute() roda o parsing/descompactação numa isolate separada,
    // então a UI continua fluida (60fps) enquanto um CBZ/ZIP grande
    // é processado — antes isso rodava direto na thread principal
    // e travava a tela em aparelhos mais fracos durante a importação.
    return compute(
      parseMangaFromBytes,
      MangaParseRequest(
        fileName: fileName,
        bytes: bytes,
        fileCounter: fileCounter,
      ),
    );
  }

  Future<MangaItem> _storeImportedManga(
    MangaItem manga,
  ) async {
    await saveManga(manga);

    // Guarda o volume recém-importado (já com as páginas em memória)
    // no cache de leitura. Sem isso, ao tocar para ler logo após
    // importar, o app reabria o Hive e descomprimia todas as
    // páginas de novo — um trabalho redundante que fazia o
    // primeiro capítulo demorar muito mais do que deveria.
    _cachedVolumeId = manga.id;
    _cachedVolume = manga;

    return manga.toMetadataOnly();
  }

  Future<void> _importAndroidOpenedFile(
    Map<dynamic, dynamic> data,
  ) async {
    final String path =
        data['path']?.toString() ?? '';
    final String name =
        data['name']?.toString() ?? '';

    if (path.isEmpty || name.isEmpty) {
      return;
    }

    final dynamic lastHandledPath =
        metadataBox.get(
      androidLastOpenedPathKey,
    );

    // Evita reler automaticamente um Intent antigo quando
    // o Android/Flutter reinicia a Activity.
    if (lastHandledPath?.toString() == path) {
      return;
    }

    // Marca ANTES da leitura. Se um arquivo inválido ou enorme
    // derrubar a importação, a próxima abertura normal do app
    // não ficará presa tentando o mesmo arquivo novamente.
    await metadataBox.put(
      androidLastOpenedPathKey,
      path,
    );

    if (mounted) {
      setState(() {
        loading = true;
        errorMessage = null;
      });
    }

    try {
      final Uint8List? bytes =
          await readLocalFileBytes(path);

      if (bytes == null) {
        throw Exception(
          'Não foi possível ler o arquivo selecionado.',
        );
      }

      final MangaItem? manga =
          await _buildMangaFromBytes(
        name,
        bytes,
        1,
      );

      if (manga == null) {
        throw Exception(
          'O arquivo selecionado não é um EPUB, CBZ ou ZIP válido.',
        );
      }

      MangaItem finalManga = manga;

      if (_isAmbiguousChapterManga(
        manga,
      )) {
        if (mounted) {
          setState(() {
            loading = false;
          });
        }

        final String? seriesName =
            await _askSeriesNameForChapters(
          <MangaItem>[manga],
        );

        if (seriesName == null ||
            seriesName.trim().isEmpty) {
          return;
        }

        finalManga =
            _withSeriesOverride(
          manga,
          seriesName,
        );

        if (mounted) {
          setState(() {
            loading = true;
          });
        }
      }

      final MangaItem lightweight =
          await _storeImportedManga(
        finalManga,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        library.add(lightweight);
        loading = false;
        errorMessage = null;
        selectedSeriesName =
            lightweight.seriesOverride
                    .trim()
                    .isNotEmpty
                ? lightweight
                    .seriesOverride
                    .trim()
                : normalizedSeriesName(
                    lightweight.title,
                    fileName:
                        lightweight.fileName,
                  );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        loading = false;
        errorMessage =
            'Não foi possível abrir o arquivo: $error';
      });
    }
  }

  bool _isAmbiguousChapterManga(
    MangaItem manga,
  ) {
    if (!isChapterTitle(manga.title)) {
      return false;
    }

    final String derived =
        normalizedSeriesName(
      manga.title,
      fileName: manga.fileName,
    ).trim();

    return derived.isEmpty ||
        _looksLikeOnlyChapterTitle(
          derived,
        ) ||
        _looksLikeOnlyChapterTitle(
          manga.title,
        );
  }

  Future<String?> _askSeriesNameForChapters(
    List<MangaItem> ambiguous,
  ) async {
    if (!mounted ||
        ambiguous.isEmpty) {
      return null;
    }

    final TextEditingController
        controller =
        TextEditingController();

    String? result;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (
        BuildContext dialogContext,
      ) {
        return AlertDialog(
          title: const Text(
            'Organizar capítulos',
          ),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  ambiguous.length == 1
                      ? 'Este EPUB contém um capítulo sem o nome da obra.'
                      : 'Os ${ambiguous.length} EPUBs selecionados contêm capítulos sem o nome da obra.',
                ),
                const SizedBox(
                  height: 8,
                ),
                const Text(
                  'Digite o nome da obra uma única vez. Todos esses capítulos serão agrupados nela.',
                  style: TextStyle(
                    color:
                        Colors.white70,
                  ),
                ),
                const SizedBox(
                  height: 16,
                ),
                TextField(
                  controller:
                      controller,
                  autofocus: true,
                  textInputAction:
                      TextInputAction.done,
                  decoration:
                      const InputDecoration(
                    labelText:
                        'Nome da obra',
                    hintText:
                        'Ex.: Blue Lock',
                    border:
                        OutlineInputBorder(),
                  ),
                  onSubmitted: (
                    value,
                  ) {
                    final String name =
                        value.trim();

                    if (name.isEmpty) {
                      return;
                    }

                    result = name;
                    Navigator.of(
                      dialogContext,
                    ).pop();
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                result = null;
                Navigator.of(
                  dialogContext,
                ).pop();
              },
              child: const Text(
                'Cancelar',
              ),
            ),
            FilledButton(
              onPressed: () {
                final String name =
                    controller.text.trim();

                if (name.isEmpty) {
                  return;
                }

                result = name;
                Navigator.of(
                  dialogContext,
                ).pop();
              },
              child: const Text(
                'Agrupar',
              ),
            ),
          ],
        );
      },
    );

    controller.dispose();
    return result;
  }

  MangaItem _withSeriesOverride(
    MangaItem manga,
    String seriesName,
  ) {
    return MangaItem(
      id: manga.id,
      title: manga.title,
      fileName: manga.fileName,
      author: manga.author,
      format: manga.format,
      seriesOverride:
          seriesName.trim(),
      coverBytes:
          manga.coverBytes,
      pages: manga.pages,
      pageCount:
          manga.pageCount,
      lastPage:
          manga.lastPage,
    );
  }

  Future<void> importManga() async {
    if (mounted) {
      setState(() {
        loading = true;
        errorMessage = null;
      });
    }

    try {
      final FilePickerResult? result =
          await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'cbz',
          'zip',
          'epub',
        ],
        withData: kIsWeb,
        allowMultiple: true,
      );

      if (result == null) {
        if (mounted) {
          setState(() {
            loading = false;
          });
        }

        return;
      }

      final List<MangaItem> parsedMangas =
          [];

      int fileCounter = 0;

      for (final file in result.files) {
        fileCounter++;

        Uint8List? bytes =
            file.bytes;

        if (bytes == null &&
            file.path != null &&
            file.path!.isNotEmpty) {
          bytes =
              await readLocalFileBytes(
            file.path!,
          );
        }

        if (bytes == null) {
          continue;
        }

        final MangaItem? manga =
            await _buildMangaFromBytes(
          file.name,
          bytes,
          fileCounter,
        );

        if (manga != null) {
          parsedMangas.add(
            manga,
          );
        }

        bytes = null;

        await Future<void>.delayed(
          Duration.zero,
        );
      }

      if (parsedMangas.isEmpty) {
        throw Exception(
          'Nenhum mangá válido foi encontrado.',
        );
      }

      final List<MangaItem> ambiguous =
          parsedMangas
              .where(
                _isAmbiguousChapterManga,
              )
              .toList();

      String? chapterSeriesName;

      if (ambiguous.isNotEmpty) {
        if (mounted) {
          setState(() {
            loading = false;
          });
        }

        chapterSeriesName =
            await _askSeriesNameForChapters(
          ambiguous,
        );

        if (chapterSeriesName == null ||
            chapterSeriesName.trim().isEmpty) {
          return;
        }

        if (mounted) {
          setState(() {
            loading = true;
          });
        }
      }

      final Set<String> ambiguousIds =
          ambiguous
              .map(
                (item) => item.id,
              )
              .toSet();

      final List<MangaItem>
          lightweightMangas =
          [];

      for (final MangaItem parsed
          in parsedMangas) {
        final MangaItem manga =
            ambiguousIds.contains(
                      parsed.id,
                    ) &&
                    chapterSeriesName !=
                        null
                ? _withSeriesOverride(
                    parsed,
                    chapterSeriesName,
                  )
                : parsed;

        final MangaItem lightweight =
            await _storeImportedManga(
          manga,
        );

        lightweightMangas.add(
          lightweight,
        );

        await Future<void>.delayed(
          Duration.zero,
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        library.addAll(
          lightweightMangas,
        );

        loading = false;
        errorMessage = null;

        final MangaItem first =
            lightweightMangas.first;

        selectedSeriesName =
            first.seriesOverride
                    .trim()
                    .isNotEmpty
                ? first
                    .seriesOverride
                    .trim()
                : normalizedSeriesName(
                    first.title,
                    fileName:
                        first.fileName,
                  );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        loading = false;
        errorMessage =
            error.toString();
      });
    }
  }

  Future<MangaItem> _loadVolumeForReading(
    MangaItem metadataManga,
  ) async {
    final MangaItem? cached =
        _cachedVolume;

    if (_cachedVolumeId ==
            metadataManga.id &&
        cached != null &&
        cached.pages.isNotEmpty) {
      cached.lastPage =
          metadataManga.lastPage;
      return cached;
    }

    final LazyBox contentBox =
        await _ensureContentBox();

    final dynamic raw =
        await contentBox.get(
      metadataManga.id,
    );

    if (raw is! Map) {
      throw Exception(
        'Os dados deste volume não foram encontrados.',
      );
    }

    final MangaItem loadedManga =
        MangaItem.fromMap(raw);

    loadedManga.lastPage =
        metadataManga.lastPage;

    if (loadedManga.pages.isEmpty) {
      throw Exception(
        'Nenhuma página foi encontrada neste volume.',
      );
    }

    _cachedVolumeId =
        metadataManga.id;
    _cachedVolume =
        loadedManga;

    return loadedManga;
  }

  List<MangaItem> _navigationItemsFor(
    MangaItem manga,
  ) {
    for (final SeriesGroup series in allSeries) {
      if (series.volumes.any(
        (item) => item.id == manga.id,
      )) {
        final List<MangaItem> items =
            [...series.volumes];

        items.sort(
          (a, b) => readingItemNumber(a)
              .compareTo(readingItemNumber(b)),
        );

        return items;
      }
    }

    return <MangaItem>[manga];
  }

  Future<void> openAdjacentVolume(
    MangaItem manga,
  ) async {
    if (!mounted) {
      return;
    }

    final List<MangaItem> navigationItems =
        _navigationItemsFor(manga);

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            _VolumeOpeningScreen(
          title: manga.title,
          loadVolume: () =>
              _loadVolumeForReading(
            manga,
          ),
          navigationItems:
              navigationItems,
          onOpenAdjacent:
              openAdjacentVolume,
          openDirectly: true,
          onProgressChanged: (
            MangaItem loadedManga,
            int pageIndex,
          ) {
            updateProgress(
              loadedManga,
              pageIndex,
            );

            manga.lastPage =
                pageIndex;
          },
        ),
      ),
    );
  }

  Future<void> openVolume(
    MangaItem manga,
  ) async {
    if (!mounted) {
      return;
    }

    final List<MangaItem> navigationItems =
        _navigationItemsFor(manga);

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            _VolumeOpeningScreen(
          title: manga.title,
          loadVolume: () =>
              _loadVolumeForReading(
            manga,
          ),
          navigationItems:
              navigationItems,
          onOpenAdjacent:
              openAdjacentVolume,
          onProgressChanged: (
            MangaItem loadedManga,
            int pageIndex,
          ) {
            updateProgress(
              loadedManga,
              pageIndex,
            );

            manga.lastPage =
                pageIndex;
          },
        ),
      ),
    );

    if (!kIsWeb &&
        defaultTargetPlatform ==
            TargetPlatform.android) {
      PaintingBinding.instance.imageCache
          .clearLiveImages();
      PaintingBinding.instance.imageCache
          .clear();
    }

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
    final LazyBox contentBox =
        await _ensureContentBox();

    await contentBox.delete(
      manga.id,
    );
    await contentBox.delete(
      progressKey(manga.id),
    );
    await contentBox.delete(
      metadataKey(manga.id),
    );

    await metadataBox.delete(
      manga.id,
    );

    if (_cachedVolumeId == manga.id) {
      _cachedVolumeId = null;
      _cachedVolume = null;
    }

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
      final LazyBox contentBox =
          await _ensureContentBox();

      await contentBox.delete(
        volume.id,
      );
      await contentBox.delete(
        progressKey(volume.id),
      );
      await contentBox.delete(
        metadataKey(volume.id),
      );

      await metadataBox.delete(
        volume.id,
      );
    }

    setState(() {
      final ids = series.volumes
          .map((volume) => volume.id)
          .toSet();

      if (_cachedVolumeId != null &&
          ids.contains(_cachedVolumeId)) {
        _cachedVolumeId = null;
        _cachedVolume = null;
      }

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
    final LazyBox contentBox =
        await _ensureContentBox();

    await contentBox.clear();
    await metadataBox.clear();

    _cachedVolumeId = null;
    _cachedVolume = null;

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
          title: Text(
            isChapterTitle(manga.title)
                ? 'Remover capítulo?'
                : 'Remover volume?',
          ),
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
            'Isso removerá ${series.itemCountLabel} de "${series.name}" da biblioteca.',
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
                        return Stack(
                          children: [
                            _buildMobile(),
                            if (mobileSearchOpen)
                              _buildMobileSearchOverlay(),
                          ],
                        );
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

  void _openMobileSearch() {
    setState(() {
      mobileSearchOpen = true;
    });
  }

  void _closeMobileSearch() {
    searchController.clear();

    setState(() {
      searchQuery = '';
      mobileSearchOpen = false;
    });
  }

  Widget _buildMobileSearchOverlay() {
    final String query =
        searchQuery.trim().toLowerCase();

    final List<SeriesGroup> results =
        query.isEmpty
            ? <SeriesGroup>[]
            : allSeries.where(
                (series) {
                  final String searchable =
                      [
                    series.name,
                    ...series.volumes.map(
                      (volume) =>
                          '${volume.title} ${volume.author}',
                    ),
                  ].join(' ').toLowerCase();

                  return searchable.contains(query);
                },
              ).toList();

    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(
          alpha: 0.58,
        ),
        child: SafeArea(
          bottom: false,
          child: GestureDetector(
            behavior:
                HitTestBehavior.opaque,
            onTap: _closeMobileSearch,
            child: Align(
              alignment:
                  Alignment.topCenter,
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  margin:
                      const EdgeInsets.fromLTRB(
                    12,
                    8,
                    12,
                    0,
                  ),
                  constraints:
                      const BoxConstraints(
                    maxWidth: 620,
                    maxHeight: 430,
                  ),
                  decoration:
                      BoxDecoration(
                    color:
                        Theme.of(context)
                            .colorScheme
                            .surface,
                    borderRadius:
                        BorderRadius.circular(
                      16,
                    ),
                    border: Border.all(
                      color:
                          Theme.of(context)
                              .dividerColor,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        blurRadius: 24,
                        spreadRadius: 2,
                        color:
                            Color(0x66000000),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: [
                      Padding(
                        padding:
                            const EdgeInsets.all(
                          10,
                        ),
                        child: TextField(
                          controller:
                              searchController,
                          autofocus: true,
                          textInputAction:
                              TextInputAction.search,
                          onChanged: (value) {
                            setState(() {
                              searchQuery =
                                  value;
                            });
                          },
                          decoration:
                              InputDecoration(
                            hintText:
                                'Buscar título ou autor...',
                            prefixIcon:
                                const Icon(
                              Icons.search,
                            ),
                            suffixIcon:
                                IconButton(
                              tooltip: 'Fechar',
                              onPressed:
                                  _closeMobileSearch,
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
                                  BorderRadius.circular(
                                12,
                              ),
                              borderSide:
                                  BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      if (query.isEmpty)
                        const Padding(
                          padding:
                              EdgeInsets.fromLTRB(
                            18,
                            6,
                            18,
                            20,
                          ),
                          child: Align(
                            alignment:
                                Alignment.centerLeft,
                            child: Text(
                              'Digite para pesquisar na sua biblioteca.',
                              style: TextStyle(
                                color:
                                    Colors.white54,
                              ),
                            ),
                          ),
                        )
                      else if (results.isEmpty)
                        const Padding(
                          padding:
                              EdgeInsets.fromLTRB(
                            18,
                            8,
                            18,
                            22,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.search_off,
                                color:
                                    Colors.white54,
                              ),
                              SizedBox(
                                width: 10,
                              ),
                              Text(
                                'Nenhum título encontrado',
                              ),
                            ],
                          ),
                        )
                      else
                        Flexible(
                          child:
                              ListView.separated(
                            padding:
                                const EdgeInsets.fromLTRB(
                              10,
                              2,
                              10,
                              12,
                            ),
                            shrinkWrap: true,
                            itemCount:
                                results.length,
                            separatorBuilder: (_, _) =>
                                    const Divider(
                              height: 1,
                            ),
                            itemBuilder:
                                (context, index) {
                              final SeriesGroup
                                  series =
                                  results[index];

                              return ListTile(
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                leading:
                                    ClipRRect(
                                  borderRadius:
                                      BorderRadius.circular(
                                    6,
                                  ),
                                  child: SizedBox(
                                    width: 44,
                                    height: 58,
                                    child:
                                        seriesCoverImage(
                                      series,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  series.name,
                                  maxLines: 1,
                                  overflow:
                                      TextOverflow.ellipsis,
                                  style:
                                      const TextStyle(
                                    fontWeight:
                                        FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  series.itemCountLabel,
                                ),
                                trailing:
                                    const Icon(
                                  Icons.chevron_right,
                                ),
                                onTap: () {
                                  searchController
                                      .clear();

                                  setState(() {
                                    searchQuery = '';
                                    mobileSearchOpen =
                                        false;
                                    selectedSeriesName =
                                        series.name;
                                    section =
                                        LibrarySection
                                            .library;
                                  });

                                  Navigator.of(
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
                                },
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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
            onSearchTap:
                _openMobileSearch,
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
          onSearchTap:
              _openMobileSearch,
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
  final VoidCallback? onSearchTap;
  final bool compact;

  const _TopBar({
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onImport,
    required this.onMore,
    this.onSearchTap,
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
          if (compact)
            IconButton(
              tooltip:
                  'Pesquisar',
              onPressed:
                  onSearchTap,
              icon: const Icon(
                Icons.search,
              ),
            )
          else
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
          if (compact)
            IconButton.filled(
              tooltip:
                  'Importar',
              onPressed:
                  onImport,
              icon: const Icon(
                Icons.add,
              ),
            )
          else
            FilledButton.icon(
              onPressed:
                  onImport,
              icon: const Icon(
                Icons.add,
              ),
              label: const Text(
                'Importar',
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
                        label:
                            series.badgeLabel,
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
            series.itemCountLabel,
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
  final String label;

  const _CountBadge({
    required this.count,
    required this.label,
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
            label,
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
              final double aNumber =
                  readingItemNumber(a);
              final double bNumber =
                  readingItemNumber(b);

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
                                  series.itemCountLabel,
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
                          'Coleção local de ${series.name}. Seus ${series.itemPlural} importados ficam organizados aqui para leitura offline.',
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
                                series.completedLabel,
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
                Expanded(
                  child: Text(
                    series.itemHeading,
                    style:
                        const TextStyle(
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
                          (context) => [
                        PopupMenuItem(
                          value:
                              'delete',
                          child: Text(
                            isChapterTitle(
                              manga.title,
                            )
                                ? 'Remover capítulo'
                                : 'Remover volume',
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
                    '${series.itemCountLabel} • ${series.totalPagesLabel}',
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
                  Text(
                    series.itemHeading,
                    style:
                        const TextStyle(
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


class _VolumeOpeningScreen
    extends StatefulWidget {
  final String title;
  final Future<MangaItem> Function()
      loadVolume;
  final void Function(
    MangaItem manga,
    int pageIndex,
  ) onProgressChanged;
  final List<MangaItem> navigationItems;
  final Future<void> Function(MangaItem manga)?
      onOpenAdjacent;
  final bool openDirectly;

  const _VolumeOpeningScreen({
    required this.title,
    required this.loadVolume,
    required this.onProgressChanged,
    this.navigationItems = const <MangaItem>[],
    this.onOpenAdjacent,
    this.openDirectly = false,
  });

  @override
  State<_VolumeOpeningScreen>
      createState() =>
          _VolumeOpeningScreenState();
}

class _VolumeOpeningScreenState
    extends State<_VolumeOpeningScreen> {
  MangaItem? manga;
  Object? error;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback(
      (_) async {
        // Dá tempo real para o Android desenhar a tela
        // "Abrindo volume..." antes de iniciar a leitura pesada.
        // Assim o usuário nunca fica preso visualmente na tela anterior.
        // Esse delay só faz sentido no Android; nas outras
        // plataformas ele só atrasava a abertura de todo capítulo
        // sem necessidade.
        if (!kIsWeb &&
            defaultTargetPlatform == TargetPlatform.android) {
          await Future<void>.delayed(
            const Duration(milliseconds: 180),
          );
        }

        if (!mounted) {
          return;
        }

        await _load();
      },
    );
  }

  Future<void> _load() async {
    try {
      final MangaItem loaded =
          await widget.loadVolume();

      if (!mounted) {
        return;
      }

      setState(() {
        manga = loaded;
      });
    } catch (loadError) {
      if (!mounted) {
        return;
      }

      setState(() {
        error = loadError;
      });
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final MangaItem? loaded =
        manga;

    if (loaded != null) {
      // Volume novo: entra direto no leitor.
      // A tela de detalhes/"Continuar leitura" só aparece
      // para volumes que já possuem progresso salvo.
      if (widget.openDirectly || !loaded.hasStarted) {
        return ReaderScreen(
          title: loaded.title,
          seriesTitle:
              normalizedSeriesName(
            loaded.title,
            fileName:
                loaded.fileName,
          ),
          pages: loaded.pages,
          initialPage:
              loaded.hasStarted
                  ? loaded.lastPage
                  : 0,
          previousItem:
              _adjacentItem(
            loaded,
            widget.navigationItems,
            -1,
          ),
          nextItem:
              _adjacentItem(
            loaded,
            widget.navigationItems,
            1,
          ),
          onOpenAdjacent:
              widget.onOpenAdjacent,
          onProgressChanged: (
            int pageIndex,
          ) {
            widget.onProgressChanged(
              loaded,
              pageIndex,
            );
          },
        );
      }

      return MangaDetailsScreen(
        manga: loaded,
        navigationItems:
            widget.navigationItems,
        onOpenAdjacent:
            widget.onOpenAdjacent,
        onProgressChanged: (
          int pageIndex,
        ) {
          widget.onProgressChanged(
            loaded,
            pageIndex,
          );
        },
      );
    }

    return Scaffold(
      backgroundColor:
          const Color(0xFF05060B),
      appBar: AppBar(
        backgroundColor:
            const Color(0xFF090A10),
        title: Text(
          widget.title,
          maxLines: 1,
          overflow:
              TextOverflow.ellipsis,
        ),
      ),
      body: Center(
        child: error != null
            ? Padding(
                padding:
                    const EdgeInsets.all(
                  24,
                ),
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 56,
                    ),
                    const SizedBox(
                      height: 16,
                    ),
                    const Text(
                      'Não foi possível abrir o volume.',
                      textAlign:
                          TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight:
                            FontWeight.w700,
                      ),
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    Text(
                      error.toString(),
                      textAlign:
                          TextAlign.center,
                    ),
                    const SizedBox(
                      height: 18,
                    ),
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          error = null;
                        });
                        _load();
                      },
                      child: const Text(
                        'Tentar novamente',
                      ),
                    ),
                  ],
                ),
              )
            : const Column(
                mainAxisSize:
                    MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 3,
                    ),
                  ),
                  SizedBox(
                    height: 18,
                  ),
                  Text(
                    'Abrindo volume...',
                    style: TextStyle(
                      color:
                          Colors.white70,
                      fontSize: 15,
                      fontWeight:
                          FontWeight.w600,
                    ),
                  ),
                  SizedBox(
                    height: 6,
                  ),
                  Text(
                    'Preparando páginas para leitura',
                    style: TextStyle(
                      color:
                          Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// Esta tela é usada apenas para volumes que já foram iniciados.
// Volumes ainda não lidos entram diretamente no ReaderScreen.
MangaItem? _adjacentItem(
  MangaItem current,
  List<MangaItem> navigationItems,
  int direction,
) {
  if (navigationItems.isEmpty) {
    return null;
  }

  final int index = navigationItems.indexWhere(
    (item) => item.id == current.id,
  );

  if (index < 0) {
    return null;
  }

  final int targetIndex = index + direction;

  if (targetIndex < 0 ||
      targetIndex >= navigationItems.length) {
    return null;
  }

  return navigationItems[targetIndex];
}

class MangaDetailsScreen
    extends StatefulWidget {
  final MangaItem manga;

  final ValueChanged<int>
      onProgressChanged;
  final List<MangaItem> navigationItems;
  final Future<void> Function(MangaItem manga)?
      onOpenAdjacent;

  const MangaDetailsScreen({
    super.key,
    required this.manga,
    required this.onProgressChanged,
    this.navigationItems = const <MangaItem>[],
    this.onOpenAdjacent,
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
            fileName:
                widget.manga.fileName,
          ),
          pages:
              widget.manga.pages,
          initialPage:
              widget.manga.hasStarted
                  ? widget.manga
                      .lastPage
                  : 0,
          previousItem:
              _adjacentItem(
            widget.manga,
            widget.navigationItems,
            -1,
          ),
          nextItem:
              _adjacentItem(
            widget.manga,
            widget.navigationItems,
            1,
          ),
          onOpenAdjacent:
              widget.onOpenAdjacent,
          onProgressChanged: (
            int pageIndex,
          ) {
            widget
                .onProgressChanged(
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

  @override
  Widget build(
    BuildContext context,
  ) {
    final MangaItem manga =
        widget.manga;

    String statusText;

    if (!manga.hasStarted) {
      statusText =
          '${manga.pageCount} páginas';
    } else if (manga.isFinished) {
      statusText =
          'Leitura concluída';
    } else {
      statusText =
          'Página ${manga.lastPage + 1} de ${manga.pageCount}';
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
  final MangaItem? previousItem;
  final MangaItem? nextItem;
  final Future<void> Function(MangaItem manga)?
      onOpenAdjacent;

  final ValueChanged<int>
      onProgressChanged;

  const ReaderScreen({
    super.key,
    required this.title,
    required this.seriesTitle,
    required this.pages,
    required this.initialPage,
    this.previousItem,
    this.nextItem,
    this.onOpenAdjacent,
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
  bool isFullscreen = false;
  bool fullscreenAvailable = false;

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

    fullscreenAvailable =
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.windows;

    if (fullscreenAvailable) {
      _loadFullscreenState();
    }

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

  Future<void> _loadFullscreenState() async {
    try {
      final bool value =
          await windowManager.isFullScreen();

      if (!mounted) {
        return;
      }

      setState(() {
        isFullscreen = value;
      });
    } catch (_) {
      // O botão continua oculto se a API nativa não estiver disponível.
    }
  }

  Future<void> toggleFullscreen() async {
    if (!fullscreenAvailable || isZoomed) {
      return;
    }

    try {
      final bool target = !isFullscreen;
      await windowManager.setFullScreen(target);

      if (!mounted) {
        return;
      }

      setState(() {
        isFullscreen = target;
        showInterface = true;
      });
    } catch (_) {
      // Evita quebrar o leitor caso a janela nativa recuse a operação.
    }
  }

  Future<void> handleEscapeFullscreen() async {
    if (!fullscreenAvailable || !isFullscreen) {
      return;
    }

    await windowManager.setFullScreen(false);

    if (mounted) {
      setState(() {
        isFullscreen = false;
        showInterface = true;
      });
    }
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
        milliseconds: 350,
      ),
      () {
        widget.onProgressChanged(
          currentPage,
        );
      },
    );
  }

  Future<void> openAdjacent(MangaItem? target) async {
    if (target == null ||
        widget.onOpenAdjacent == null ||
        isZoomed) {
      return;
    }

    saveTimer?.cancel();
    widget.onProgressChanged(
      currentPage,
    );

    await widget.onOpenAdjacent!(target);
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

  void handlePointerSignal(PointerSignalEvent event) {
    if (!fullscreenAvailable &&
        !kIsWeb &&
        defaultTargetPlatform != TargetPlatform.windows) {
      return;
    }

    if (event is! PointerScrollEvent) {
      return;
    }

    // No PC, Ctrl + roda do mouse controla o zoom.
    // A roda normal continua dedicada à leitura vertical.
    if (!HardwareKeyboard.instance.isControlPressed) {
      return;
    }

    if (!mounted) {
      return;
    }

    if (event.scrollDelta.dy < 0) {
      final double nextZoom =
          (currentZoom + 0.25).clamp(1.0, 4.0);

      transformationController.value =
          Matrix4.identity()
            ..scaleByDouble(
              nextZoom,
              nextZoom,
              nextZoom,
              1.0,
            );
    } else if (event.scrollDelta.dy > 0) {
      transformationController.value =
          Matrix4.identity();
    }
  }

  @override
  void dispose() {
    saveTimer?.cancel();

    if (fullscreenAvailable && isFullscreen) {
      windowManager.setFullScreen(false);
    }

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

    final double devicePixelRatio =
        MediaQuery.devicePixelRatioOf(
      context,
    );

    final int mobileDecodeWidth =
        (readerWidth * devicePixelRatio)
            .round()
            .clamp(720, 1440);

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
                return Listener(
                  onPointerSignal: handlePointerSignal,
                  child: GestureDetector(
                    behavior:
                        HitTestBehavior.translucent,
                  onTap:
                      toggleInterface,
                  onDoubleTap:
                      toggleDoubleTapZoom,
                  child: InteractiveViewer(
                    transformationController:
                        transformationController,

                    // No desktop a roda normal continua dedicada
                    // ao scroll vertical. Segurando Ctrl, a roda
                    // controla o zoom da imagem.
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
                            : desktop
                                ? const ClampingScrollPhysics()
                                : const BouncingScrollPhysics(
                                    parent:
                                        AlwaysScrollableScrollPhysics(),
                                  ),
                        itemBuilder: (
                          context,
                          index,
                        ) {
                          final MangaPage page =
                              widget.pages[index];

                          final Widget pageImage =
                              RepaintBoundary(
                            child: SizedBox(
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
                                        desktop
                                            ? FilterQuality.medium
                                            : FilterQuality.low,
                                    cacheWidth:
                                        desktop
                                            ? null
                                            : mobileDecodeWidth,
                                  ),
                                ),
                              ),
                            ),
                          );

                          if (index !=
                                  widget.pages.length - 1 ||
                              widget.nextItem == null) {
                            return pageImage;
                          }

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              pageImage,
                              const SizedBox(height: 28),
                              Container(
                                width: readerWidth,
                                margin: const EdgeInsets.only(
                                  bottom: 36,
                                ),
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10121A),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: const Color(0xFF292C38),
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Fim do capítulo',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      widget.nextItem!.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    FilledButton.icon(
                                      onPressed: isZoomed
                                          ? null
                                          : () => openAdjacent(
                                                widget.nextItem,
                                              ),
                                      icon: const Icon(
                                        Icons.arrow_forward_rounded,
                                      ),
                                      label: const Text(
                                        'Próximo capítulo',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
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
                          const EdgeInsets.symmetric(
                        horizontal: 8,
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
                    if (fullscreenAvailable)
                      IconButton(
                        tooltip: isFullscreen
                            ? 'Sair da tela cheia'
                            : 'Tela cheia',
                        onPressed: toggleFullscreen,
                        icon: Icon(
                          isFullscreen
                              ? Icons.fullscreen_exit
                              : Icons.fullscreen,
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