import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> readLocalFileBytes(
  String path,
) {
  return File(path).readAsBytes();
}

String _coverKey(String value) {
  return value
      .toLowerCase()
      .replaceAll(
        RegExp(r'[^a-z0-9]+'),
        '',
      );
}

Future<Uint8List?> readSeriesCoverBytes(
  String folderPath,
  String seriesName,
) async {
  final Directory directory =
      Directory(folderPath);

  if (!await directory.exists()) {
    return null;
  }

  final String cleanSeries =
      seriesName.trim();

  final String wantedKey =
      _coverKey(cleanSeries);

  if (cleanSeries.isEmpty ||
      wantedKey.isEmpty) {
    return null;
  }

  final List<String> extensions = [
    'png',
    'webp',
    'jpg',
    'jpeg',
  ];

  final String hyphenName =
      cleanSeries.replaceAll(
    RegExp(r'\s+'),
    '-',
  );

  final String underscoreName =
      cleanSeries.replaceAll(
    RegExp(r'\s+'),
    '_',
  );

  final List<String> bases = [
    cleanSeries,
    hyphenName,
    underscoreName,
    '$cleanSeries capa',
    'capa $cleanSeries',
    '$hyphenName-capa',
    'capa-$hyphenName',
  ];

  // Tentativas diretas. Isso cobre exatamente:
  // Blue-Lock.png e One-Piece.png.
  for (final String base in bases) {
    for (final String extension
        in extensions) {
      final File file = File(
        '${directory.path}'
        '${Platform.pathSeparator}'
        '$base.$extension',
      );

      if (!await file.exists()) {
        continue;
      }

      final Uint8List bytes =
          await file.readAsBytes();

      if (bytes.isNotEmpty) {
        return bytes;
      }
    }
  }

  // Fallback: percorre toda a pasta e compara por nome normalizado.
  await for (final FileSystemEntity entity
      in directory.list(
    followLinks: false,
  )) {
    if (entity is! File) {
      continue;
    }

    final String fileName =
        entity.path
            .split(
              Platform.pathSeparator,
            )
            .last;

    final int dot =
        fileName.lastIndexOf('.');

    if (dot <= 0) {
      continue;
    }

    final String extension =
        fileName
            .substring(dot + 1)
            .toLowerCase();

    if (!extensions.contains(
      extension,
    )) {
      continue;
    }

    String base =
        fileName.substring(
      0,
      dot,
    );

    base = base
        .replaceFirst(
          RegExp(
            r'^\s*capa[\s_-]*',
            caseSensitive: false,
          ),
          '',
        )
        .replaceFirst(
          RegExp(
            r'[\s_-]*capa\s*$',
            caseSensitive: false,
          ),
          '',
        );

    if (_coverKey(base) !=
        wantedKey) {
      continue;
    }

    final Uint8List bytes =
        await entity.readAsBytes();

    if (bytes.isNotEmpty) {
      return bytes;
    }
  }

  return null;
}
