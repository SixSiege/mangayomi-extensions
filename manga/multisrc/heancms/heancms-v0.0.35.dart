import 'package:mangayomi/bridge_lib.dart';
import 'dart:convert';

class HeanCms extends MProvider {
  HeanCms();

  @override
  Future<MPages> getPopular(MSource source, int page) async {
    final headers = getHeader(source.baseUrl);
    String res = "";
    if (!useNewQueryEndpoint(source.name)) {
      final url = "${source.apiUrl}/series/querysearch";

      final body = {
        "page": page,
        "order": "desc",
        "order_by": "total_views",
        "series_status": "Ongoing",
        "series_type": "Comic"
      };
      final data = {"url": url, "headers": headers, "body": body};
      res = await http('POST', json.encode(data));
    } else {
      final newEndpointUrl =
          "${source.apiUrl}/query/?page=$page&query_string=&series_status=All&order=desc&orderBy=total_views&perPage=12&tags_ids=[]&series_type=Comic";

      final newEndpointData = {"url": newEndpointUrl, "headers": headers};
      res = await http('GET', json.encode(newEndpointData));
    }
    return mMangaRes(res, source);
  }

  @override
  Future<MPages> getLatestUpdates(MSource source, int page) async {
    final headers = getHeader(source.baseUrl);
    String res = "";
    if (!useNewQueryEndpoint(source.name)) {
      final url = "${source.apiUrl}/series/querysearch";
      final body = {
        "page": page,
        "order": "desc",
        "order_by": "latest",
        "series_status": "Ongoing",
        "series_type": "Comic"
      };
      final data = {"url": url, "headers": headers, "body": body};
      res = await http('POST', json.encode(data));
    } else {
      final newEndpointUrl =
          "${source.apiUrl}/query/?page=$page&query_string=&series_status=All&order=desc&orderBy=latest&perPage=12&tags_ids=[]&series_type=Comic";

      final newEndpointData = {"url": newEndpointUrl, "headers": headers};
      res = await http('GET', json.encode(newEndpointData));
    }
    return mMangaRes(res, source);
  }

  @override
  Future<MPages> search(MSource source, String query, int page) async {
    final headers = getHeader(source.baseUrl);
    String res = "";
    if (!useNewQueryEndpoint(source.source)) {
      final url = "${source.apiUrl}/series/search";
      final body = {"term": query};
      final data = {"url": url, "headers": headers, "body": body};
      res = await http('POST', json.encode(data));
    } else {
      final newEndpointUrl =
          "${source.apiUrl}/query/?page=$page&query_string=$query&series_status=All&order=desc&orderBy=total_views&perPage=12&tags_ids=[]&series_type=Comic";

      final newEndpointData = {"url": newEndpointUrl, "headers": headers};
      res = await http('GET', json.encode(newEndpointData));
    }
    return mMangaRes(res, source);
  }

  @override
  Future<MManga> getDetail(MSource source, String url) async {
    MManga manga = MManga();
    String currentSlug = substringAfterLast(url, "/");
    final headers = getHeader(source.baseUrl);
    final data = {
      "url": "${source.apiUrl}/series/$currentSlug",
      "headers": headers
    };
    final res = await http('GET', json.encode(data));
    manga.author = getMapValue(res, "author");
    manga.description = getMapValue(res, "description");
    manga.genre = jsonPathToString(res, r"$.tags[*].name", "._").split("._");
    List<String> chapterTitles = [];
    List<String> chapterUrls = [];
    List<String> chapterDates = [];

    if (!useNewQueryEndpoint(source.name)) {
      for (var chapter in json.decode(res)["chapters"]) {
        final chapterName = chapter["chapter_name"];
        final chapterSlug = chapter["chapter_slug"];
        final chapterId = chapter["id"];
        final createdAt = chapter["created_at"];
        chapterUrls.add("/series/$currentSlug/$chapterSlug#$chapterId");
        chapterTitles.add(chapterName);
        chapterDates.add(createdAt);
      }
    } else {
      final seasons = json.decode(res)["seasons"].first;
      for (var chapter in seasons["chapters"]) {
        final chapterName = chapter["chapter_name"];
        final chapterSlug = chapter["chapter_slug"];
        final chapterId = chapter["id"];
        final createdAt = chapter["created_at"];
        chapterUrls.add("/series/$currentSlug/$chapterSlug#$chapterId");
        chapterTitles.add(chapterName);
        chapterDates.add(createdAt);
      }
    }
    final dateUploads = parseDates(chapterDates, "dd MMMM yyyy", "fr");
    List<MChapter>? chaptersList = [];
    for (var i = 0; i < chapterTitles.length; i++) {
      MChapter chapter = MChapter();
      chapter.name = chapterTitles[i];
      chapter.url = chapterUrls[i];
      chapter.dateUpload = dateUploads[i];
      chaptersList.add(chapter);
    }
    if (!useNewQueryEndpoint(source.name)) {
      chaptersList = chaptersList.reversed.toList();
    }

    manga.chapters = chaptersList;
    return manga;
  }

  @override
  Future<List<String>> getPageList(MSource source, String url) async {
    final headers = getHeader(source.baseUrl);

    String res = "".toString();
    if (!useslugStrategy(source.name)) {
      String chapterId = substringAfter(url, '#');
      final data = {
        "url": "${source.apiUrl}/series/chapter/$chapterId",
        "headers": headers
      };
      res = await http('GET', json.encode(data));
    } else {
      final data = {"url": "${source.baseUrl}$url", "headers": headers};
      res = await http('GET', json.encode(data));

      List<String> pageUrls = [];
      var imagesRes = querySelectorAll(res,
          selector: "div.min-h-screen > div.container > p.items-center",
          typeElement: 1,
          attributes: "",
          typeRegExp: 0);
      pageUrls = xpath(imagesRes.first, '//img/@src');

      pageUrls.addAll(xpath(imagesRes.first, '//img/@data-src'));

      return pageUrls.where((e) => e.isNotEmpty).toList();
    }

    final pages = jsonPathToList(res, r"$.content.images[*]", 0);
    List<String> pageUrls = [];
    for (var u in pages) {
      final url = u.replaceAll('"', "");
      if (url.startsWith("http")) {
        pageUrls.add(url);
      } else {
        pageUrls.add("${source.apiUrl}/$url");
      }
    }
    return pageUrls;
  }

  MPages mMangaRes(String res, MSource source) {
    bool hasNextPage = true;
    List<MManga> mangaList = [];
    List<String> names = [];
    List<String> urls = [];
    List<String> images = [];
    if (res.startsWith("{")) {
      for (var a in json.decode(res)["data"]) {
        String thumbnail = a["thumbnail"];
        if (thumbnail.startsWith("https://")) {
          images.add(thumbnail);
        } else {
          images.add("${source.apiUrl}/cover/$thumbnail");
        }
        names.add(a["title"]);
        final seriesSlug = a["series_slug"];
        urls.add("/series/$seriesSlug");
      }
    } else {
      for (var a in json.decode(res)) {
        String thumbnail = a["thumbnail"];
        if (thumbnail.startsWith("https://")) {
          images.add(thumbnail);
        } else {
          images.add("${source.apiUrl}/cover/$thumbnail");
        }
        names.add(a["title"]);
        final seriesSlug = a["series_slug"];
        urls.add("/series/$seriesSlug");
      }
      hasNextPage = false;
    }

    for (var i = 0; i < names.length; i++) {
      MManga manga = MManga();
      manga.name = names[i];
      manga.imageUrl = images[i];
      manga.link = urls[i];
      mangaList.add(manga);
    }
    return MPages(mangaList, hasNextPage);
  }

  bool useNewQueryEndpoint(String sourceName) {
    List<String> sources = ["YugenMangas", "Perf Scan", "Reaper Scans"];
    return sources.contains(sourceName);
  }

  bool useslugStrategy(String sourceName) {
    List<String> sources = ["YugenMangas", "Reaper Scans", "Perf Scan"];
    return sources.contains(sourceName);
  }
}

Map<String, String> getHeader(String url) {
  final headers = {
    'Origin': url,
    'Referer': '$url/',
    'Accept': 'application/json, text/plain, */*',
    'Content-Type': 'application/json'
  };
  return headers;
}

HeanCms main() {
  return HeanCms();
}
