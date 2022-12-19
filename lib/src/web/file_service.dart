import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;
import 'mime_converter.dart';
import 'package:pointycastle/pointycastle.dart';
import 'package:pointycastle/block/modes/ecb.dart';
import 'package:pointycastle/export.dart';
///Flutter Cache Manager
///Copyright (c) 2019 Rene Floor
///Released under MIT License.

/// Defines the interface for a file service.
/// Most common file service will be an [HttpFileService], however one can
/// also make something more specialized. For example you could fetch files
/// from other apps or from local storage.
abstract class FileService {
  int concurrentFetches = 10;
  Future<FileServiceResponse> get(String url, {Map<String, String>? headers});
}

/// [HttpFileService] is the most common file service and the default for
/// [WebHelper]. One can easily adapt it to use dio or any other http client.
class HttpFileService extends FileService {
  final http.Client _httpClient;

  HttpFileService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  @override
  Future<FileServiceResponse> get(String url,
      {Map<String, String>? headers}) async {
    String newUrl=url;
    String encryptType='';
    if(url.contains('.bnc')){
      encryptType='xingba';
    }
    final req = http.Request('GET', Uri.parse(newUrl));
    if (headers != null) {
      req.headers.addAll(headers);
    }
    final httpResponse = await _httpClient.send(req);
    http.StreamedResponse newResponse=httpResponse;

    Uint8List encryptedData=await httpResponse.stream.toBytes();
    //解密
    if(encryptType=='xingba'){
      // 定义加密密钥
      final key = KeyParameter(Uint8List.fromList(utf8.encode('525202f9149e061d')));
      // 创建ECB block cipher实例
      final cipher = ECBBlockCipher(AESEngine());
      // 初始化cipher为解密模式
      cipher.init(false, key);
      // 解密数据
      final paddedPlainText = Uint8List(encryptedData.length); // allocate space
      var offset = 0;
      while (offset < encryptedData.length) {
        offset += cipher.processBlock(encryptedData, offset, paddedPlainText, offset);
      }

      //重新赋值
      newResponse=http.StreamedResponse(
          http.ByteStream.fromBytes(paddedPlainText),
          httpResponse.statusCode,
          contentLength:httpResponse.contentLength,
          request:httpResponse.request,
          headers:httpResponse.headers,
          isRedirect:httpResponse.isRedirect,
          persistentConnection:httpResponse.persistentConnection,
          reasonPhrase:httpResponse.reasonPhrase
      );
    }


    return HttpGetResponse(newResponse);
  }
}

/// Defines the interface for a get result of a [FileService].
abstract class FileServiceResponse {
  /// [content] is a stream of bytes
  Stream<List<int>> get content;

  /// [contentLength] is the total size of the content.
  /// If the size is not known beforehand contentLength is null.
  int? get contentLength;

  /// [statusCode] is expected to conform to an http status code.
  int get statusCode;

  /// Defines till when the cache should be assumed to be valid.
  DateTime get validTill;

  /// [eTag] is used when asking to update the cache
  String? get eTag;

  /// Used to save the file on the storage, includes a dot. For example '.jpeg'
  String get fileExtension;
}

/// Basic implementation of a [FileServiceResponse] for http requests.
class HttpGetResponse implements FileServiceResponse {
  HttpGetResponse(this._response);

  final DateTime _receivedTime = clock.now();

  final http.StreamedResponse _response;

  @override
  int get statusCode => _response.statusCode;

  String? _header(String name) {
    return _response.headers[name];
  }

  @override
  Stream<List<int>> get content => _response.stream;

  @override
  int? get contentLength => _response.contentLength;

  @override
  DateTime get validTill {
    // Without a cache-control header we keep the file for a week
    var ageDuration = const Duration(days: 7);
    final controlHeader = _header(HttpHeaders.cacheControlHeader);
    if (controlHeader != null) {
      final controlSettings = controlHeader.split(',');
      for (final setting in controlSettings) {
        final sanitizedSetting = setting.trim().toLowerCase();
        if (sanitizedSetting == 'no-cache') {
          ageDuration = const Duration();
        }
        if (sanitizedSetting.startsWith('max-age=')) {
          var validSeconds = int.tryParse(sanitizedSetting.split('=')[1]) ?? 0;
          if (validSeconds > 0) {
            ageDuration = Duration(seconds: validSeconds);
          }
        }
      }
    }

    return _receivedTime.add(ageDuration);
  }

  @override
  String? get eTag => _header(HttpHeaders.etagHeader);

  @override
  String get fileExtension {
    var fileExtension = '';
    final contentTypeHeader = _header(HttpHeaders.contentTypeHeader);
    if (contentTypeHeader != null) {
      final contentType = ContentType.parse(contentTypeHeader);
      fileExtension = contentType.fileExtension;
    }
    return fileExtension;
  }
}
