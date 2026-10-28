import 'dart:convert';

import 'package:crypto/crypto.dart';

/// SigV4 签名结果
class SigV4Signature {
  /// Authorization 头的内容
  final String authorization;

  /// 实际需要发送的请求头（含传入的签名头、x-amz-date 与 authorization）
  final Map<String, String> headers;

  /// 规范化请求，便于排查签名不一致的问题
  final String canonicalRequest;

  /// 待签名字符串
  final String stringToSign;

  const SigV4Signature({
    required this.authorization,
    required this.headers,
    required this.canonicalRequest,
    required this.stringToSign,
  });
}

/// AWS Signature Version 4 签名器
///
/// 只实现对象存储需要的「Authorization 头 + 单块负载」签名流程，
/// 与具体协议无关，便于单独验证算法正确性
class SigV4Signer {
  const SigV4Signer({
    required this.accessKey,
    required this.secretKey,
    required this.region,
    this.service = 's3',
    this.sessionToken = '',
  });

  /// Access Key
  final String accessKey;

  /// Secret Key
  final String secretKey;

  /// 区域
  final String region;

  /// 服务名（对象存储固定为 s3）
  final String service;

  /// 临时凭据的会话令牌，使用长期密钥时为空
  final String sessionToken;

  /// 计算签名
  ///
  /// [canonicalPath] 已按 RFC3986 逐段编码
  /// [canonicalQuery] 已按键名排序并编码
  /// [headers] 参与签名的请求头，键必须是小写；host 必须包含在内
  /// [payloadHash] 负载的 SHA256 十六进制摘要
  SigV4Signature sign({
    required String method,
    required String canonicalPath,
    required String canonicalQuery,
    required Map<String, String> headers,
    required String payloadHash,
    required DateTime timestamp,
  }) {
    final utc = timestamp.toUtc();
    final amzDate = amzDateOf(utc);
    final dateStamp = dateStampOf(utc);
    final scope = '$dateStamp/$region/$service/aws4_request';

    final signable = <String, String>{
      for (final entry in headers.entries) entry.key.toLowerCase(): entry.value,
      'x-amz-date': amzDate,
      if (sessionToken.isNotEmpty) 'x-amz-security-token': sessionToken,
    };
    final signedNames = signable.keys.toList()..sort();
    final canonicalHeaders = signedNames
        .map((name) => '$name:${signable[name]!.trim()}\n')
        .join();
    final signedHeaders = signedNames.join(';');

    final canonicalRequest = [
      method,
      canonicalPath,
      canonicalQuery,
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');

    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      scope,
      sha256Hex(utf8.encode(canonicalRequest)),
    ].join('\n');

    final signature = Hmac(
      sha256,
      _signingKeyOf(dateStamp),
    ).convert(utf8.encode(stringToSign)).toString();

    final authorization =
        'AWS4-HMAC-SHA256 Credential=$accessKey/$scope, '
        'SignedHeaders=$signedHeaders, Signature=$signature';

    return SigV4Signature(
      authorization: authorization,
      headers: {
        // host 由 HTTP 客户端根据请求地址自动生成，这里不再重复下发
        for (final entry in signable.entries)
          if (entry.key != 'x-amz-date' && entry.key != 'host')
            entry.key: entry.value,
        'x-amz-date': amzDate,
        'authorization': authorization,
      },
      canonicalRequest: canonicalRequest,
      stringToSign: stringToSign,
    );
  }

  /// 生成签名密钥（日期 → 区域 → 服务 → 终止串的逐级 HMAC）
  List<int> _signingKeyOf(String dateStamp) {
    List<int> sign(List<int> key, String data) =>
        Hmac(sha256, key).convert(utf8.encode(data)).bytes;

    final dateKey = sign(utf8.encode('AWS4$secretKey'), dateStamp);
    final regionKey = sign(dateKey, region);
    final serviceKey = sign(regionKey, service);
    return sign(serviceKey, 'aws4_request');
  }
}

/// 计算 SHA256 十六进制摘要
String sha256Hex(List<int> data) => sha256.convert(data).toString();

/// 生成 SigV4 时间戳（yyyyMMddTHHmmssZ）
String amzDateOf(DateTime utc) =>
    '${dateStampOf(utc)}T'
    '${_twoDigits(utc.hour)}${_twoDigits(utc.minute)}'
    '${_twoDigits(utc.second)}Z';

/// 生成日期戳（yyyyMMdd）
String dateStampOf(DateTime utc) =>
    '${utc.year}${_twoDigits(utc.month)}${_twoDigits(utc.day)}';

String _twoDigits(int value) => value.toString().padLeft(2, '0');

/// RFC3986 编码：仅保留非保留字符
///
/// 对象键中可能出现中文书名等非 ASCII 字符，必须按字节逐个编码；
/// `Uri.encodeComponent` 会保留 `!*'()` 等字符，与 SigV4 的规范不一致
String encodeRfc3986(String value) {
  final buffer = StringBuffer();
  for (final byte in utf8.encode(value)) {
    final isUnreserved =
        (byte >= 0x41 && byte <= 0x5A) ||
        (byte >= 0x61 && byte <= 0x7A) ||
        (byte >= 0x30 && byte <= 0x39) ||
        byte == 0x2D ||
        byte == 0x2E ||
        byte == 0x5F ||
        byte == 0x7E;
    if (isUnreserved) {
      buffer.writeCharCode(byte);
    } else {
      buffer.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return buffer.toString();
}

/// 规范化查询串：按键名排序，键与值都做 RFC3986 编码
String canonicalQueryOf(Map<String, String> query) {
  if (query.isEmpty) return '';
  final keys = query.keys.toList()..sort();
  return keys
      .map((key) => '${encodeRfc3986(key)}=${encodeRfc3986(query[key]!)}')
      .join('&');
}
